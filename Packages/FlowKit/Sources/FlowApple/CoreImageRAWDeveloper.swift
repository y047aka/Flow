#if canImport(CoreImage)
import CoreImage
import CoreImage.CIFilterBuiltins
import FlowCore
import Foundation
import ImageIO

/// Core Image の CIRAWFilter（Apple 純正 RAW エンジン、GPU 処理）でレシピどおりに現像する。
public final class CoreImageRAWDeveloper: ToneMeasuring, PhotoExporting, @unchecked Sendable {
    // CIContext はスレッドセーフで、生成コストが高いので使い回す。
    private let context: CIContext

    public init() {
        context = CIContext(options: [.cacheIntermediates: false])
    }

    // MARK: - 現像

    /// - Parameters:
    ///   - maximumPixelSize: 長辺の最大ピクセル数。nil なら原寸。プレビューでは小さく指定して高速化する。
    ///   - draft: 品質を落として高速化する（解析用）。
    public func developedImage(url: URL, recipe: DevelopRecipe, maximumPixelSize: Int? = nil, draft: Bool = false) throws -> CIImage {
        guard let raw = CIRAWFilter(imageURL: url) else { throw FlowAppleError.unsupportedRAW(url) }

        raw.isDraftModeEnabled = draft
        if let maximumPixelSize {
            let native = max(raw.nativeSize.width, raw.nativeSize.height)
            if native > 0 { raw.scaleFactor = Float(min(1, Double(maximumPixelSize) / native)) }
        }

        // --- RAW 段階の処理（リニアなセンサーデータに対して効かせる）
        raw.exposure = Float(recipe.exposure)
        if case let .custom(temperature, tint) = recipe.whiteBalance {
            raw.neutralTemperature = Float(temperature)
            raw.neutralTint = Float(tint)
        }
        if raw.isLensCorrectionSupported { raw.isLensCorrectionEnabled = recipe.lensCorrection }
        if let nr = recipe.noiseReduction, raw.isLuminanceNoiseReductionSupported {
            raw.luminanceNoiseReductionAmount = Float(nr)
        }
        if let sharpness = recipe.sharpness, raw.isSharpnessSupported {
            raw.sharpnessAmount = Float(sharpness)
        }

        guard var image = raw.outputImage else { throw FlowAppleError.renderFailed(url) }

        // --- 現像後の調整
        if recipe.highlights > 0 || recipe.shadows > 0 {
            let filter = CIFilter.highlightShadowAdjust()
            filter.inputImage = image
            filter.highlightAmount = Float(1 - recipe.highlights) // 1 = 変化なし、小さいほど抑制
            filter.shadowAmount = Float(recipe.shadows)           // 0 = 変化なし
            image = filter.outputImage ?? image
        }
        if recipe.vibrance != 0 {
            let filter = CIFilter.vibrance()
            filter.inputImage = image
            filter.amount = Float(recipe.vibrance)
            image = filter.outputImage ?? image
        }
        if recipe.contrast != 0 || recipe.saturation != 0 || recipe.monochrome {
            // TODO: コントラストは知覚的に均等なトーンカーブ（CIToneCurve など）に置き換えると、より自然になる。
            let filter = CIFilter.colorControls()
            filter.inputImage = image
            filter.contrast = Float(1 + recipe.contrast * 0.3)
            filter.saturation = recipe.monochrome ? 0 : Float(1 + recipe.saturation)
            image = filter.outputImage ?? image
        }
        return image
    }

    /// 画面表示用に現像済みの CGImage を作る。
    public func renderPreview(url: URL, recipe: DevelopRecipe, maximumPixelSize: Int) throws -> CGImage {
        let image = try developedImage(url: url, recipe: recipe, maximumPixelSize: maximumPixelSize)
        guard let space = CGColorSpace(name: CGColorSpace.displayP3),
              let cgImage = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: space) else {
            throw FlowAppleError.renderFailed(url)
        }
        return cgImage
    }

    // MARK: - ToneMeasuring

    public func luminanceHistogram(for asset: PhotoAsset) async throws -> LuminanceHistogram {
        let image = try developedImage(url: asset.fileURL, recipe: DevelopRecipe(), maximumPixelSize: 512, draft: true)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let cgImage = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: space),
              let gray = GrayscaleBuffer(image: cgImage, maximumDimension: 512) else {
            throw FlowAppleError.renderFailed(asset.fileURL)
        }
        return gray.histogram
    }

    // MARK: - PhotoExporting

    public func export(_ asset: PhotoAsset, recipe: DevelopRecipe, options: ExportOptions, to destination: URL) async throws {
        let image = try developedImage(url: asset.fileURL, recipe: recipe, maximumPixelSize: options.maximumPixelSize)
        let spaceName = options.colorSpace == .sRGB ? CGColorSpace.sRGB : CGColorSpace.displayP3
        guard let space = CGColorSpace(name: spaceName) else { throw FlowAppleError.renderFailed(asset.fileURL) }
        let quality = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)

        // TODO: 元 RAW の EXIF / GPS を書き出しファイルへコピーする（CGImageDestination で書き直す）。
        switch options.format {
        case .heic:
            try context.writeHEIFRepresentation(of: image, to: destination, format: .RGBA8, colorSpace: space,
                                                options: [quality: options.quality])
        case .jpeg:
            try context.writeJPEGRepresentation(of: image, to: destination, colorSpace: space,
                                                options: [quality: options.quality])
        case .tiff16:
            try context.writeTIFFRepresentation(of: image, to: destination, format: .RGBA16, colorSpace: space, options: [:])
        }
    }
}
#endif
