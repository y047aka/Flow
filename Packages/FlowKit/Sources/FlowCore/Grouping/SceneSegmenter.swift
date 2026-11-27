import Foundation

/// 撮影時刻（と任意で撮影位置）の不連続点で写真列をシーンに分割する。
public struct SceneSegmenter: Sendable {
    public struct Configuration: Sendable {
        /// これ以上撮影間隔が空いたら別シーンにする。
        public var maximumTimeGap: TimeInterval
        /// これ以上撮影位置が離れたら別シーンにする（両方に GPS がある場合のみ）。
        public var maximumDistance: Double?

        public init(maximumTimeGap: TimeInterval = 15 * 60, maximumDistance: Double? = 500) {
            self.maximumTimeGap = maximumTimeGap
            self.maximumDistance = maximumDistance
        }
    }

    public var configuration: Configuration

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    /// 撮影順にソートした上でシーンごとの配列を返す。撮影日時の無い写真は末尾の 1 シーンにまとめる。
    public func segment(_ assets: [PhotoAsset]) -> [[PhotoAsset]] {
        let dated = assets.filter { $0.captureDate != nil }.sorted(by: Self.chronological)
        let undated = assets.filter { $0.captureDate == nil }.sorted { $0.fileName < $1.fileName }

        var scenes: [[PhotoAsset]] = []
        var current: [PhotoAsset] = []
        for asset in dated {
            if let previous = current.last, isBoundary(between: previous, and: asset) {
                scenes.append(current)
                current = []
            }
            current.append(asset)
        }
        if !current.isEmpty { scenes.append(current) }
        if !undated.isEmpty { scenes.append(undated) }
        return scenes
    }

    func isBoundary(between a: PhotoAsset, and b: PhotoAsset) -> Bool {
        guard let da = a.captureDate, let db = b.captureDate else { return true }
        if db.timeIntervalSince(da) > configuration.maximumTimeGap { return true }
        if let maxDistance = configuration.maximumDistance,
           let la = a.metadata.location, let lb = b.metadata.location,
           la.distance(to: lb) > maxDistance {
            return true
        }
        return false
    }

    /// 撮影日時 → ファイル名の順で並べる（同一秒の連写をファイル名順で安定させる）。
    static func chronological(_ a: PhotoAsset, _ b: PhotoAsset) -> Bool {
        switch (a.captureDate, b.captureDate) {
        case let (da?, db?) where da != db: return da < db
        default: return a.fileName < b.fileName
        }
    }
}
