import FlowApple
import FlowCore
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var catalog: Catalog?
    /// 折り畳まれているシーン。既定はすべて開いた状態で、新しいシーンも開いた状態で現れる。
    var collapsedSceneIDs: Set<PhotoScene.ID> = []
    var activity: Activity?
    var failures: [URL: String] = [:]
    var errorMessage: String?
    var exportOptions = ExportOptions()

    /// 開いている写真。自動補正を最優先で計算する（一時停止中は計算しない）。
    var focusedAssetID: PhotoAsset.ID? {
        didSet {
            if let id = focusedAssetID, id != oldValue, !isAutoTonePaused { _ = autoToneTask(for: id) }
        }
    }

    /// ユーザーが自動補正の計算を一時停止しているか。保存しないので、起動し直すと再開する。
    private(set) var isAutoTonePaused = false

    let developer: CoreImageRAWDeveloper
    let thumbnails = ThumbnailProvider()

    @ObservationIgnored private var accessedFolders: [URL] = []
    private let store: CatalogStore
    private let autoTone: AutoToneService
    /// 自動補正を裏で順に計算するワーカー。
    @ObservationIgnored private var autoToneWorkers: [Task<Void, Never>] = []
    /// 計算中の写真ごとのタスク。同じ写真を二重に計算しないため、また完了を待てるようにするため。
    @ObservationIgnored private var autoToneTasks: [PhotoAsset.ID: Task<Void, Never>] = [:]
    /// 保存していない自動補正の件数。カタログ全体を書き直すので、毎回ではなくまとめて保存する。
    @ObservationIgnored private var unsavedAutoToneCount = 0
    private static let autoToneSaveInterval = 20

    struct Activity {
        var title: String
        var completed: Int
        var total: Int
        var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
    }

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        store = CatalogStore(fileURL: support.appendingPathComponent("Flow/catalog.json"))
        // init 内では全プロパティの初期化前に self.developer を読めないので、ローカル変数経由で渡す。
        let developer = CoreImageRAWDeveloper()
        self.developer = developer
        autoTone = .apple(developer: developer)
        do {
            // 保存済みのシーンは古いロジックで作られている場合があるので、読み込み時に現在のロジックで組み直す（数ミリ秒）。
            catalog = try store.load().map { $0.regrouped(with: $0.grouping) }
            if let bookmark = catalog?.sourceFolderBookmark { restoreAccess(bookmark) }
        } catch {
            errorMessage = "カタログを読み込めませんでした: \(error.localizedDescription)"
        }
        // 前回計算しきれなかった自動補正の続き
        startAutoTone()
    }

    var isBusy: Bool { activity != nil }

    // MARK: - シーンの開閉

    func isExpanded(_ sceneID: PhotoScene.ID) -> Bool {
        !collapsedSceneIDs.contains(sceneID)
    }

    func toggleScene(_ sceneID: PhotoScene.ID) {
        collapsedSceneIDs.formSymmetricDifference([sceneID])
    }

    // MARK: - 取り込み

    func importFolder(_ folder: URL) async {
        guard !isBusy else { return }
        startAccessing(folder)
        stopAutoTone()
        activity = Activity(title: "ファイルを検索中", completed: 0, total: 0)
        defer {
            activity = nil
            startAutoTone()
        }

        do {
            let files = try RawFileScanner().scan(folder)
            guard !files.isEmpty else {
                errorMessage = "フォルダに RAW ファイルが見つかりませんでした。"
                return
            }
            let pipeline = LibraryPipeline.apple()
            let result = try await pipeline.run(files: files, progress: { update in
                Task { @MainActor in
                    self.activity = Activity(title: update.stage.localizedTitle, completed: update.completed, total: update.total)
                }
            })
            let catalog = result.catalog
                .regrouped(with: groupingSettings)
                .with(presetID: self.catalog?.presetID ?? result.catalog.presetID)
                // 正解データはファイルの場所で記録しているので、取り込み直しても引き継げる
                .with(groupingLabels: self.catalog?.groupingLabels)
                .with(sourceFolderBookmark: try? folder.bookmarkData(options: Self.bookmarkCreationOptions))
            self.catalog = catalog
            failures = result.failures
            collapsedSceneIDs = []
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
        // シーンの ID は先頭の写真から決まるので、組み直しても開閉状態はそのまま保たれる。
        self.catalog = catalog.regrouped(with: settings)
    }

    /// 現在のグルーピング設定を保存する（スライダー操作の終わりなどに呼ぶ）。
    func commitGrouping() {
        save()
    }

    // MARK: - 判定の検証

    /// 続けて撮った 2 枚の正解（同じグループであるべきなら true、別なら false、nil で取り消し）を記録する。
    func setLabel(_ label: Bool?, for pair: PhotoPair) {
        catalog = catalog?.with(label: label, for: pair)
        save()
    }

    // MARK: - 自動補正（裏で計算）

    /// 自動補正の計算が残っているときの進捗。すべて済んでいれば nil。
    var autoToneProgress: (completed: Int, total: Int)? {
        guard let progress = catalog?.autoToneProgress, progress.completed < progress.total else { return nil }
        return progress
    }

    func isAutoTonePending(_ id: PhotoAsset.ID) -> Bool {
        catalog.map { $0.assets[id] != nil && $0.autoRecipes[id] == nil } ?? false
    }

    /// 自動補正の計算を一時停止する。計算中の 1 枚は最後まで計算して結果を残す。
    /// 書き出しは補正なしで書き出さないよう、停止中でも対象の写真だけはその場で計算する。
    func pauseAutoTone() {
        isAutoTonePaused = true
        stopAutoTone()
    }

    func resumeAutoTone() {
        isAutoTonePaused = false
        startAutoTone()
    }

    /// 未計算の写真の自動補正を、優先順（開いている写真 → ベストショット → 残り）に裏で計算し始める。
    /// 一時停止中は何もしない（取り込みや書き出しの後に呼ばれても再開しない）。
    func startAutoTone() {
        stopAutoTone()
        guard !isAutoTonePaused, catalog?.autoTonePriority().isEmpty == false else { return }
        autoToneWorkers = (0..<AutoToneService.backgroundConcurrency).map { _ in
            Task(priority: .utility) { await self.runAutoToneWorker() }
        }
    }

    /// 裏の計算を止める（計算中の 1 枚は最後まで計算して結果を残す）。
    func stopAutoTone() {
        autoToneWorkers.forEach { $0.cancel() }
        autoToneWorkers = []
        flushAutoTone()
    }

    /// 写真の自動補正が済むまで待つ（未計算なら今すぐ計算する）。
    func ensureAutoTone(for id: PhotoAsset.ID) async {
        await autoToneTask(for: id)?.value
    }

    /// 1 枚ずつ、その時点で最も優先度の高い未計算の写真を計算する。
    /// 毎回優先順を求め直すので、途中で開いた写真やグループの組み直しがすぐに反映される。
    private func runAutoToneWorker() async {
        while !Task.isCancelled, let id = nextAutoToneCandidate() {
            await ensureAutoTone(for: id)
        }
        if !Task.isCancelled { flushAutoTone() }
    }

    private func nextAutoToneCandidate() -> PhotoAsset.ID? {
        catalog?.autoTonePriority(focusedOn: focusedAssetID).first { autoToneTasks[$0] == nil }
    }

    /// 写真の自動補正を計算するタスク。計算中ならそのタスク、計算済み・対象外なら nil。
    private func autoToneTask(for id: PhotoAsset.ID) -> Task<Void, Never>? {
        if let running = autoToneTasks[id] { return running }
        guard let asset = catalog?.assets[id], catalog?.autoRecipes[id] == nil else { return nil }
        let service = autoTone
        let task = Task {
            // 失敗した写真（OS が未対応の RAW など）は撮って出しを記録し、計算を繰り返さない。
            let recipe = (try? await service.recipe(for: asset)) ?? DevelopRecipe()
            self.finishAutoTone(recipe, for: id)
        }
        autoToneTasks[id] = task
        return task
    }

    private func finishAutoTone(_ recipe: DevelopRecipe, for id: PhotoAsset.ID) {
        autoToneTasks[id] = nil
        // 計算中に別のフォルダを取り込んだ場合、新しいカタログには無い写真なので無視される。
        catalog = catalog?.with(autoRecipe: recipe, for: id)
        unsavedAutoToneCount += 1
        if unsavedAutoToneCount >= Self.autoToneSaveInterval { flushAutoTone() }
    }

    private func flushAutoTone() {
        if unsavedAutoToneCount > 0 { save() }
    }

    // MARK: - 書き出し

    /// 書き出し 1 件分の内容（何を・どこへ）。レシピは自動補正を待ってから決める。
    struct ExportJob {
        let asset: PhotoAsset
        let destination: URL
    }

    /// 各グループのベストショットの書き出し内容を決める（副作用の無い純粋な関数）。
    static func exportJobs(for catalog: Catalog, to folder: URL, options: ExportOptions) -> [ExportJob] {
        catalog.bestAssets.map { asset in
            ExportJob(
                asset: asset,
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
        // フル解像度の現像はメモリを大きく使うので、裏の自動補正は止めておく。
        stopAutoTone()
        let options = exportOptions
        let jobs = Self.exportJobs(for: catalog, to: folder, options: options)
        activity = Activity(title: "書き出し中", completed: 0, total: jobs.count)
        defer {
            activity = nil
            startAutoTone()
        }

        // ファイル書き込みという副作用を、フル解像度の現像がメモリを大きく使うので 1 枚ずつ順に実行する。
        for (index, job) in jobs.enumerated() where !Task.isCancelled {
            // 自動補正が未計算なら、その場で計算してから書き出す。
            await ensureAutoTone(for: job.asset.id)
            let recipe = (self.catalog ?? catalog).recipe(for: job.asset.id)
            do {
                try await developer.export(job.asset, recipe: recipe, options: options, to: job.destination)
            } catch {
                failures[job.asset.fileURL] = error.localizedDescription
            }
            activity?.completed = index + 1
        }
    }

    // MARK: - 永続化とファイルアクセス

    private func save() {
        guard let catalog else { return }
        unsavedAutoToneCount = 0
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
        case .grouping: "グループ分け中"
        }
    }
}
