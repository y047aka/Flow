import Foundation

/// 輝度ヒストグラム（ガンマ補正後の 0...1 を等分したビン）。
public struct LuminanceHistogram: Codable, Hashable, Sendable {
    public var bins: [Int]

    public init(bins: [Int]) {
        self.bins = bins
    }

    /// 0...1 の輝度値の列から作る。
    public init(samples: some Sequence<Float>, binCount: Int = 256) {
        var bins = [Int](repeating: 0, count: binCount)
        for v in samples {
            let i = Int((v.clamped(to: 0...1) * Float(binCount - 1)).rounded())
            bins[i] += 1
        }
        self.bins = bins
    }

    public var total: Int { bins.reduce(0, +) }

    /// 累積分布が p (0...1) に達する輝度値。
    public func percentile(_ p: Double) -> Double {
        let total = self.total
        guard total > 0, bins.count > 1 else { return 0 }
        let target = Double(total) * p
        var cumulative = 0
        for (i, c) in bins.enumerated() {
            cumulative += c
            if Double(cumulative) >= target { return Double(i) / Double(bins.count - 1) }
        }
        return 1
    }

    /// 輝度が範囲内にある画素の割合。
    public func fraction(in range: ClosedRange<Double>) -> Double {
        let total = self.total
        guard total > 0, bins.count > 1 else { return 0 }
        var n = 0
        for (i, c) in bins.enumerated() where range.contains(Double(i) / Double(bins.count - 1)) {
            n += c
        }
        return Double(n) / Double(total)
    }
}

/// 中立現像のプレビューのヒストグラムから「控えめな」自動補正レシピを推定する。
///
/// 方針: 派手に仕上げるのではなく、露出の明らかな過不足・白飛び・黒つぶれだけを穏やかに直す。
/// 色やコントラストには手を付けない（それはプリセットの役割）。
public struct AutoToneEstimator: Sendable {
    public struct Configuration: Sendable {
        /// 目標とする中央値輝度（ガンマ補正後）。
        public var targetMedian: Double = 0.42
        /// 推定した露出差のうち実際に補正する割合。
        public var exposureStrength: Double = 0.6
        /// 露出補正の上限（EV）。
        public var maximumExposureCorrection: Double = 1.0
        /// この EV 未満の差は補正しない（意図的なローキー / ハイキーを尊重）。
        public var exposureDeadZone: Double = 0.2
        public var gamma: Double = 2.2
        /// 補正せずに許容する白飛び画素の割合。
        public var allowedClippedFraction: Double = 0.005
        /// 補正せずに許容する黒つぶれ画素の割合。
        public var allowedCrushedFraction: Double = 0.05

        public init() {}
    }

    public var configuration: Configuration

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    public func estimate(from histogram: LuminanceHistogram) -> DevelopRecipe {
        var recipe = DevelopRecipe()
        guard histogram.total > 0 else { return recipe }
        let c = configuration

        let median = max(histogram.percentile(0.5), 0.01)
        let linearMedian = pow(median, c.gamma)
        let linearTarget = pow(c.targetMedian, c.gamma)
        let ev = log2(linearTarget / linearMedian)
        if abs(ev) > c.exposureDeadZone {
            recipe.exposure = (ev * c.exposureStrength).clamped(to: -c.maximumExposureCorrection...c.maximumExposureCorrection)
        }

        // 露出を上げる場合は白飛びが増えるので、その分もハイライト抑制に含める。
        // ごく一部の白飛び・黒つぶれは自然なので、許容量を超えた分だけ補正する。
        let clipped = max(0, histogram.fraction(in: 0.97...1.0) - c.allowedClippedFraction)
        let brightening = max(recipe.exposure, 0)
        recipe.highlights = (clipped * 8 + brightening * 0.3).clamped(to: 0...0.8)

        let crushed = max(0, histogram.fraction(in: 0.0...0.03) - c.allowedCrushedFraction)
        recipe.shadows = (crushed * 4).clamped(to: 0...0.5)

        return recipe.clamped()
    }
}
