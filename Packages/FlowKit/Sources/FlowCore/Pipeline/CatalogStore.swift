import Foundation

/// カタログを JSON ファイルとして保存・読み込みする。
/// 数万枚規模になったら SQLite（GRDB など）への置き換えを検討する。
public struct CatalogStore: Sendable {
    public var fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> Catalog? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try Self.decoder.decode(Catalog.self, from: data)
    }

    public func save(_ catalog: Catalog) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try Self.encoder.encode(catalog)
        try data.write(to: fileURL, options: .atomic)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
