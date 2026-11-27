import Foundation

/// 写真列を撮影日ごとのシーンに分割する。
///
/// 日の変わり目は `dayStartHour` 時（既定は朝 4 時）とし、深夜 0 時をまたぐ撮影は前日と同じシーンにする。
public struct SceneSegmenter: Sendable {
    public struct Configuration: Sendable {
        /// 1 日の始まりとみなす時刻（0...23）。深夜の撮影を前日と同じシーンにまとめるため。
        public let dayStartHour: Int
        /// 撮影日の判定に使うタイムゾーン。
        public let timeZone: TimeZone

        public init(dayStartHour: Int = 4, timeZone: TimeZone = .current) {
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
            .chunked { shootingDay(of: $0) == shootingDay(of: $1) }
        let undated = assets
            .filter { $0.captureDate == nil }
            .sorted { $0.fileName < $1.fileName }
        return datedScenes + (undated.isEmpty ? [] : [undated])
    }

    /// 撮影日（`dayStartHour` 時を日の始まりとする）。撮影日時が無ければ nil。
    func shootingDay(of asset: PhotoAsset) -> DateComponents? {
        asset.captureDate.map(shootingDay(of:))
    }

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
