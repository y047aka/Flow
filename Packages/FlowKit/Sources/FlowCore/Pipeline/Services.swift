import Foundation

// プラットフォーム固有処理の抽象。Apple 版は FlowApple が実装する。
// Windows 版を作る際は LibRaw / ONNX Runtime などで同じプロトコルを実装すればよい。

/// RAW ファイルの撮影情報を読む。
public protocol MetadataReading: Sendable {
    func readMetadata(at url: URL) throws -> CaptureMetadata
}

/// 類似判定・ベストショット選定のための画像解析。高速化のため埋め込みプレビューで行う想定。
public protocol ImageAnalyzing: Sendable {
    func analyze(_ asset: PhotoAsset) async throws -> ImageAnalysis
}

/// 中立現像した縮小画像の輝度ヒストグラムを測る（自動補正の推定用）。
public protocol ToneMeasuring: Sendable {
    func luminanceHistogram(for asset: PhotoAsset) async throws -> LuminanceHistogram
}

/// レシピに従って RAW を現像し、ファイルに書き出す。
public protocol PhotoExporting: Sendable {
    func export(_ asset: PhotoAsset, recipe: DevelopRecipe, options: ExportOptions, to destination: URL) async throws
}

public struct ExportOptions: Codable, Hashable, Sendable {
    public enum Format: String, Codable, CaseIterable, Sendable {
        case heic, jpeg, tiff16

        public var fileExtension: String {
            switch self {
            case .heic: "heic"
            case .jpeg: "jpg"
            case .tiff16: "tiff"
            }
        }
    }

    public enum ColorSpace: String, Codable, CaseIterable, Sendable {
        case sRGB, displayP3
    }

    public let format: Format
    public let colorSpace: ColorSpace
    /// 非可逆圧縮の品質 0...1。
    public let quality: Double
    /// 長辺の最大ピクセル数。nil なら原寸。
    public let maximumPixelSize: Int?

    public init(format: Format = .heic, colorSpace: ColorSpace = .displayP3, quality: Double = 0.9, maximumPixelSize: Int? = nil) {
        self.format = format
        self.colorSpace = colorSpace
        self.quality = quality
        self.maximumPixelSize = maximumPixelSize
    }
}
