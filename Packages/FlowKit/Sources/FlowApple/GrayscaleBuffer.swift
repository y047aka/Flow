#if canImport(CoreGraphics)
import CoreGraphics
import FlowCore
import Foundation

/// 解析用の 8bit グレースケール画素バッファ（ガンマ 2.2）。
struct GrayscaleBuffer {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init?(image: CGImage, maximumDimension: Int) {
        let scale = min(1, Double(maximumDimension) / Double(max(image.width, image.height)))
        let w = max(1, Int(Double(image.width) * scale))
        let h = max(1, Int(Double(image.height) * scale))
        guard let space = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2),
              let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = context.data else { return nil }
        // 行末にパディングが入ることがあるので、行ごとに詰めてコピーする。
        let stride = context.bytesPerRow
        let base = data.bindMemory(to: UInt8.self, capacity: stride * h)
        var pixels = [UInt8]()
        pixels.reserveCapacity(w * h)
        for y in 0..<h {
            pixels.append(contentsOf: UnsafeBufferPointer(start: base + y * stride, count: w))
        }
        self.width = w
        self.height = h
        self.pixels = pixels
    }

    var histogram: LuminanceHistogram {
        var bins = [Int](repeating: 0, count: 256)
        for p in pixels { bins[Int(p)] += 1 }
        return LuminanceHistogram(bins: bins)
    }

    /// ラプラシアンの分散（ピント・ブレの指標）。大きいほどシャープ。
    var laplacianVariance: Double {
        guard width > 2, height > 2 else { return 0 }
        var sum = 0.0, sumSq = 0.0
        var n = 0
        for y in 1..<(height - 1) {
            let row = y * width
            for x in 1..<(width - 1) {
                let i = row + x
                let v = 4 * Int(pixels[i]) - Int(pixels[i - 1]) - Int(pixels[i + 1]) - Int(pixels[i - width]) - Int(pixels[i + width])
                let d = Double(v)
                sum += d
                sumSq += d * d
                n += 1
            }
        }
        let mean = sum / Double(n)
        return sumSq / Double(n) - mean * mean
    }

    /// 0...1 に正規化したシャープネス。`halfPoint` の分散で約 0.63 になる。
    /// 縮小プレビュー上での値なので、厳密なピント判定には主要被写体の切り抜きで測るのが望ましい。
    func normalizedSharpness(halfPoint: Double = 300) -> Float {
        Float(1 - exp(-laplacianVariance / halfPoint))
    }
}
#endif
