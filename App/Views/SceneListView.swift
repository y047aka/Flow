import FlowCore
import SwiftUI

/// サイドバー: シーン（撮影時間のまとまり）の一覧。
struct SceneListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        List(selection: $model.selectedSceneID) {
            if let catalog = model.catalog {
                Section("\(catalog.assets.count) 枚 · \(catalog.scenes.count) シーン") {
                    ForEach(catalog.scenes) { scene in
                        SceneRow(scene: scene, catalog: catalog)
                            .tag(scene.id)
                    }
                }
                if !model.failures.isEmpty {
                    Section("読み込めなかったファイル") {
                        ForEach(model.failures.keys.sorted { $0.path < $1.path }, id: \.self) { url in
                            Label(url.lastPathComponent, systemImage: "exclamationmark.triangle")
                                .help(model.failures[url] ?? "")
                        }
                    }
                }
            }
        }
    }
}

private struct SceneRow: View {
    let scene: PhotoScene
    let catalog: Catalog

    var body: some View {
        HStack(spacing: 10) {
            if let bestID = scene.groups.first?.bestAssetID, let asset = catalog.assets[bestID] {
                AssetThumbnail(asset: asset, size: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(scene.startDate?.formatted(date: .abbreviated, time: .shortened) ?? "日時不明")
                Text("\(scene.assetIDs.count) 枚 · \(scene.groups.count) グループ")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
