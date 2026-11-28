import FlowCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var isPickingFolder = false
    @State private var folderPurpose: FolderPurpose = .importPhotos
    @State private var isShowingGroupingSettings = false
    @State private var path = NavigationPath()

    enum FolderPurpose { case importPhotos, export }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let catalog = model.catalog {
                    LibraryGridView(catalog: catalog)
                } else {
                    ContentUnavailableView {
                        Label("写真を取り込む", systemImage: "camera.aperture")
                    } description: {
                        Text("RAW が入ったフォルダやカードを選ぶと、自動で整理・グループ分け・現像します。")
                    } actions: {
                        Button("フォルダを選択…") { pickFolder(for: .importPhotos) }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Flow")
            .navigationDestination(for: SimilarGroup.self) { group in
                GroupDetailView(group: group)
                    .toolbar { toolbarContent }
            }
            .navigationDestination(for: EvaluationRoute.self) { _ in
                GroupingEvaluationView()
            }
            .toolbar { toolbarContent }
        }
        .fileImporter(
            isPresented: $isPickingFolder,
            allowedContentTypes: [.folder]
        ) { result in
            guard case .success(let url) = result else { return }
            let purpose = folderPurpose
            Task {
                switch purpose {
                case .importPhotos: await model.importFolder(url)
                case .export: await model.exportBestShots(to: url)
                }
            }
        }
        .overlay {
            if let activity = model.activity { ActivityOverlay(activity: activity) }
        }
        .alert("エラー", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private func pickFolder(for purpose: FolderPurpose) {
        folderPurpose = purpose
        isPickingFolder = true
    }

    /// 一覧と詳細の両方に出すツールバー。
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            if let progress = model.autoToneProgress {
                AutoToneStatus(progress: progress, isPaused: model.isAutoTonePaused) {
                    model.isAutoTonePaused ? model.resumeAutoTone() : model.pauseAutoTone()
                }
            }
        }
        ToolbarItem {
            Button { pickFolder(for: .importPhotos) } label: {
                Label("取り込み", systemImage: "square.and.arrow.down")
            }
            .disabled(model.isBusy)
        }
        ToolbarItem {
            Button { path.append(EvaluationRoute()) } label: {
                Label("判定の検証", systemImage: "checklist")
            }
            .disabled(model.catalog == nil || model.isBusy)
        }
        ToolbarItem {
            Button { isShowingGroupingSettings = true } label: {
                Label("グループ分け", systemImage: "slider.horizontal.3")
            }
            .disabled(model.catalog == nil || model.isBusy)
            .popover(isPresented: $isShowingGroupingSettings) {
                GroupingSettingsView()
                    .environment(model)
            }
        }
        ToolbarItem {
            Picker("プリセット", selection: Binding(
                get: { model.catalog?.presetID ?? DevelopPreset.neutral.id },
                set: { model.setPreset($0) }
            )) {
                ForEach(DevelopPreset.builtIn) { preset in
                    Text(preset.name).tag(preset.id)
                }
            }
            .disabled(model.catalog == nil)
        }
        ToolbarItem {
            Button { pickFolder(for: .export) } label: {
                Label("ベストショットを書き出し", systemImage: "square.and.arrow.up")
            }
            .disabled(model.catalog == nil || model.isBusy)
        }
    }
}

/// ツールバーの自動補正の進捗と、一時停止／再開ボタン。
/// 判定の検証画面への遷移先。
struct EvaluationRoute: Hashable {}

private struct AutoToneStatus: View {
    let progress: (completed: Int, total: Int)
    let isPaused: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if isPaused {
                Image(systemName: "pause.circle").foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
            Text("自動補正\(isPaused ? "（停止中）" : "") \(progress.completed) / \(progress.total)")
                .font(.caption).monospacedDigit()
            Button(action: toggle) {
                Label(isPaused ? "自動補正を再開" : "自動補正を一時停止",
                      systemImage: isPaused ? "play.fill" : "pause.fill")
                    .labelStyle(.iconOnly)
            }
            .help(isPaused ? "自動補正の計算を再開します。"
                           : "自動補正の計算を一時停止します。計算が済んでいない写真は撮って出しで表示されます（書き出し時はその場で計算します）。")
        }
    }
}

private struct ActivityOverlay: View {
    let activity: AppModel.Activity

    var body: some View {
        VStack(spacing: 12) {
            Text(activity.title).font(.headline)
            if activity.total > 0 {
                ProgressView(value: activity.fraction)
                Text("\(activity.completed) / \(activity.total)")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .padding(24)
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
