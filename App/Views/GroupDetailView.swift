import FlowCore
import SwiftUI

/// 類似グループの詳細: 現在のプリセットで現像した大きなプレビューと、メンバーのフィルムストリップ。
/// 右側に、プリセット・自動補正・スコア・撮影情報をまとめた開閉可能な情報パネルを表示する。
struct GroupDetailView: View {
    @Environment(AppModel.self) private var model
    let group: SimilarGroup
    @State private var selectedID: PhotoAsset.ID?
    /// 情報パネルの開閉（この端末の表示の好みとして覚えておく）。
    @AppStorage("photoInspectorPresented") private var isInspectorPresented = true

    /// 写真の周囲の余白。
    private static let margin: CGFloat = 24

    var body: some View {
        let currentID = selectedID ?? group.bestAssetID ?? group.assetIDs.first
        let hasFilmstrip = group.assetIDs.count > 1
        VStack(spacing: 0) {
            if let catalog = model.catalog, let id = currentID, let asset = catalog.assets[id] {
                DevelopedPreview(asset: asset, recipe: catalog.recipe(for: id))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // 複数枚のグループでは、下のフィルムストリップが下側の余白を兼ねる。
                    .padding(.horizontal, Self.margin)
                    .padding(.top, Self.margin)
                    .padding(.bottom, hasFilmstrip ? 0 : Self.margin)
            }
            if hasFilmstrip {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(group.assetIDs, id: \.self) { id in
                            if let asset = model.catalog?.assets[id] {
                                AssetThumbnail(asset: asset, size: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(id == currentID ? Color.accentColor : .clear, lineWidth: 3)
                                    }
                                    .onTapGesture { selectedID = id }
                            }
                        }
                    }
                    .padding(.horizontal, Self.margin)
                    .padding(.vertical, 16)
                }
                // 余白の一部として見えるよう、背景は付けない
                .scrollIndicators(.hidden)
            }
        }
        .navigationTitle("\(group.assetIDs.count) 枚の類似ショット")
        .inspector(isPresented: $isInspectorPresented) {
            if let id = currentID, let asset = model.catalog?.assets[id] {
                PhotoInspector(asset: asset, group: group)
                    .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
            }
        }
        .toolbar {
            ToolbarItem {
                Button { isInspectorPresented.toggle() } label: {
                    Label(isInspectorPresented ? "情報パネルを閉じる" : "情報パネルを開く", systemImage: "sidebar.trailing")
                }
                .help("プリセット・自動補正・スコア・撮影情報のパネルを開閉します")
            }
        }
        // 開いている写真の自動補正を最優先で計算させる。計算が済むとレシピが変わり、プレビューが再現像される。
        .task(id: currentID) { model.focusedAssetID = currentID }
        .onDisappear { model.focusedAssetID = nil }
    }
}

/// CIRAWFilter で実際に現像したプレビュー。プリセット変更で再現像される。
private struct DevelopedPreview: View {
    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var displayScale
    let asset: PhotoAsset
    let recipe: DevelopRecipe
    @State private var image: CGImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image {
                    Image(decorative: image, scale: 1).resizable().scaledToFit()
                } else {
                    ProgressView()
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .task(id: RenderKey(assetID: asset.id, recipe: recipe)) {
                let pixels = Int(max(proxy.size.width, proxy.size.height) * displayScale)
                let developer = model.developer
                let url = asset.fileURL
                let recipe = recipe
                // 現像は重いのでメインスレッド外で行う。
                image = try? await Task.detached(priority: .userInitiated) {
                    try developer.renderPreview(url: url, recipe: recipe, maximumPixelSize: max(pixels, 1024))
                }.value
            }
        }
    }

    private struct RenderKey: Equatable {
        var assetID: PhotoAsset.ID
        var recipe: DevelopRecipe
    }
}
