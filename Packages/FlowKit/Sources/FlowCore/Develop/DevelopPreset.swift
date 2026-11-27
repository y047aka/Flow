import Foundation

/// ユーザーが選べる唯一の「現像パラメータ」。自動推定レシピの上に重ねる差分として表現する。
public struct DevelopPreset: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    /// 自動補正（露出・ハイライト・シャドウ）をどの程度効かせるか。0 で撮って出し、1 で推定値どおり。
    public let autoToneStrength: Double
    public let exposureOffset: Double
    public let contrast: Double
    public let saturation: Double
    public let vibrance: Double
    public let monochrome: Bool

    public init(
        id: String,
        name: String,
        autoToneStrength: Double = 1,
        exposureOffset: Double = 0,
        contrast: Double = 0,
        saturation: Double = 0,
        vibrance: Double = 0,
        monochrome: Bool = false
    ) {
        self.id = id
        self.name = name
        self.autoToneStrength = autoToneStrength
        self.exposureOffset = exposureOffset
        self.contrast = contrast
        self.saturation = saturation
        self.vibrance = vibrance
        self.monochrome = monochrome
    }

    /// 自動推定レシピにこのプリセットを重ねたレシピ。
    public func apply(to auto: DevelopRecipe) -> DevelopRecipe {
        DevelopRecipe(
            exposure: auto.exposure * autoToneStrength + exposureOffset,
            whiteBalance: auto.whiteBalance,
            highlights: auto.highlights * autoToneStrength,
            shadows: auto.shadows * autoToneStrength,
            contrast: auto.contrast + contrast,
            saturation: auto.saturation + saturation,
            vibrance: auto.vibrance + vibrance,
            noiseReduction: auto.noiseReduction,
            sharpness: auto.sharpness,
            lensCorrection: auto.lensCorrection,
            monochrome: auto.monochrome || monochrome
        ).clamped()
    }
}

public extension DevelopPreset {
    /// 癖のない標準。自動補正のみ。
    static let neutral = DevelopPreset(id: "neutral", name: "ニュートラル")
    /// 撮って出し（自動補正なし）。
    static let asShot = DevelopPreset(id: "as-shot", name: "撮って出し", autoToneStrength: 0)
    /// 柔らかめ。
    static let soft = DevelopPreset(id: "soft", name: "やわらか", exposureOffset: 0.1, contrast: -0.15, vibrance: -0.05)
    /// くっきり。
    static let crisp = DevelopPreset(id: "crisp", name: "くっきり", contrast: 0.15, vibrance: 0.15)
    static let monochrome = DevelopPreset(id: "mono", name: "モノクロ", contrast: 0.1, monochrome: true)

    static let builtIn: [DevelopPreset] = [.neutral, .asShot, .soft, .crisp, .monochrome]
}
