import Foundation

/// 写真列をシーン（同じ日・同じ場所でのひとまとまりの撮影）に分割する。
///
/// 次の写真をそれまでのシーンに含めるかを、以下の順で判定する:
/// 1. 撮影日（`dayStartHour` を日の変わり目とする）が変わったら必ず区切る。
/// 2. 位置情報があれば、シーンの中心（それまでの撮影位置の平均）からの距離で判定する。
///    直前の写真ではなく中心と比べるので、少しずつ移動しながら撮った場合も区切れる。
///    同じ場所でも、長時間（`maximumTimeGapAtSameLocation`）空いたら区切る。
/// 3. 位置情報が無ければ区切らない（同じ撮影日は 1 シーン）。
public struct SceneSegmenter: Sendable {
    public struct Configuration: Sendable {
        /// シーンの中心からこれ以上離れたら別シーンにする（メートル）。nil なら位置情報を使わない。
        public let maximumDistance: Double?
        /// 同じ場所でも、これ以上撮影間隔が空いたら別シーンにする。
        public let maximumTimeGapAtSameLocation: TimeInterval
        /// 1 日の始まりとみなす時刻（0...23）。深夜の撮影を前日と同じシーンにまとめるため。
        public let dayStartHour: Int
        /// 撮影日の判定に使うタイムゾーン。
        public let timeZone: TimeZone

        public init(
            maximumDistance: Double? = 500,
            maximumTimeGapAtSameLocation: TimeInterval = 3 * 60 * 60,
            dayStartHour: Int = 4,
            timeZone: TimeZone = .current
        ) {
            self.maximumDistance = maximumDistance
            self.maximumTimeGapAtSameLocation = maximumTimeGapAtSameLocation
            self.dayStartHour = dayStartHour
            self.timeZone = timeZone
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
            .grouped { scene, next in !isBoundary(scene: scene, next: next) }
        let undated = assets
            .filter { $0.captureDate == nil }
            .sorted { $0.fileName < $1.fileName }
        return datedScenes + (undated.isEmpty ? [] : [undated])
    }

    /// `next` が、撮影順に並んだ `scene` とは別のシーンになるか。
    func isBoundary(scene: [PhotoAsset], next: PhotoAsset) -> Bool {
        guard let previous = scene.last, let d0 = previous.captureDate, let d1 = next.captureDate else { return true }
        if shootingDay(of: d0) != shootingDay(of: d1) { return true }
        guard let distance = distance(from: scene, to: next), let maximumDistance = configuration.maximumDistance else {
            return false
        }
        return distance > maximumDistance || d1.timeIntervalSince(d0) > configuration.maximumTimeGapAtSameLocation
    }

    /// シーンの中心（位置情報のある写真の平均位置）から `next` までの距離。どちらかに位置情報が無ければ nil。
    func distance(from scene: [PhotoAsset], to next: PhotoAsset) -> Double? {
        guard let location = next.metadata.location,
              let center = GeoCoordinate.centroid(of: scene.compactMap(\.metadata.location)) else { return nil }
        return center.distance(to: location)
    }

    /// 撮影日（`dayStartHour` 時を日の始まりとする）。
    func shootingDay(of date: Date) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = configuration.timeZone
        let shifted = date.addingTimeInterval(-TimeInterval(configuration.dayStartHour) * 3600)
        return calendar.dateComponents([.year, .month, .day], from: shifted)
    }

    /// 撮影日時 → ファイル名の順で並べる（同一秒の連写をファイル名順で安定させる）。
    static func chronological(_ a: PhotoAsset, _ b: PhotoAsset) -> Bool {
        switch (a.captureDate, b.captureDate) {
        case let (da?, db?) where da != db: da < db
        default: a.fileName < b.fileName
        }
    }
}

extension GeoCoordinate {
    /// 座標の単純平均。数 km 程度の範囲なら十分な精度。
    static func centroid(of coordinates: [GeoCoordinate]) -> GeoCoordinate? {
        guard !coordinates.isEmpty else { return nil }
        let n = Double(coordinates.count)
        return GeoCoordinate(
            latitude: coordinates.map(\.latitude).sum() / n,
            longitude: coordinates.map(\.longitude).sum() / n
        )
    }
}
