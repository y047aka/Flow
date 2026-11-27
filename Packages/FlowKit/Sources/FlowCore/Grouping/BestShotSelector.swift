import Foundation

/// グループ内のベストショットを解析結果のスコアから選ぶ。
public struct BestShotSelector: Sendable {
    public struct Weights: Sendable {
        public var aesthetics: Float
        public var sharpness: Float
        public var faceQuality: Float
        /// 記録用写真（書類・スクショ的）と判定されたときの減点。
        public var utilityPenalty: Float

        public init(aesthetics: Float = 1.0, sharpness: Float = 1.0, faceQuality: Float = 1.5, utilityPenalty: Float = 0.5) {
            self.aesthetics = aesthetics
            self.sharpness = sharpness
            self.faceQuality = faceQuality
            self.utilityPenalty = utilityPenalty
        }
    }

    public var weights: Weights

    public init(weights: Weights = .init()) {
        self.weights = weights
    }

    public func score(_ analysis: ImageAnalysis?) -> Float {
        guard let analysis else { return 0 }
        var score: Float = 0
        if let a = analysis.aestheticsScore { score += weights.aesthetics * a }
        if let s = analysis.sharpness { score += weights.sharpness * s }
        if let f = analysis.minimumFaceQuality { score += weights.faceQuality * f }
        if analysis.isUtility == true { score -= weights.utilityPenalty }
        return score
    }

    /// 最もスコアの高い写真。同点なら撮影順で先のもの。
    public func selectBest(from assetIDs: [PhotoAsset.ID], analyses: [PhotoAsset.ID: ImageAnalysis]) -> PhotoAsset.ID? {
        var best: (id: PhotoAsset.ID, score: Float)?
        for id in assetIDs {
            let s = score(analyses[id])
            if best == nil || s > best!.score { best = (id, s) }
        }
        return best?.id
    }
}
