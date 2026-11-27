import Foundation

/// フォルダ内の RAW ファイルを列挙する。
public struct RawFileScanner: Sendable {
    /// 主要メーカーの RAW 拡張子（小文字）。
    public static let defaultExtensions: Set<String> = [
        "3fr", "arw", "cr2", "cr3", "crw", "dcr", "dng", "erf", "fff", "iiq", "k25", "kdc",
        "mef", "mos", "mrw", "nef", "nrw", "orf", "pef", "raf", "raw", "rw2", "rwl", "sr2", "srf", "srw", "x3f",
    ]

    public let extensions: Set<String>
    public let recursive: Bool

    public init(extensions: Set<String> = Self.defaultExtensions, recursive: Bool = true) {
        self.extensions = extensions
        self.recursive = recursive
    }

    public func scan(_ directory: URL) throws -> [URL] {
        let options: FileManager.DirectoryEnumerationOptions = recursive
            ? [.skipsHiddenFiles]
            : [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: options
        )
        return (enumerator?.compactMap { $0 as? URL } ?? [])
            .filter(isRawFile)
            .sorted { $0.path < $1.path }
    }

    func isRawFile(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
            && (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }
}
