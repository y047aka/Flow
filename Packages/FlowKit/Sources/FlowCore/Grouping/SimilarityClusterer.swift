import Foundation

/// シーン内の写真を「似たショット」のグループにまとめる。
///
/// 1. シーン内の写真をカメラごとに分ける（別のカメラの写真は同じグループにしない）。
///    カメラはシリアル番号があれば個体、無ければ機種で識別する（`CaptureMetadata.cameraIdentity`）。
/// 2. カメラごとに撮影順に走査し、次のどちらかを満たせば直前のグループに入れる:
///    - 連写: 直前の写真との撮影間隔が `burstInterval` 以内（見た目に関係なく同じグループ）
///    - 似たショット: グループの直近メンバーとの特徴ベクトルの距離が閾値以下（撮影間隔は問わない）
/// 3. すべてのカメラのグループを、先頭の写真の撮影順に並べる。
///
/// 各写真を直前のグループに入れたか・その理由は `PhotoLink` として記録され、判定の検証に使える。
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

        public init(maximumDistance: Float = 0.38, burstInterval: TimeInterval = 1, comparisonWindow: Int = 3) {
            self.maximumDistance = maximumDistance
            self.burstInterval = burstInterval
            self.comparisonWindow = comparisonWindow
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
        guard let vector = analyses[asset.id]?.featureVector,
              let distance = group
                .suffix(configuration.comparisonWindow)
                .compactMap({ analyses[$0.id]?.featureVector })
                .filter({ $0.values.count == vector.values.count })
                .map({ vector.distance(to: $0) })
                .min()
        else { return .different(distance: nil) }
        return distance <= configuration.maximumDistance ? .similar(distance: distance) : .different(distance: distance)
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

    /// 正解データのキー。
    public var pair: PhotoPair { PhotoPair(previous: previous, next: next) }
}

/// 写真を直前のグループに入れたか、その理由。
public enum LinkDecision: Hashable, Sendable {
    /// 連写のため同じグループ（見た目は比べない）。
    case burst(interval: TimeInterval)
    /// 見た目が近いため同じグループ。距離はグループの直近メンバーとの最小値。
    case similar(distance: Float)
    /// 見た目が離れているため別グループ。特徴ベクトルが無く比べられなかった場合は nil。
    case different(distance: Float?)

    public var joins: Bool {
        switch self {
        case .burst, .similar: true
        case .different: false
        }
    }
}
