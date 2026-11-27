#if canImport(ImageIO)
import CoreGraphics
import Foundation
import ImageIO

/// RAW に埋め込まれた JPEG プレビューを取り出す。RAW デコードより桁違いに速いので、
/// サムネイル表示と画像解析はこちらを使う。
public struct PreviewImageLoader: Sendable {
    public let maximumPixelSize: Int

    public init(maximumPixelSize: Int = 1024) {
        self.maximumPixelSize = maximumPixelSize
    }

    public func loadPreview(at url: URL, maximumPixelSize: Int? = nil) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw FlowAppleError.cannotOpen(url)
        }
        let options: [CFString: Any] = [
            // 埋め込みプレビューがあればそれを使い、無い場合のみ本体から生成する。
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            // EXIF の回転を適用する。
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize ?? self.maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw FlowAppleError.noPreview(url)
        }
        return image
    }
}
#endif
