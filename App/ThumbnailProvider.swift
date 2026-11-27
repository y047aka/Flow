import CoreGraphics
import FlowApple
import Foundation

/// 埋め込みプレビューからサムネイルを読み込み、メモリにキャッシュする。
actor ThumbnailProvider {
    private let loader = PreviewImageLoader(maximumPixelSize: 512)
    private let cache = NSCache<NSURL, CGImage>()

    init() {
        cache.countLimit = 600
    }

    func thumbnail(for url: URL) -> CGImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        guard let image = try? loader.loadPreview(at: url) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}
