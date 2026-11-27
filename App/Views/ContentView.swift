import FlowCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var isPickingFolder = false
    @State private var folderPurpose: FolderPurpose = .importPhotos
    @State private var isShowingGroupingSettings = false

    enum FolderPurpose { case importPhotos, export }

    var body: some View {
        NavigationSplitView {
            SceneListView()
                .navigationTitle("Flow")
        } detail: {
            NavigationStack {
                if let scene = model.selectedScene {
                    SceneGridView(scene: scene)
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
        }
        .toolbar { toolbarContent }
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

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Button { pickFolder(for: .importPhotos) } label: {
                Label("取り込み", systemImage: "square.and.arrow.down")
            }
            .disabled(model.isBusy)
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
