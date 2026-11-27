import Foundation

/// シーン内の写真を「似たショット」のグループにまとめる。
///
/// 1. シーン内の写真をカメラごとに分ける（別のカメラの写真は同じグループにしない）。
///    カメラはシリアル番号があれば個体、無ければ機種で識別する（`CaptureMetadata.cameraIdentity`）。
/// 2. カメラごとに撮影順に走査し、次のどちらかを満たせば直前のグループに入れる:
///    - 連写: 直前の写真との撮影間隔が `burstInterval` 以内（見た目に関係なく同じグループ）
///    - 似たショット: 撮影間隔が `maximumTimeGap` 以内で、グループの直近メンバーと特徴ベクトルが近い
/// 3. すべてのカメラのグループを、先頭の写真の撮影順に並べる。
///
/// カメラごとに分けてから走査するので、2 台で交互に撮った写真もそれぞれ連続した写真として扱える。
public struct SimilarityClusterer: Sendable {
    public struct Configuration: Sendable {
        /// 特徴ベクトルの距離がこれ以下なら「似ている」とみなす。
        /// Vision の FeaturePrint（revision 2, 正規化済み 768 次元）を想定した初期値。実データで調整すること。
        public let maximumDistance: Float
        /// グループ内の直前の写真とこれ以上撮影間隔が空いたら別グループ。
        public let maximumTimeGap: TimeInterval
        /// 直前の写真との撮影間隔がこれ以内なら、1 回の連写とみなして見た目に関係なく同じグループにする。
        /// サブ秒を記録しないカメラでは同じ秒のコマが間隔 0、隣の秒のコマが間隔 1 になるので、1 秒以内とする。
        public let burstInterval: TimeInterval
        /// 比較対象にするグループ内の直近メンバー数。
        public let comparisonWindow: Int

        public init(
            maximumDistance: Float = 0.38,
            maximumTimeGap: TimeInterval = 60,
            burstInterval: TimeInterval = 1,
            comparisonWindow: Int = 3
        ) {
            self.maximumDistance = maximumDistance
            self.maximumTimeGap = maximumTimeGap
            self.burstInterval = burstInterval
            self.comparisonWindow = comparisonWindow
        }
    }

    public let configuration: Configuration

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    /// - Parameter assets: 撮影順に並んだ 1 シーン分の写真。
    public func cluster(_ assets: [PhotoAsset], analyses: [PhotoAsset.ID: ImageAnalysis]) -> [[PhotoAsset]] {
        // Dictionary(grouping:) は各カメラ内の順序（撮影順）を保つ。
        Dictionary(grouping: assets) { $0.metadata.cameraIdentity }
            .values
            .flatMap { cameraAssets in
                cameraAssets.grouped { group, asset in belongs(asset, to: group, analyses: analyses) }
            }
            .sorted { SceneSegmenter.chronological($0[0], $1[0]) }
    }

    func belongs(_ asset: PhotoAsset, to group: [PhotoAsset], analyses: [PhotoAsset.ID: ImageAnalysis]) -> Bool {
        guard let previous = group.last else { return false }
        if isBurst(previous, asset) { return true }
        guard let vector = analyses[asset.id]?.featureVector,
              isWithinTimeGap(previous, asset) else { return false }
        return group
            .suffix(configuration.comparisonWindow)
            .compactMap { analyses[$0.id]?.featureVector }
            .contains { isSimilar(vector, $0) }
    }

    /// 同じ連写のコマか（撮影日時が両方ある場合のみ判定できる）。
    func isBurst(_ a: PhotoAsset, _ b: PhotoAsset) -> Bool {
        guard let da = a.captureDate, let db = b.captureDate else { return false }
        return abs(db.timeIntervalSince(da)) <= configuration.burstInterval
    }

    func isWithinTimeGap(_ a: PhotoAsset, _ b: PhotoAsset) -> Bool {
        guard let da = a.captureDate, let db = b.captureDate else { return true }
        return db.timeIntervalSince(da) <= configuration.maximumTimeGap
    }

    func isSimilar(_ a: FeatureVector, _ b: FeatureVector) -> Bool {
        a.values.count == b.values.count && a.distance(to: b) <= configuration.maximumDistance
    }
}
