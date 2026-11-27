import Foundation

/// 非破壊の現像レシピ。元の RAW とこのレシピがあれば、いつでも同じ結果を再現できる。
/// 既定値はすべて「何もしない（カメラの撮って出しに近い中立な現像）」。
public struct DevelopRecipe: Codable, Hashable, Sendable {
    public enum WhiteBalance: Codable, Hashable, Sendable {
        /// カメラ記録値（As Shot）。
        case asShot
        /// 色温度（K）と色かぶり補正。
        case custom(temperature: Double, tint: Double)
    }

    /// 露出補正（EV）。カメラのベースライン露出に加算される。
    public var exposure: Double = 0
    public var whiteBalance: WhiteBalance = .asShot
    /// ハイライトの抑制量 0...1。
    public var highlights: Double = 0
    /// シャドウの持ち上げ量 0...1。
    public var shadows: Double = 0
    /// コントラスト -1...1。
    public var contrast: Double = 0
    /// 彩度 -1...1。
    public var saturation: Double = 0
    /// 自然な彩度 -1...1。
    public var vibrance: Double = 0
    /// 輝度ノイズ低減 0...1。nil ならカメラ / OS の既定値。
    public var noiseReduction: Double?
    /// シャープネス 0...1。nil ならカメラ / OS の既定値。
    public var sharpness: Double?
    public var lensCorrection: Bool = true
    public var monochrome: Bool = false

    public init() {}

    /// 範囲外の値を丸める。
    public func clamped() -> DevelopRecipe {
        var r = self
        r.exposure = r.exposure.clamped(to: -5...5)
        r.highlights = r.highlights.clamped(to: 0...1)
        r.shadows = r.shadows.clamped(to: 0...1)
        r.contrast = r.contrast.clamped(to: -1...1)
        r.saturation = r.saturation.clamped(to: -1...1)
        r.vibrance = r.vibrance.clamped(to: -1...1)
        r.noiseReduction = r.noiseReduction?.clamped(to: 0...1)
        r.sharpness = r.sharpness?.clamped(to: 0...1)
        return r
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
