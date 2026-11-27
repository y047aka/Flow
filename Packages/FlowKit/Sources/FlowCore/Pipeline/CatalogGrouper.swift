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

    public func group(_ assets: [PhotoAsset], analyses: [PhotoAsset.ID: ImageAnalysis]) -> [PhotoScene] {
        segmenter.segment(assets).map { sceneAssets in
            let groups = clusterer.cluster(sceneAssets, analyses: analyses).map { members in
                let ids = members.map(\.id)
                return SimilarGroup(assetIDs: ids, bestAssetID: selector.selectBest(from: ids, analyses: analyses))
            }
            let dates = sceneAssets.compactMap(\.captureDate)
            return PhotoScene(startDate: dates.min(), endDate: dates.max(), groups: groups)
        }
    }
}
