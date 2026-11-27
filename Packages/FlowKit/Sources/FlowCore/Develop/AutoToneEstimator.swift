import Foundation

/// 輝度ヒストグラム（ガンマ補正後の 0...1 を等分したビン）。
public struct LuminanceHistogram: Codable, Hashable, Sendable {
    public let bins: [Int]

    public init(bins: [Int]) {
        self.bins = bins
    }

    /// 0...1 の輝度値の列から作る。
    public init(samples: some Sequence<Float>, binCount: Int = 256) {
        self.bins = samples.reduce(into: [Int](repeating: 0, count: binCount)) { bins, value in
            bins[Int((value.clamped(to: 0...1) * Float(binCount - 1)).rounded())] += 1
        }
    }

    public var total: Int { bins.sum() }

    /// 各ビンの代表輝度（0...1）と画素数の組。
    private var levels: [(level: Double, count: Int)] {
        let maxIndex = Double(max(bins.count - 1, 1))
        return bins.enumerated().map { (level: Double($0.offset) / maxIndex, count: $0.element) }
    }

    private var isMeasurable: Bool { total > 0 && bins.count > 1 }

    /// 累積分布が p (0...1) に達する輝度値。
    public func percentile(_ p: Double) -> Double {
        guard isMeasurable else { return 0 }
        let target = Double(total) * p
        return zip(levels, bins.cumulativeSums())
            .first { Double($0.1) >= target }?
            .0.level ?? 1
    }

    /// 輝度が範囲内にある画素の割合。
    public func fraction(in range: ClosedRange<Double>) -> Double {
        guard isMeasurable else { return 0 }
        let count = levels.filter { range.contains($0.level) }.map(\.count).sum()
        return Double(count) / Double(total)
    }
}

/// 中立現像のプレビューのヒストグラムから「控えめな」自動補正レシピを推定する。
///
/// 方針: 派手に仕上げるのではなく、露出の明らかな過不足・白飛び・黒つぶれだけを穏やかに直す。
/// 色やコントラストには手を付けない（それはプリセットの役割）。
public struct AutoToneEstimator: Sendable {
    public struct Configuration: Sendable {
        /// 目標とする中央値輝度（ガンマ補正後）。
        public let targetMedian: Double
        /// 推定した露出差のうち実際に補正する割合。
        public let exposureStrength: Double
        /// 露出補正の上限（EV）。
        public let maximumExposureCorrection: Double
        /// この EV 未満の差は補正しない（意図的なローキー / ハイキーを尊重）。
        public let exposureDeadZone: Double
        public let gamma: Double
        /// 補正せずに許容する白飛び画素の割合。
        public let allowedClippedFraction: Double
        /// 補正せずに許容する黒つぶれ画素の割合。
        public let allowedCrushedFraction: Double

        public init(
            targetMedian: Double = 0.42,
            exposureStrength: Double = 0.6,
            maximumExposureCorrection: Double = 1.0,
            exposureDeadZone: Double = 0.2,
            gamma: Double = 2.2,
            allowedClippedFraction: Double = 0.005,
            allowedCrushedFraction: Double = 0.05
        ) {
            self.targetMedian = targetMedian
            self.exposureStrength = exposureStrength
            self.maximumExposureCorrection = maximumExposureCorrection
            self.exposureDeadZone = exposureDeadZone
            self.gamma = gamma
            self.allowedClippedFraction = allowedClippedFraction
            self.allowedCrushedFraction = allowedCrushedFraction
        }
    }

    public let configuration: Configuration

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    public func estimate(from histogram: LuminanceHistogram) -> DevelopRecipe {
        guard histogram.total > 0 else { return DevelopRecipe() }
        let exposure = exposureCorrection(median: histogram.percentile(0.5))
        return DevelopRecipe(
            exposure: exposure,
            highlights: highlightRecovery(clipped: histogram.fraction(in: 0.97...1.0), exposure: exposure),
            shadows: shadowLift(crushed: histogram.fraction(in: 0.0...0.03))
        ).clamped()
    }

    /// 中央値を目標に近づける露出補正（EV）。差が小さければ 0。
    func exposureCorrection(median: Double) -> Double {
        let c = configuration
        let ev = log2(pow(c.targetMedian, c.gamma) / pow(max(median, 0.01), c.gamma))
        guard abs(ev) > c.exposureDeadZone else { return 0 }
        return (ev * c.exposureStrength).clamped(to: -c.maximumExposureCorrection...c.maximumExposureCorrection)
    }

    /// 許容量を超えた白飛びと、露出を上げることで増える白飛びを抑える量。
    func highlightRecovery(clipped: Double, exposure: Double) -> Double {
        let excess = max(0, clipped - configuration.allowedClippedFraction)
        return (excess * 8 + max(exposure, 0) * 0.3).clamped(to: 0...0.8)
    }

    /// 許容量を超えた黒つぶれを持ち上げる量。
    func shadowLift(crushed: Double) -> Double {
        let excess = max(0, crushed - configuration.allowedCrushedFraction)
        return (excess * 4).clamped(to: 0...0.5)
    }
}
