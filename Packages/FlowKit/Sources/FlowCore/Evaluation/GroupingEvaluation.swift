import Foundation

/// 正解データのキー: 同じカメラで続けて撮った 2 枚。
///
/// 写真の ID は取り込みのたびに作り直されるので、ファイルの場所（パス）で記録する。
/// 閾値やグループ分けのロジックを変えても、同じフォルダを取り込み直しても同じキーになる。
public struct PhotoPair: Codable, Hashable, Sendable {
    public let previousPath: String
    public let nextPath: String

    public init(previousPath: String, nextPath: String) {
        self.previousPath = previousPath
        self.nextPath = nextPath
    }

    public init(previous: PhotoAsset, next: PhotoAsset) {
        self.init(previousPath: previous.fileURL.path, nextPath: next.fileURL.path)
    }
}

/// 正解データに対するグループ分けの評価。
///
/// 2 枚が「同じグループか」の予測は、判定の記録ではなく実際のグループの所属で決める。
/// こうしておけば、離れた写真どうしをまとめるようなロジックに変えても同じ正解データで比べられる。
public struct GroupingEvaluation: Hashable, Sendable {
    /// 正解「同じ」・予測「同じ」
    public let correctMerges: Int
    /// 正解「別」・予測「別」
    public let correctSplits: Int
    /// 正解「別」なのに同じグループにした（誤って統合）
    public let falseMerges: Int
    /// 正解「同じ」なのに別のグループにした（誤って分割）
    public let falseSplits: Int

    public init(correctMerges: Int = 0, correctSplits: Int = 0, falseMerges: Int = 0, falseSplits: Int = 0) {
        self.correctMerges = correctMerges
        self.correctSplits = correctSplits
        self.falseMerges = falseMerges
        self.falseSplits = falseSplits
    }

    /// 評価に使えた（両方の写真がカタログにある）正解の数。
    public var labeledCount: Int { correctMerges + correctSplits + falseMerges + falseSplits }
    public var errorCount: Int { falseMerges + falseSplits }

    /// 正解率。正解が 1 件も無ければ nil。
    public var accuracy: Double? {
        labeledCount > 0 ? Double(correctMerges + correctSplits) / Double(labeledCount) : nil
    }

    /// 1 組の予測と正解を加えた評価。
    func adding(predictedSame: Bool, actuallySame: Bool) -> GroupingEvaluation {
        GroupingEvaluation(
            correctMerges: correctMerges + (predictedSame && actuallySame ? 1 : 0),
            correctSplits: correctSplits + (!predictedSame && !actuallySame ? 1 : 0),
            falseMerges: falseMerges + (predictedSame && !actuallySame ? 1 : 0),
            falseSplits: falseSplits + (!predictedSame && actuallySame ? 1 : 0)
        )
    }
}

public extension Catalog {
    /// 正解データ（未設定なら空）。
    var labels: [PhotoPair: Bool] { groupingLabels ?? [:] }

    /// 2 枚が今のグループ分けで同じグループか。どちらかがカタログに無ければ nil。
    func isPredictedSame(_ pair: PhotoPair) -> Bool? {
        predictions(for: [pair])[pair]
    }

    /// 複数の組について、今のグループ分けで同じグループか（一覧表示用。対応表は 1 回だけ作る）。
    func predictions(for pairs: [PhotoPair]) -> [PhotoPair: Bool] {
        let groupByPath = groupIDByPath
        return Dictionary(
            pairs.compactMap { pair in
                guard let a = groupByPath[pair.previousPath], let b = groupByPath[pair.nextPath] else { return nil }
                return (pair, a == b)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// 今のグループ分けの、正解データに対する評価。
    var evaluation: GroupingEvaluation {
        let groupByPath = groupIDByPath
        return labels.reduce(GroupingEvaluation()) { result, label in
            guard let a = groupByPath[label.key.previousPath], let b = groupByPath[label.key.nextPath] else { return result }
            return result.adding(predictedSame: a == b, actuallySame: label.value)
        }
    }

    /// 閾値を変えたときの評価（グループ分けをやり直すだけなので、解析はやり直さない）。
    func thresholdSweep(_ thresholds: [Float]) -> [(threshold: Float, evaluation: GroupingEvaluation)] {
        thresholds.map { threshold in
            (threshold, regrouped(with: grouping.with(similarityThreshold: threshold)).evaluation)
        }
    }

    /// シーンごとの、同じカメラで続けて撮った 2 枚の判定の記録。
    var linksByScene: [PhotoScene.ID: [PhotoLink]] {
        Dictionary(
            grouping.grouper.groupWithLinks(Array(assets.values), analyses: analyses).map { ($0.scene.id, $0.links) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// ファイルの場所 → 所属するグループの ID。
    private var groupIDByPath: [String: SimilarGroup.ID] {
        Dictionary(
            scenes.flatMap(\.groups).flatMap { group in
                group.assetIDs.compactMap { assets[$0].map { ($0.fileURL.path, group.id) } }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }
}
