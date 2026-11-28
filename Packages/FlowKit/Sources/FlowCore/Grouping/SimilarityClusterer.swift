import Foundation

/// シーン内の写真を「似たショット」のグループにまとめる。
///
/// 1. シーン内の写真をカメラごとに分ける（別のカメラの写真は同じグループにしない）。
///    カメラはシリアル番号があれば個体、無ければ機種で識別する（`CaptureMetadata.cameraIdentity`）。
/// 2. カメラごとに撮影順に走査し、次のどちらかを満たせば直前のグループに入れる:
///    - 連写: 直前の写真との撮影間隔が `burstInterval` 以内（見た目に関係なく同じグループ）
///    - 似たショット: グループの直近メンバーとの見た目の距離が閾値以下（撮影間隔は問わない）
///      見た目の距離は、画像全体の特徴ベクトルの距離と、2×2 の領域ごとの距離の平均を `tileWeight` で混ぜたもの。
///      領域ごとに比べることで、構図は同じでも人や物の位置が違う写真を区別しやすくする。
/// 3. すべてのカメラのグループを、先頭の写真の撮影順に並べる。
///
/// 各写真を直前のグループに入れたか・その理由は `PhotoLink` として記録され、判定の確認に使える。
public struct SimilarityClusterer: Sendable {
    public struct Configuration: Sendable {
        /// 特徴ベクトルの距離がこれ以下なら「似ている」とみなす。
        /// Vision の FeaturePrint（revision 2, 正規化済み 768 次元）を想定した初期値。実データで調整すること。
        public let maximumDistance: Float
        /// 直前の写真との撮影間隔がこれ以内なら、1 回の連写とみなして見た目に関係なく同じグループにする。
        /// サブ秒を記録しないカメラでは同じ秒のコマが間隔 0、隣の秒のコマが間隔 1 になるので、1 秒以内とする。
        public let burstInterval: TimeInterval
        /// 比較対象にするグループ内の直近メンバー数。
        public let comparisonWindow: Int
        /// 見た目の距離で、領域ごとの距離の平均を混ぜる割合（0 で画像全体のみ、1 で領域のみ）。
        /// どちらかの写真に領域ごとの特徴ベクトルが無ければ、画像全体の距離だけを使う。
        public let tileWeight: Float

        public init(
            maximumDistance: Float = 0.38,
            burstInterval: TimeInterval = 1,
            comparisonWindow: Int = 3,
            tileWeight: Float = 0.5
        ) {
            self.maximumDistance = maximumDistance
            self.burstInterval = burstInterval
            self.comparisonWindow = comparisonWindow
            self.tileWeight = tileWeight
        }
    }

    public struct Result: Sendable {
        /// グループ（各グループは撮影順。グループは先頭の写真の撮影順に並ぶ）。
        public let groups: [[PhotoAsset]]
        /// 同じカメラで続けて撮った 2 枚ごとの判定（`next` の撮影順に並ぶ）。
        public let links: [PhotoLink]
    }

    public let configuration: Configuration

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    /// - Parameter assets: 撮影順に並んだ 1 シーン分の写真。
    public func cluster(_ assets: [PhotoAsset], analyses: [PhotoAsset.ID: ImageAnalysis]) -> [[PhotoAsset]] {
        clusterWithLinks(assets, analyses: analyses).groups
    }

    /// グループ分けと、その過程の判定の記録。
    public func clusterWithLinks(_ assets: [PhotoAsset], analyses: [PhotoAsset.ID: ImageAnalysis]) -> Result {
        // Dictionary(grouping:) は各カメラ内の順序（撮影順）を保つ。
        let perCamera = Dictionary(grouping: assets) { $0.metadata.cameraIdentity }.values.map { cameraAssets in
            cameraAssets.reduce(into: (groups: [[PhotoAsset]](), links: [PhotoLink]())) { acc, asset in
                guard let group = acc.groups.last, let previous = group.last else {
                    acc.groups.append([asset])
                    return
                }
                let decision = decide(asset, joining: group, analyses: analyses)
                acc.links.append(PhotoLink(previous: previous, next: asset, decision: decision))
                if decision.joins {
                    acc.groups[acc.groups.count - 1].append(asset)
                } else {
                    acc.groups.append([asset])
                }
            }
        }
        return Result(
            groups: perCamera.flatMap(\.groups).sorted { SceneSegmenter.chronological($0[0], $1[0]) },
            links: perCamera.flatMap(\.links).sorted { SceneSegmenter.chronological($0.next, $1.next) }
        )
    }

