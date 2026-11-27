#if canImport(CoreImage)
import CoreImage
import CoreImage.CIFilterBuiltins
import FlowCore
import Foundation
import ImageIO

/// Core Image の CIRAWFilter（Apple 純正 RAW エンジン、GPU 処理）でレシピどおりに現像する。
///
/// 現像は「RAW デコード → 調整関数の合成」として表す。
/// 調整はそれぞれ `CIImage -> CIImage` の純粋関数で、レシピから必要なものだけを選んで順に適用する。
public final class CoreImageRAWDeveloper: ToneMeasuring, PhotoExporting, @unchecked Sendable {
    public typealias Adjustment = (CIImage) -> CIImage

    // CIContext はスレッドセーフで、生成コストが高いので使い回す。
    private let context = CIContext(options: [.cacheIntermediates: false])

    public init() {}

    // MARK: - 現像

    /// - Parameters:
    ///   - maximumPixelSize: 長辺の最大ピクセル数。nil なら原寸。プレビューでは小さく指定して高速化する。
    ///   - draft: 品質を落として高速化する（解析用）。
    public func developedImage(url: URL, recipe: DevelopRecipe, maximumPixelSize: Int? = nil, draft: Bool = false) throws -> CIImage {
        guard let decoded = try Self.rawFilter(url: url, recipe: recipe, maximumPixelSize: maximumPixelSize, draft: draft).outputImage else {
            throw FlowAppleError.renderFailed(url)
        }
        return Self.adjustments(for: recipe).reduce(decoded) { image, adjust in adjust(image) }
    }

    /// RAW 段階の処理（リニアなセンサーデータに対して効かせる）を設定した CIRAWFilter。
    /// CIRAWFilter はプロパティを書き換えて設定する API なので、設定はこの関数の中に閉じ込める。
    static func rawFilter(url: URL, recipe: DevelopRecipe, maximumPixelSize: Int?, draft: Bool) throws -> CIRAWFilter {
        guard let raw = CIRAWFilter(imageURL: url) else { throw FlowAppleError.unsupportedRAW(url) }
        raw.isDraftModeEnabled = draft
        raw.scaleFactor = Float(scaleFactor(nativeSize: raw.nativeSize, maximumPixelSize: maximumPixelSize))
        raw.exposure = Float(recipe.exposure)
        if case let .custom(temperature, tint) = recipe.whiteBalance {
            raw.neutralTemperature = Float(temperature)
            raw.neutralTint = Float(tint)
        }
        if raw.isLensCorrectionSupported { raw.isLensCorrectionEnabled = recipe.lensCorrection }
        if let nr = recipe.noiseReduction, raw.isLuminanceNoiseReductionSupported { raw.luminanceNoiseReductionAmount = Float(nr) }
        if let sharpness = recipe.sharpness, raw.isSharpnessSupported { raw.sharpnessAmount = Float(sharpness) }
        return raw
    }

    static func scaleFactor(nativeSize: CGSize, maximumPixelSize: Int?) -> Double {
        let native = max(nativeSize.width, nativeSize.height)
        guard let maximumPixelSize, native > 0 else { return 1 }
        return min(1, Double(maximumPixelSize) / native)
    }

    /// レシピのうち「何もしない」以外の項目に対応する調整を、適用順に並べたもの。
    static func adjustments(for recipe: DevelopRecipe) -> [Adjustment] {
        let candidates: [Adjustment?] = [
            recipe.highlights > 0 || recipe.shadows > 0
                ? highlightShadow(highlights: recipe.highlights, shadows: recipe.shadows) : nil,
            recipe.vibrance != 0
                ? vibrance(recipe.vibrance) : nil,
            recipe.contrast != 0 || recipe.saturation != 0 || recipe.monochrome
                ? colorControls(contrast: recipe.contrast, saturation: recipe.monochrome ? -1 : recipe.saturation) : nil,
        ]
        return candidates.compactMap { $0 }
    }

    static func highlightShadow(highlights: Double, shadows: Double) -> Adjustment {
        { image in
            let filter = CIFilter.highlightShadowAdjust()
            filter.inputImage = image
            filter.highlightAmount = Float(1 - highlights) // 1 = 変化なし、小さいほど抑制
            filter.shadowAmount = Float(shadows)           // 0 = 変化なし
            return filter.outputImage ?? image
        }
    }

    static func vibrance(_ amount: Double) -> Adjustment {
        { image in
            let filter = CIFilter.vibrance()
            filter.inputImage = image
            filter.amount = Float(amount)
            return filter.outputImage ?? image
        }
    }

    /// - Parameter saturation: -1 でモノクロ、0 で変化なし。
    static func colorControls(contrast: Double, saturation: Double) -> Adjustment {
        { image in
            // TODO: コントラストは知覚的に均等なトーンカーブ（CIToneCurve など）に置き換えると、より自然になる。
            let filter = CIFilter.colorControls()
            filter.inputImage = image
            filter.contrast = Float(1 + contrast * 0.3)
            filter.saturation = Float(1 + saturation)
            return filter.outputImage ?? image
        }
    }

    // MARK: - レンダリング

    /// 画面表示用に現像済みの CGImage を作る。
    public func renderPreview(url: URL, recipe: DevelopRecipe, maximumPixelSize: Int) throws -> CGImage {
        try render(developedImage(url: url, recipe: recipe, maximumPixelSize: maximumPixelSize), colorSpace: CGColorSpace.displayP3, url: url)
    }

    private func render(_ image: CIImage, colorSpace name: CFString, url: URL) throws -> CGImage {
        guard let space = CGColorSpace(name: name),
              let cgImage = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: space) else {
            throw FlowAppleError.renderFailed(url)
        }
        return cgImage
    }

    // MARK: - ToneMeasuring

    public func luminanceHistogram(for asset: PhotoAsset) async throws -> LuminanceHistogram {
        let url = asset.fileURL
        let image = try developedImage(url: url, recipe: DevelopRecipe(), maximumPixelSize: 512, draft: true)
        guard let gray = GrayscaleBuffer(image: try render(image, colorSpace: CGColorSpace.sRGB, url: url), maximumDimension: 512) else {
            throw FlowAppleError.renderFailed(url)
        }
        return gray.histogram
    }

    // MARK: - PhotoExporting

    public func export(_ asset: PhotoAsset, recipe: DevelopRecipe, options: ExportOptions, to destination: URL) async throws {
        let image = try developedImage(url: asset.fileURL, recipe: recipe, maximumPixelSize: options.maximumPixelSize)
        guard let space = CGColorSpace(name: options.colorSpace == .sRGB ? CGColorSpace.sRGB : CGColorSpace.displayP3) else {
            throw FlowAppleError.renderFailed(asset.fileURL)
        }
        let quality: [CIImageRepresentationOption: Any] = [
            CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): options.quality,
        ]

        // TODO: 元 RAW の EXIF / GPS を書き出しファイルへコピーする（CGImageDestination で書き直す）。
        switch options.format {
        case .heic:
            try context.writeHEIFRepresentation(of: image, to: destination, format: .RGBA8, colorSpace: space, options: quality)
        case .jpeg:
            try context.writeJPEGRepresentation(of: image, to: destination, colorSpace: space, options: quality)
        case .tiff16:
            try context.writeTIFFRepresentation(of: image, to: destination, format: .RGBA16, colorSpace: space, options: [:])
        }
    }
}
#endif
