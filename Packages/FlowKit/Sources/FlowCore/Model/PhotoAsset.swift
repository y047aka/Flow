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
    /// カメラ本体のシリアル番号（EXIF BodySerialNumber など）。記録しない機種もある。
    public let cameraSerialNumber: String?
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
        cameraSerialNumber: String? = nil,
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
        self.cameraSerialNumber = cameraSerialNumber
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

extension CaptureMetadata {
    /// 撮影したカメラを識別する値。シリアル番号があれば個体単位、無ければ機種単位で識別する。
    /// どちらも記録されていなければ nil（どのカメラか分からない）。
    public var cameraIdentity: CameraIdentity? {
        let make = cameraMake?.trimmingCharacters(in: .whitespaces) ?? ""
        let model = cameraModel?.trimmingCharacters(in: .whitespaces) ?? ""
        if let serial = cameraSerialNumber?.trimmingCharacters(in: .whitespaces), !serial.isEmpty {
            return .body(make: make, model: model, serialNumber: serial)
        }
        return make.isEmpty && model.isEmpty ? nil : .model(make: make, model: model)
    }
}

/// カメラの識別子。
public enum CameraIdentity: Hashable, Sendable {
    /// シリアル番号で特定した個体。
    case body(make: String, model: String, serialNumber: String)
    /// 機種のみ（同じ機種の別の個体とは区別できない）。
    case model(make: String, model: String)
}

public struct GeoCoordinate: Codable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}