    /// `asset` を撮影順で直前のグループ `group` に入れるかの判定。
    func decide(_ asset: PhotoAsset, joining group: [PhotoAsset], analyses: [PhotoAsset.ID: ImageAnalysis]) -> LinkDecision {
        if let previous = group.last, let interval = burstInterval(previous, asset) {
            return .burst(interval: interval)
        }
        guard let analysis = analyses[asset.id],
              let nearest = group
                .suffix(configuration.comparisonWindow)
                .compactMap({ analyses[$0.id].flatMap { visualDistance(analysis, $0) } })
                .min(by: { $0.combined < $1.combined })
        else { return .different(distance: nil) }
        return nearest.combined <= configuration.maximumDistance ? .similar(distance: nearest) : .different(distance: nearest)
    }

    /// 2 枚の見た目の距離。画像全体の特徴ベクトルが比べられなければ nil。
    func visualDistance(_ a: ImageAnalysis, _ b: ImageAnalysis) -> VisualDistance? {
        guard let va = a.featureVector, let vb = b.featureVector, va.values.count == vb.values.count else { return nil }
        let whole = va.distance(to: vb)
        let tiles = configuration.tileWeight > 0 ? Self.meanTileDistance(a.tileFeatureVectors, b.tileFeatureVectors) : nil
        let combined = tiles.map { (1 - configuration.tileWeight) * whole + configuration.tileWeight * $0 } ?? whole
        return VisualDistance(combined: combined, whole: whole, tiles: tiles)
    }

    /// 同じ位置の領域どうしの距離の平均。領域の数や次元が揃っていなければ nil。
    static func meanTileDistance(_ a: [FeatureVector]?, _ b: [FeatureVector]?) -> Float? {
        guard let a, let b, !a.isEmpty, a.count == b.count,
              zip(a, b).allSatisfy({ $0.values.count == $1.values.count }) else { return nil }
        return zip(a, b).map { $0.distance(to: $1) }.sum() / Float(a.count)
    }

    /// 同じ連写のコマなら撮影間隔（撮影日時が両方ある場合のみ判定できる）。
    func burstInterval(_ a: PhotoAsset, _ b: PhotoAsset) -> TimeInterval? {
        guard let da = a.captureDate, let db = b.captureDate else { return nil }
        let interval = abs(db.timeIntervalSince(da))
        return interval <= configuration.burstInterval ? interval : nil
    }
}

/// 同じカメラで続けて撮った 2 枚の、グループ分けの判定。
public struct PhotoLink: Hashable, Sendable {
    public let previous: PhotoAsset
    public let next: PhotoAsset
    public let decision: LinkDecision
}

extension PhotoLink: Identifiable {
    /// 後の写真は 1 つの判定にしか現れないので、その ID で識別できる。
    public var id: PhotoAsset.ID { next.id }
}

/// 写真を直前のグループに入れたか、その理由。
public enum LinkDecision: Hashable, Sendable {
    /// 連写のため同じグループ（見た目は比べない）。
    case burst(interval: TimeInterval)
    /// 見た目が近いため同じグループ。距離はグループの直近メンバーのうち最も近いもの。
    case similar(distance: VisualDistance)
    /// 見た目が離れているため別グループ。特徴ベクトルが無く比べられなかった場合は nil。
    case different(distance: VisualDistance?)

    public var joins: Bool {
        switch self {
        case .burst, .similar: true
        case .different: false
        }
    }
}

/// 2 枚の見た目の距離と、その内訳。
public struct VisualDistance: Hashable, Sendable {
    /// 判定に使う距離（画像全体と領域ごとの平均を混ぜたもの）。
    public let combined: Float
    /// 画像全体の特徴ベクトルの距離。
    public let whole: Float
    /// 2×2 の領域ごとの距離の平均。領域ごとの比較をしていなければ nil。
    public let tiles: Float?

    public init(combined: Float, whole: Float, tiles: Float?) {
        self.combined = combined
        self.whole = whole
        self.tiles = tiles
    }
}
