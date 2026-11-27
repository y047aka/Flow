import Foundation

/// 取り込まれた 1 枚の写真（RAW ファイル）。
public struct PhotoAsset: Identifiable, Codable, Hashable, Sendable {
    public typealias ID = UUID

    public let id: ID
    /// 取り込み元ファイルの URL（セッション中に有効な URL）。
    public let fileURL: URL
    /// 次回起動時にファイルへ再アクセスするための（セキュリティスコープ付き）ブックマーク。
    public let bookmarkData: Data?
    public let metadata: CaptureMetadata

    public init(id: ID = UUID(), fileURL: URL, bookmarkData: Data? = nil, metadata: CaptureMetadata) {
        self.id = id
        self.fileURL = fileURL
        self.bookmarkData = bookmarkData
        self.metadata = metadata
    }

    public var fileName: String { fileURL.lastPathComponent }

    /// 撮影日時。EXIF が無い場合は nil。
    public var captureDate: Date? { metadata.captureDate }
}

/// EXIF などから読み取った撮影情報。
public struct CaptureMetadata: Codable, Hashable, Sendable {
    public let captureDate: Date?
    public let cameraMake: String?
    public let cameraModel: String?
    public let lensModel: String?
    public let focalLength: Double?
    public let fNumber: Double?
    public let exposureTime: Double?
    public let iso: Int?
    public let pixelWidth: Int?
    public let pixelHeight: Int?
    public let location: GeoCoordinate?

    public init(
        captureDate: Date? = nil,
        cameraMake: String? = nil,
        cameraModel: String? = nil,
        lensModel: String? = nil,
        focalLength: Double? = nil,
        fNumber: Double? = nil,
        exposureTime: Double? = nil,
        iso: Int? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        location: GeoCoordinate? = nil
    ) {
        self.captureDate = captureDate
        self.cameraMake = cameraMake
        self.cameraModel = cameraModel
        self.lensModel = lensModel
        self.focalLength = focalLength
        self.fNumber = fNumber
        self.exposureTime = exposureTime
        self.iso = iso
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.location = location
    }
}

public struct GeoCoordinate: Codable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// 2 点間の距離（メートル、Haversine）。
    public func distance(to other: GeoCoordinate) -> Double {
        let r = 6_371_000.0
        let lat1 = latitude * .pi / 180, lat2 = other.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }
}
