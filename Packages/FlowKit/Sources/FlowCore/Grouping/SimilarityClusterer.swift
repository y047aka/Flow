import Foundation

/// シーン内の写真を「似たショット」のグループにまとめる。
///
/// 撮影順に走査し、直前のグループの直近メンバーと特徴ベクトルが近く、撮影間隔も短ければ同じグループに入れる。
/// 連写や同じ被写体の撮り直しは時間的に連続するため、全組み合わせを比べる階層クラスタリングより
/// 高速（O(n·k)）で、誤って離れた時間の写真を混ぜることも無い。
public struct SimilarityClusterer: Sendable {
    public struct Configuration: Sendable {
        /// 特徴ベクトルの距離がこれ以下なら「似ている」とみなす。
        /// Vision の FeaturePrint（revision 2, 正規化済み 768 次元）を想定した初期値。実データで調整すること。
        public var maximumDistance: Float
        /// グループ内の直前の写真とこれ以上撮影間隔が空いたら別グループ。
        public var maximumTimeGap: TimeInterval
        /// 比較対象にするグループ内の直近メンバー数。
        public var comparisonWindow: Int

        public init(maximumDistance: Float = 0.55, maximumTimeGap: TimeInterval = 60, comparisonWindow: Int = 3) {
            self.maximumDistance = maximumDistance
            self.maximumTimeGap = maximumTimeGap
            self.comparisonWindow = comparisonWindow
        }
    }

    public var configuration: Configuration

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    /// - Parameter assets: 撮影順に並んだ 1 シーン分の写真。
    public func cluster(_ assets: [PhotoAsset], analyses: [PhotoAsset.ID: ImageAnalysis]) -> [[PhotoAsset]] {
        var groups: [[PhotoAsset]] = []
        for asset in assets {
            if let last = groups.last, belongs(asset, to: last, analyses: analyses) {
                groups[groups.count - 1].append(asset)
            } else {
                groups.append([asset])
            }
        }
        return groups
    }

    func belongs(_ asset: PhotoAsset, to group: [PhotoAsset], analyses: [PhotoAsset.ID: ImageAnalysis]) -> Bool {
        guard let previous = group.last else { return false }
        if let d0 = previous.captureDate, let d1 = asset.captureDate,
           d1.timeIntervalSince(d0) > configuration.maximumTimeGap {
            return false
        }
        guard let vector = analyses[asset.id]?.featureVector else { return false }
        return group.suffix(configuration.comparisonWindow).contains { member in
            guard let other = analyses[member.id]?.featureVector,
                  other.values.count == vector.values.count else { return false }
            return vector.distance(to: other) <= configuration.maximumDistance
        }
    }
}
