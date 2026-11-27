import Foundation

/// ユーザーが UI から調整できるグルーピングの設定。カタログに保存される。
public struct GroupingSettings: Codable, Hashable, Sendable {
    /// 特徴ベクトルの距離がこれ以下なら「似ている」とみなす。小さいほど厳しい。
    public let similarityThreshold: Float
    /// シーンの中心からこれ以上離れたら別シーン（メートル）。
    public let sceneDistance: Double

    public init(similarityThreshold: Float = 0.38, sceneDistance: Double = 500) {
        self.similarityThreshold = similarityThreshold
        self.sceneDistance = sceneDistance
    }

    public static let `default` = GroupingSettings()

    // UI のスライダーの範囲
    public static let similarityThresholdRange: ClosedRange<Float> = 0.2...0.9
    public static let sceneDistanceRange: ClosedRange<Double> = 100...5000

    /// 一部の値だけを変えた設定。
    public func with(similarityThreshold: Float? = nil, sceneDistance: Double? = nil) -> GroupingSettings {
        GroupingSettings(
            similarityThreshold: similarityThreshold ?? self.similarityThreshold,
            sceneDistance: sceneDistance ?? self.sceneDistance
        )
    }

    /// この設定でグルーピングを行う grouper。
    public var grouper: CatalogGrouper {
        CatalogGrouper(
            segmenter: SceneSegmenter(configuration: .init(maximumDistance: sceneDistance)),
            clusterer: SimilarityClusterer(configuration: .init(maximumDistance: similarityThreshold))
        )
    }
}
