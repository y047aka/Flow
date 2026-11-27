import Foundation

/// ユーザーが UI から調整できるグルーピングの設定。カタログに保存される。
public struct GroupingSettings: Codable, Hashable, Sendable {
    /// 特徴ベクトルの距離がこれ以下なら「似ている」とみなす。小さいほど厳しい。
    public let similarityThreshold: Float
    /// シーンの中心からこれ以上離れたら別シーン（メートル）。
    public let sceneDistance: Double
    /// 位置情報が無いときに、これ以上撮影間隔が空いたら別シーン（秒）。
    public let sceneTimeGap: TimeInterval
    /// 撮影日が変わったら別シーンにするか。
    public let splitsByDay: Bool

    public init(
        similarityThreshold: Float = 0.55,
        sceneDistance: Double = 500,
        sceneTimeGap: TimeInterval = 30 * 60,
        splitsByDay: Bool = true
    ) {
        self.similarityThreshold = similarityThreshold
        self.sceneDistance = sceneDistance
        self.sceneTimeGap = sceneTimeGap
        self.splitsByDay = splitsByDay
    }

    public static let `default` = GroupingSettings()

    // UI のスライダーの範囲
    public static let similarityThresholdRange: ClosedRange<Float> = 0.2...0.9
    public static let sceneDistanceRange: ClosedRange<Double> = 100...5000
    public static let sceneTimeGapRange: ClosedRange<TimeInterval> = 5 * 60...3 * 60 * 60

    /// 一部の値だけを変えた設定。
    public func with(
        similarityThreshold: Float? = nil,
        sceneDistance: Double? = nil,
        sceneTimeGap: TimeInterval? = nil,
        splitsByDay: Bool? = nil
    ) -> GroupingSettings {
        GroupingSettings(
            similarityThreshold: similarityThreshold ?? self.similarityThreshold,
            sceneDistance: sceneDistance ?? self.sceneDistance,
            sceneTimeGap: sceneTimeGap ?? self.sceneTimeGap,
            splitsByDay: splitsByDay ?? self.splitsByDay
        )
    }

    /// この設定でグルーピングを行う grouper。
    public var grouper: CatalogGrouper {
        CatalogGrouper(
            segmenter: SceneSegmenter(configuration: .init(
                maximumTimeGap: sceneTimeGap,
                maximumDistance: sceneDistance,
                splitsByDay: splitsByDay
            )),
            clusterer: SimilarityClusterer(configuration: .init(maximumDistance: similarityThreshold))
        )
    }
}
