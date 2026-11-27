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
    public let exposure: Double
    public let whiteBalance: WhiteBalance
    /// ハイライトの抑制量 0...1。
    public let highlights: Double
    /// シャドウの持ち上げ量 0...1。
    public let shadows: Double
    /// コントラスト -1...1。
    public let contrast: Double
    /// 彩度 -1...1。
    public let saturation: Double
    /// 自然な彩度 -1...1。
    public let vibrance: Double
    /// 輝度ノイズ低減 0...1。nil ならカメラ / OS の既定値。
    public let noiseReduction: Double?
    /// シャープネス 0...1。nil ならカメラ / OS の既定値。
    public let sharpness: Double?
    public let lensCorrection: Bool
    public let monochrome: Bool

    public init(
        exposure: Double = 0,
        whiteBalance: WhiteBalance = .asShot,
        highlights: Double = 0,
        shadows: Double = 0,
        contrast: Double = 0,
        saturation: Double = 0,
        vibrance: Double = 0,
        noiseReduction: Double? = nil,
        sharpness: Double? = nil,
        lensCorrection: Bool = true,
        monochrome: Bool = false
    ) {
        self.exposure = exposure
        self.whiteBalance = whiteBalance
        self.highlights = highlights
        self.shadows = shadows
        self.contrast = contrast
        self.saturation = saturation
        self.vibrance = vibrance
        self.noiseReduction = noiseReduction
        self.sharpness = sharpness
        self.lensCorrection = lensCorrection
        self.monochrome = monochrome
    }

    /// 範囲外の値を丸めたレシピ。
    public func clamped() -> DevelopRecipe {
        DevelopRecipe(
            exposure: exposure.clamped(to: -5...5),
            whiteBalance: whiteBalance,
            highlights: highlights.clamped(to: 0...1),
            shadows: shadows.clamped(to: 0...1),
            contrast: contrast.clamped(to: -1...1),
            saturation: saturation.clamped(to: -1...1),
            vibrance: vibrance.clamped(to: -1...1),
            noiseReduction: noiseReduction?.clamped(to: 0...1),
            sharpness: sharpness?.clamped(to: 0...1),
            lensCorrection: lensCorrection,
            monochrome: monochrome
        )
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
