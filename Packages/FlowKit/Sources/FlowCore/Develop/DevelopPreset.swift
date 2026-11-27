import Foundation

/// ユーザーが選べる唯一の「現像パラメータ」。自動推定レシピの上に重ねる差分として表現する。
public struct DevelopPreset: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    /// 自動補正（露出・ハイライト・シャドウ）をどの程度効かせるか。0 で撮って出し、1 で推定値どおり。
    public var autoToneStrength: Double
    public var exposureOffset: Double
    public var contrast: Double
    public var saturation: Double
    public var vibrance: Double
    public var monochrome: Bool

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

    public func apply(to auto: DevelopRecipe) -> DevelopRecipe {
        var r = auto
        r.exposure = auto.exposure * autoToneStrength + exposureOffset
        r.highlights = auto.highlights * autoToneStrength
        r.shadows = auto.shadows * autoToneStrength
        r.contrast += contrast
        r.saturation += saturation
        r.vibrance += vibrance
        r.monochrome = r.monochrome || monochrome
        return r.clamped()
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
