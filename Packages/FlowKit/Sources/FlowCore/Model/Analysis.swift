import Foundation

/// 画像解析の結果。プラットフォーム固有の型を含まないため、どの OS の解析器でも生成できる。
public struct ImageAnalysis: Codable, Hashable, Sendable {
    /// 類似度比較用の特徴ベクトル（Vision の FeaturePrint など）。
    public let featureVector: FeatureVector?
    /// 写真としての美しさ（-1...1 程度。Vision の overallScore）。
    public let aestheticsScore: Float?
    /// スクリーンショットや書類など「記録用」の写真か。
    public let isUtility: Bool?
    /// シャープネス（ラプラシアン分散を 0...1 に正規化）。ブレ・ピンボケ判定用。
    public let sharpness: Float?
    /// 検出された顔の数。
    public let faceCount: Int
    /// 顔の写りの品質（目つむり・ブレ・向き）の最小値 0...1。顔が無ければ nil。
    public let minimumFaceQuality: Float?

    public init(
        featureVector: FeatureVector? = nil,
        aestheticsScore: Float? = nil,
        isUtility: Bool? = nil,
        sharpness: Float? = nil,
        faceCount: Int = 0,
        minimumFaceQuality: Float? = nil
    ) {
        self.featureVector = featureVector
        self.aestheticsScore = aestheticsScore
        self.isUtility = isUtility
        self.sharpness = sharpness
        self.faceCount = faceCount
        self.minimumFaceQuality = minimumFaceQuality
    }
}

/// 特徴ベクトル。距離はユークリッド距離（Vision の computeDistance と同じ定義）。
public struct FeatureVector: Codable, Hashable, Sendable {
    public let values: [Float]

    public init(_ values: [Float]) {
        self.values = values
    }

    public func distance(to other: FeatureVector) -> Float {
        precondition(values.count == other.values.count, "FeatureVector の次元が一致しません")
        return zip(values, other.values)
            .reduce(Float.zero) { sum, pair in sum + (pair.0 - pair.1) * (pair.0 - pair.1) }
            .squareRoot()
    }
}
