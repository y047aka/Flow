import Foundation

/// フォルダ内の RAW ファイルを列挙する。
public struct RawFileScanner: Sendable {
    /// 主要メーカーの RAW 拡張子（小文字）。
    public static let defaultExtensions: Set<String> = [
        "3fr", "arw", "cr2", "cr3", "crw", "dcr", "dng", "erf", "fff", "iiq", "k25", "kdc",
        "mef", "mos", "mrw", "nef", "nrw", "orf", "pef", "raf", "raw", "rw2", "rwl", "sr2", "srf", "srw", "x3f",
    ]

    public var extensions: Set<String>
    public var recursive: Bool

    public init(extensions: Set<String> = Self.defaultExtensions, recursive: Bool = true) {
        self.extensions = extensions
        self.recursive = recursive
    }

    public func scan(_ directory: URL) throws -> [URL] {
        let fm = FileManager.default
        var options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
        if !recursive { options.insert(.skipsSubdirectoryDescendants) }
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: options) else {
            return []
        }
        var result: [URL] = []
        for case let url as URL in enumerator where extensions.contains(url.pathExtension.lowercased()) {
            let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            if isFile { result.append(url) }
        }
        return result.sorted { $0.path < $1.path }
    }
}
