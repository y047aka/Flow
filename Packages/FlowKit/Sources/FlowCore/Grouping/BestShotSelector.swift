import Foundation

/// グループ内のベストショットを解析結果のスコアから選ぶ。
public struct BestShotSelector: Sendable {
    public struct Weights: Sendable {
        public let aesthetics: Float
        public let sharpness: Float
        public let faceQuality: Float
        /// 記録用写真（書類・スクショ的）と判定されたときの減点。
        public let utilityPenalty: Float

        public init(aesthetics: Float = 1.0, sharpness: Float = 1.0, faceQuality: Float = 1.5, utilityPenalty: Float = 0.5) {
            self.aesthetics = aesthetics
            self.sharpness = sharpness
            self.faceQuality = faceQuality
            self.utilityPenalty = utilityPenalty
        }
    }

    public let weights: Weights

    public init(weights: Weights = .init()) {
        self.weights = weights
    }

    /// 得られている指標の重み付き和。欠けている指標は 0 として扱う。
    public func score(_ analysis: ImageAnalysis?) -> Float {
        guard let analysis else { return 0 }
        let terms: [Float?] = [
            analysis.aestheticsScore.map { weights.aesthetics * $0 },
            analysis.sharpness.map { weights.sharpness * $0 },
            analysis.minimumFaceQuality.map { weights.faceQuality * $0 },
            analysis.isUtility == true ? -weights.utilityPenalty : nil,
        ]
        return terms.compactMap { $0 }.sum()
    }

    /// 最もスコアの高い写真。同点なら撮影順で先のもの（`max(by:)` は最初の最大値を返す）。
    public func selectBest(from assetIDs: [PhotoAsset.ID], analyses: [PhotoAsset.ID: ImageAnalysis]) -> PhotoAsset.ID? {
        assetIDs
            .map { (id: $0, score: score(analyses[$0])) }
            .max { $0.score < $1.score }?
            .id
    }
}
