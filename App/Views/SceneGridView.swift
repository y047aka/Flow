import FlowCore
import SwiftUI

/// シーン内の類似グループを、ベストショットを代表にしてグリッド表示する。
struct SceneGridView: View {
    @Environment(AppModel.self) private var model
    let scene: PhotoScene

    private let columns = [GridItem(.adaptive(minimum: 180), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(scene.groups) { group in
                    if let catalog = model.catalog, let best = group.bestAssetID.flatMap({ catalog.assets[$0] }) {
                        NavigationLink(value: group) {
                            GroupCell(asset: best, count: group.assetIDs.count)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(scene.startDate?.formatted(date: .long, time: .shortened) ?? "シーン")
        .navigationDestination(for: SimilarGroup.self) { group in
            GroupDetailView(group: group)
        }
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
