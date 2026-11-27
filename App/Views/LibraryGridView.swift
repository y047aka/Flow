import FlowCore
import SwiftUI

/// すべてのシーンを 1 つのグリッドに並べ、シーンごとに折り畳める一覧。
///
/// `LazyVGrid` の `Section` を使うので、画面に見えているセルだけが作られ、折り畳んだシーンのセルは 1 つも作られない。
/// シーンの見出しはスクロール中も上部に固定され、今どのシーンを見ているかが分かる。
struct LibraryGridView: View {
    @Environment(AppModel.self) private var model
    let catalog: Catalog

    private let columns = [GridItem(.adaptive(minimum: 180), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12, pinnedViews: [.sectionHeaders]) {
                ForEach(catalog.scenes) { scene in
                    Section {
                        if model.isExpanded(scene.id) {
                            ForEach(scene.groups) { group in
                                if let best = group.bestAssetID.flatMap({ catalog.assets[$0] }) {
                                    NavigationLink(value: group) {
                                        GroupCell(asset: best, count: group.assetIDs.count)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    } header: {
                        SceneHeader(scene: scene, catalog: catalog, isExpanded: model.isExpanded(scene.id)) {
                            withAnimation(.snappy) { model.toggleScene(scene.id) }
                        }
                    }
                }
            }
            .padding(.horizontal)

            if !model.failures.isEmpty {
                FailureList(failures: model.failures)
                    .padding()
            }
        }
    }
}

/// シーンの見出し。押すと開閉する。
private struct SceneHeader: View {
    let scene: PhotoScene
    let catalog: Catalog
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.right")
                    .font(.footnote.bold())
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundStyle(.secondary)
                if let bestID = scene.groups.first?.bestAssetID, let asset = catalog.assets[bestID] {
                    AssetThumbnail(asset: asset, size: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                Text(title).font(.headline)
                Text("\(scene.assetIDs.count) 枚 · \(scene.groups.count) グループ")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.bar, in: RoundedRectangle(cornerRadius: 10))
        .padding(.top, 8)
        .accessibilityLabel("\(title)、\(scene.assetIDs.count) 枚")
        .accessibilityValue(isExpanded ? "展開" : "折り畳み")
    }

    private var title: String {
        scene.startDate?.formatted(date: .complete, time: .omitted) ?? "日時不明"
    }
}

private struct GroupCell: View {
    let asset: PhotoAsset
    let count: Int

    var body: some View {
        AssetThumbnail(asset: asset, size: 180)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .topTrailing) {
                if count > 1 {
                    Label("\(count)", systemImage: "square.stack")
                        .font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(6)
                }
            }
    }
}

/// 読み込めなかったファイルの一覧（以前は左ペインに表示していたもの）。
private struct FailureList: View {
    let failures: [URL: String]

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(failures.keys.sorted { $0.path < $1.path }, id: \.self) { url in
                    Label(url.lastPathComponent, systemImage: "exclamationmark.triangle")
                        .help(failures[url] ?? "")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("読み込めなかったファイル（\(failures.count) 件）")
        }
    }
}

/// 埋め込みプレビューの正方形サムネイル。
struct AssetThumbnail: View {
    @Environment(AppModel.self) private var model
    let asset: PhotoAsset
    let size: CGFloat
    @State private var image: CGImage?

    var body: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                }
            }
            .frame(width: size, height: size)
            .clipped()
            .task(id: asset.id) {
                image = await model.thumbnails.thumbnail(for: asset.fileURL)
            }
    }
}
