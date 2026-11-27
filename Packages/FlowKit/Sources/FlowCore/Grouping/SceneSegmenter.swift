import Foundation

/// 撮影時刻（と任意で撮影位置）の不連続点で写真列をシーンに分割する。
public struct SceneSegmenter: Sendable {
    public struct Configuration: Sendable {
        /// これ以上撮影間隔が空いたら別シーンにする。
        public let maximumTimeGap: TimeInterval
        /// これ以上撮影位置が離れたら別シーンにする（両方に GPS がある場合のみ）。
        public let maximumDistance: Double?

        public init(maximumTimeGap: TimeInterval = 15 * 60, maximumDistance: Double? = 500) {
            self.maximumTimeGap = maximumTimeGap
            self.maximumDistance = maximumDistance
        }
    }

    public let configuration: Configuration

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    /// 撮影順にソートした上でシーンごとの配列を返す。撮影日時の無い写真は末尾の 1 シーンにまとめる。
    public func segment(_ assets: [PhotoAsset]) -> [[PhotoAsset]] {
        let datedScenes = assets
            .filter { $0.captureDate != nil }
            .sorted(by: Self.chronological)
            .chunked { !isBoundary(between: $0, and: $1) }
        let undated = assets
            .filter { $0.captureDate == nil }
            .sorted { $0.fileName < $1.fileName }
        return datedScenes + (undated.isEmpty ? [] : [undated])
    }

    func isBoundary(between a: PhotoAsset, and b: PhotoAsset) -> Bool {
        guard let da = a.captureDate, let db = b.captureDate else { return true }
        return db.timeIntervalSince(da) > configuration.maximumTimeGap || isFarApart(a, b)
    }

    /// 両方に位置情報があり、かつ閾値より離れているか。
    func isFarApart(_ a: PhotoAsset, _ b: PhotoAsset) -> Bool {
        guard let maximumDistance = configuration.maximumDistance,
              let la = a.metadata.location, let lb = b.metadata.location else { return false }
        return la.distance(to: lb) > maximumDistance
    }

    /// 撮影日時 → ファイル名の順で並べる（同一秒の連写をファイル名順で安定させる）。
    static func chronological(_ a: PhotoAsset, _ b: PhotoAsset) -> Bool {
        switch (a.captureDate, b.captureDate) {
        case let (da?, db?) where da != db: da < db
        default: a.fileName < b.fileName
        }
    }
}
