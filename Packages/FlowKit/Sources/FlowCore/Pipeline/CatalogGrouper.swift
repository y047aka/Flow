import Foundation

/// 解析済みの写真からシーン → 類似グループ → ベストショットを組み立てる。
/// 解析をやり直さずに閾値だけ変えて再グルーピングできるよう、パイプラインから独立させている。
public struct CatalogGrouper: Sendable {
    public let segmenter: SceneSegmenter
    public let clusterer: SimilarityClusterer
    public let selector: BestShotSelector

    public init(
        segmenter: SceneSegmenter = .init(),
        clusterer: SimilarityClusterer = .init(),
        selector: BestShotSelector = .init()
    ) {
        self.segmenter = segmenter
        self.clusterer = clusterer
        self.selector = selector
    }

    /// シーンとグループの ID は先頭の写真の ID にする。設定を変えて組み直しても、
    /// 同じ写真から始まるシーン・グループは同じ ID のままなので、UI の選択状態が保たれる。
    public func group(_ assets: [PhotoAsset], analyses: [PhotoAsset.ID: ImageAnalysis]) -> [PhotoScene] {
        segmenter.segment(assets).compactMap { sceneAssets in
            guard let first = sceneAssets.first else { return nil }
            let groups = clusterer.cluster(sceneAssets, analyses: analyses).compactMap { members -> SimilarGroup? in
                let ids = members.map(\.id)
                return ids.first.map { SimilarGroup(id: $0, assetIDs: ids, bestAssetID: selector.selectBest(from: ids, analyses: analyses)) }
            }
            let dates = sceneAssets.compactMap(\.captureDate)
            return PhotoScene(id: first.id, startDate: dates.min(), endDate: dates.max(), groups: groups)
        }
    }
}
