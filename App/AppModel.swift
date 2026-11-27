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
            let catalog = result.catalog
                .regrouped(with: groupingSettings)
                .with(presetID: self.catalog?.presetID ?? result.catalog.presetID)
                .with(sourceFolderBookmark: try? folder.bookmarkData(options: Self.bookmarkCreationOptions))
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
        catalog = catalog?.with(presetID: id)
        save()
    }

    // MARK: - グルーピング

    var groupingSettings: GroupingSettings { catalog?.grouping ?? .default }

    /// 現在の設定を変換してグルーピングし直す（解析はやり直さないので即時）。保存はしない。
    ///
    /// 新しい設定は「呼び出し時点の最新の設定」から作る。UI 側が描画時点の古い設定を持っていても、
    /// 他の項目を巻き戻してしまうことがない。
    func updateGrouping(_ transform: (GroupingSettings) -> GroupingSettings) {
        guard let catalog else { return }
        let settings = transform(catalog.grouping)
        guard settings != catalog.grouping else { return }
        // 選択中のシーンの先頭の写真を含むシーンを、組み直した後も選択し続ける。
        let anchor = selectedScene?.assetIDs.first
        let regrouped = catalog.regrouped(with: settings)
        self.catalog = regrouped
        selectedSceneID = anchor.flatMap { id in regrouped.scenes.first { $0.assetIDs.contains(id) }?.id }
            ?? regrouped.scenes.first?.id
    }

    /// 現在のグルーピング設定を保存する（スライダー操作の終わりなどに呼ぶ）。
    func commitGrouping() {
        save()
    }

    // MARK: - 書き出し

    /// 書き出し 1 件分の内容（何を・どのレシピで・どこへ）。
    struct ExportJob {
        let asset: PhotoAsset
        let recipe: DevelopRecipe
        let destination: URL
    }

    /// 各グループのベストショットの書き出し内容を決める（副作用の無い純粋な関数）。
    static func exportJobs(for catalog: Catalog, to folder: URL, options: ExportOptions) -> [ExportJob] {
        catalog.bestAssets.map { asset in
            ExportJob(
                asset: asset,
                recipe: catalog.recipe(for: asset.id),
                destination: folder
                    .appendingPathComponent(asset.fileURL.deletingPathExtension().lastPathComponent)
                    .appendingPathExtension(options.format.fileExtension)
            )
        }
    }

    /// 各グループのベストショットを書き出す。
    func exportBestShots(to folder: URL) async {
        guard let catalog, !isBusy else { return }
        startAccessing(folder)
        let options = exportOptions
        let jobs = Self.exportJobs(for: catalog, to: folder, options: options)
        activity = Activity(title: "書き出し中", completed: 0, total: jobs.count)
        defer { activity = nil }

        // ファイル書き込みという副作用を、フル解像度の現像がメモリを大きく使うので 1 枚ずつ順に実行する。
        for (index, job) in jobs.enumerated() where !Task.isCancelled {
            do {
                try await developer.export(job.asset, recipe: job.recipe, options: options, to: job.destination)
            } catch {
                failures[job.asset.fileURL] = error.localizedDescription
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
