import Foundation

/// 1 枚の写真の自動補正レシピを求める（中立現像のヒストグラム測定 → 推定）。
///
/// RAW の現像を伴う重い処理なので、取り込み時にはまとめて実行せず、
/// `Catalog.autoTonePriority(focusedOn:)` の順に裏で 1 枚ずつ計算する想定。
public struct AutoToneService: Sendable {
    public let measurer: any ToneMeasuring
    public let estimator: AutoToneEstimator

    public init(measurer: any ToneMeasuring, estimator: AutoToneEstimator = .init()) {
        self.measurer = measurer
        self.estimator = estimator
    }

    public func recipe(for asset: PhotoAsset) async throws -> DevelopRecipe {
        estimator.estimate(from: try await measurer.luminanceHistogram(for: asset))
    }
}

public extension Catalog {
    /// 自動補正がまだ計算されていない写真を、計算すべき順に並べたもの。
    ///
    /// 1. 今開いている写真（`focused`）
    /// 2. 各グループのベストショット（書き出しの対象）
    /// 3. 残りの写真（シーン・撮影順）
    func autoTonePriority(focusedOn focused: PhotoAsset.ID? = nil) -> [PhotoAsset.ID] {
        let candidates = [focused].compactMap { $0 }
            + bestAssets.map(\.id)
            + scenes.flatMap(\.assetIDs)
            + assets.keys.sorted { $0.uuidString < $1.uuidString } // シーンに属さない写真（通常は無い）
        return candidates
            .uniqued()
            .filter { assets[$0] != nil && autoRecipes[$0] == nil }
    }

    /// 自動補正の計算が済んだ枚数と全体の枚数。
    var autoToneProgress: (completed: Int, total: Int) {
        (assets.keys.filter { autoRecipes[$0] != nil }.count, assets.count)
    }
}
