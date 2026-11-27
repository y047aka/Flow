import FlowApple
import FlowCore
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var catalog: Catalog?
    var selectedSceneID: PhotoScene.ID?
    var activity: Activity?
    var failures: [URL: String] = [:]
    var errorMessage: String?
    var exportOptions = ExportOptions()

    let developer = CoreImageRAWDeveloper()
    let thumbnails = ThumbnailProvider()

    @ObservationIgnored private var accessedFolders: [URL] = []
    private let store: CatalogStore

    struct Activity {
        var title: String
        var completed: Int
        var total: Int
        var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
    }

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        store = CatalogStore(fileURL: support.appendingPathComponent("Flow/catalog.json"))
        do {
            catalog = try store.load()
            if let bookmark = catalog?.sourceFolderBookmark { restoreAccess(bookmark) }
            selectedSceneID = catalog?.scenes.first?.id
        } catch {
            errorMessage = "カタログを読み込めませんでした: \(error.localizedDescription)"
        }
    }

    var isBusy: Bool { activity != nil }

    var selectedScene: PhotoScene? {
        catalog?.scenes.first { $0.id == selectedSceneID }
    }

    // MARK: - 取り込み

    func importFolder(_ folder: URL) async {
        guard !isBusy else { return }
        startAccessing(folder)
        activity = Activity(title: "ファイルを検索中", completed: 0, total: 0)
        defer { activity = nil }

        do {
            let files = try RawFileScanner().scan(folder)
            guard !files.isEmpty else {
                errorMessage = "フォルダに RAW ファイルが見つかりませんでした。"
                return
            }
            let pipeline = LibraryPipeline.apple(developer: developer)
            let result = try await pipeline.run(files: files, progress: { update in
                Task { @MainActor in
                    self.activity = Activity(title: update.stage.localizedTitle, completed: update.completed, total: update.total)
                }
            })
            var catalog = result.catalog
            catalog.presetID = self.catalog?.presetID ?? catalog.presetID
            catalog.sourceFolderBookmark = try? folder.bookmarkData(options: Self.bookmarkCreationOptions)
            self.catalog = catalog
            failures = result.failures
            selectedSceneID = catalog.scenes.first?.id
            save()
        } catch is CancellationError {
            // ユーザーによるキャンセル
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - プリセット

    func setPreset(_ id: DevelopPreset.ID) {
        catalog?.presetID = id
        save()
    }

    // MARK: - 書き出し

    /// 各グループのベストショットを書き出す。
    func exportBestShots(to folder: URL) async {
        guard let catalog, !isBusy else { return }
        startAccessing(folder)
        let assets = catalog.bestAssets
        activity = Activity(title: "書き出し中", completed: 0, total: assets.count)
        defer { activity = nil }

        let options = exportOptions
        for (index, asset) in assets.enumerated() {
            if Task.isCancelled { break }
            let name = asset.fileURL.deletingPathExtension().lastPathComponent
            let destination = folder.appendingPathComponent(name).appendingPathExtension(options.format.fileExtension)
            do {
                // フル解像度の現像はメモリを大きく使うので 1 枚ずつ行う。
                try await developer.export(asset, recipe: catalog.recipe(for: asset.id), options: options, to: destination)
            } catch {
                failures[asset.fileURL] = error.localizedDescription
            }
            activity?.completed = index + 1
        }
    }

    // MARK: - 永続化とファイルアクセス

    private func save() {
        guard let catalog else { return }
        do { try store.save(catalog) } catch { errorMessage = "カタログを保存できませんでした: \(error.localizedDescription)" }
    }

    private func startAccessing(_ url: URL) {
        if url.startAccessingSecurityScopedResource() { accessedFolders.append(url) }
    }

    private func restoreAccess(_ bookmark: Data) {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: Self.bookmarkResolutionOptions,
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return }
        startAccessing(url)
    }

    #if os(macOS)
    private static let bookmarkCreationOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
    private static let bookmarkResolutionOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
    #else
    private static let bookmarkCreationOptions: URL.BookmarkCreationOptions = []
    private static let bookmarkResolutionOptions: URL.BookmarkResolutionOptions = []
    #endif
}

extension LibraryPipeline.Stage {
    var localizedTitle: String {
        switch self {
        case .readingMetadata: "撮影情報を読み込み中"
        case .analyzing: "写真を解析中"
        case .estimatingTone: "自動補正を計算中"
        case .grouping: "グループ分け中"
        }
    }
}
