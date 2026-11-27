import Foundation

/// ユーザーが UI から調整できるグルーピングの設定。カタログに保存される。
///
/// シーンは撮影日だけで区切るので、調整できるのは似たショットの判定のみ。
public struct GroupingSettings: Codable, Hashable, Sendable {
    /// 特徴ベクトルの距離がこれ以下なら「似ている」とみなす。小さいほど厳しい。
    public let similarityThreshold: Float

    public init(similarityThreshold: Float = 0.38) {
        self.similarityThreshold = similarityThreshold
    }

    public static let `default` = GroupingSettings()

    // UI のスライダーの範囲
    public static let similarityThresholdRange: ClosedRange<Float> = 0.2...0.9

    /// 一部の値だけを変えた設定。
    public func with(similarityThreshold: Float? = nil) -> GroupingSettings {
        GroupingSettings(similarityThreshold: similarityThreshold ?? self.similarityThreshold)
    }

    /// この設定でグルーピングを行う grouper。
    public var grouper: CatalogGrouper {
        CatalogGrouper(clusterer: SimilarityClusterer(configuration: .init(maximumDistance: similarityThreshold)))
    }
}
