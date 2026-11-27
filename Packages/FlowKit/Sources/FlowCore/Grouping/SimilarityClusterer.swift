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
        public let maximumDistance: Float
        /// グループ内の直前の写真とこれ以上撮影間隔が空いたら別グループ。
        public let maximumTimeGap: TimeInterval
        /// 比較対象にするグループ内の直近メンバー数。
        public let comparisonWindow: Int

        public init(maximumDistance: Float = 0.55, maximumTimeGap: TimeInterval = 60, comparisonWindow: Int = 3) {
            self.maximumDistance = maximumDistance
            self.maximumTimeGap = maximumTimeGap
            self.comparisonWindow = comparisonWindow
        }
    }

    public let configuration: Configuration

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    /// - Parameter assets: 撮影順に並んだ 1 シーン分の写真。
    public func cluster(_ assets: [PhotoAsset], analyses: [PhotoAsset.ID: ImageAnalysis]) -> [[PhotoAsset]] {
        assets.grouped { group, asset in belongs(asset, to: group, analyses: analyses) }
    }

    func belongs(_ asset: PhotoAsset, to group: [PhotoAsset], analyses: [PhotoAsset.ID: ImageAnalysis]) -> Bool {
        guard let previous = group.last,
              let vector = analyses[asset.id]?.featureVector,
              isWithinTimeGap(previous, asset) else { return false }
        return group
            .suffix(configuration.comparisonWindow)
            .compactMap { analyses[$0.id]?.featureVector }
            .contains { isSimilar(vector, $0) }
    }

    func isWithinTimeGap(_ a: PhotoAsset, _ b: PhotoAsset) -> Bool {
        guard let da = a.captureDate, let db = b.captureDate else { return true }
        return db.timeIntervalSince(da) <= configuration.maximumTimeGap
    }

    func isSimilar(_ a: FeatureVector, _ b: FeatureVector) -> Bool {
        a.values.count == b.values.count && a.distance(to: b) <= configuration.maximumDistance
    }
}
