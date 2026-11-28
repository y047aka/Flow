import Foundation

/// ユーザーが UI から調整できるグルーピングの設定。カタログに保存される。
///
/// シーンは撮影日だけで区切るので、調整できるのは似たショットの判定のみ。
public struct GroupingSettings: Codable, Hashable, Sendable {
    /// 見た目の距離がこれ以下なら「似ている」とみなす。小さいほど厳しい。
    public let similarityThreshold: Float
    /// 2×2 の領域ごとの比較も使うか（人や物の位置の違いに敏感になる）。
    public let usesTileComparison: Bool

    public init(similarityThreshold: Float = 0.38, usesTileComparison: Bool = true) {
        self.similarityThreshold = similarityThreshold
        self.usesTileComparison = usesTileComparison
    }

    public static let `default` = GroupingSettings()

    // UI のスライダーの範囲
    public static let similarityThresholdRange: ClosedRange<Float> = 0.2...0.9

    /// 領域ごとの比較を使うときに、画像全体の距離と混ぜる割合。
    static let tileWeight: Float = 0.5

    /// 一部の値だけを変えた設定。
    public func with(similarityThreshold: Float? = nil, usesTileComparison: Bool? = nil) -> GroupingSettings {
        GroupingSettings(
            similarityThreshold: similarityThreshold ?? self.similarityThreshold,
            usesTileComparison: usesTileComparison ?? self.usesTileComparison
        )
    }

    /// この設定でグルーピングを行う grouper。
    public var grouper: CatalogGrouper {
        CatalogGrouper(clusterer: SimilarityClusterer(configuration: .init(
            maximumDistance: similarityThreshold,
            tileWeight: usesTileComparison ? Self.tileWeight : 0
        )))
    }

    // 以前のバージョンが保存した設定には usesTileComparison が無いので、無ければ既定値にする。
    private enum CodingKeys: String, CodingKey {
        case similarityThreshold, usesTileComparison
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            similarityThreshold: try container.decodeIfPresent(Float.self, forKey: .similarityThreshold)
                ?? Self.default.similarityThreshold,
            usesTileComparison: try container.decodeIfPresent(Bool.self, forKey: .usesTileComparison)
                ?? Self.default.usesTileComparison
        )
    }
}
