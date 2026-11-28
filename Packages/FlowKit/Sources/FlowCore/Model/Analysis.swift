import Foundation

/// 画像解析の結果。プラットフォーム固有の型を含まないため、どの OS の解析器でも生成できる。
public struct ImageAnalysis: Codable, Hashable, Sendable {
    /// 類似度比較用の、画像全体の特徴ベクトル（Vision の FeaturePrint など）。
    public let featureVector: FeatureVector?
    /// 画像を 2×2 に分けた領域ごとの特徴ベクトル（左上・右上・左下・右下の順）。
    /// 構図内の人や物の位置の違いを捉えるために使う。古いカタログには無い。
    public let tileFeatureVectors: [FeatureVector]?
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
        tileFeatureVectors: [FeatureVector]? = nil,
        aestheticsScore: Float? = nil,
        isUtility: Bool? = nil,
        sharpness: Float? = nil,
        faceCount: Int = 0,
        minimumFaceQuality: Float? = nil
    ) {
        self.featureVector = featureVector
        self.tileFeatureVectors = tileFeatureVectors
        self.aestheticsScore = aestheticsScore
        self.isUtility = isUtility
        self.sharpness = sharpness
        self.faceCount = faceCount
        self.minimumFaceQuality = minimumFaceQuality
    }
}

/// 特徴ベクトル。距離はユークリッド距離（Vision の computeDistance と同じ定義）。
///
/// カタログには Float32 のバイト列（Base64）として保存する。数値の配列で保存するより 2〜3 倍小さい。
/// 以前のバージョンが保存した数値の配列も読み込める。
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

    private enum CodingKeys: String, CodingKey {
        case values  // 以前の形式: [Float]
        case data    // 現在の形式: Float32（リトルエンディアン）のバイト列
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let data = try container.decodeIfPresent(Data.self, forKey: .data) {
            self.values = stride(from: 0, to: data.count - data.count % 4, by: 4).map { offset in
                Float(bitPattern: data[data.startIndex + offset ..< data.startIndex + offset + 4]
                    .enumerated()
                    .reduce(UInt32(0)) { bits, byte in bits | UInt32(byte.element) << (8 * UInt32(byte.offset)) })
            }
        } else {
            self.values = try container.decode([Float].self, forKey: .values)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let bytes = values.flatMap { value in
            (0..<4).map { UInt8(truncatingIfNeeded: value.bitPattern >> (8 * UInt32($0))) }
        }
        try container.encode(Data(bytes), forKey: .data)
    }
}
