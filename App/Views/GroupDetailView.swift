import FlowCore
import SwiftUI

/// 類似グループの詳細: 現在のプリセットで現像した大きなプレビューと、メンバーのフィルムストリップ。
struct GroupDetailView: View {
    @Environment(AppModel.self) private var model
    let group: SimilarGroup
    @State private var selectedID: PhotoAsset.ID?

    var body: some View {
        let currentID = selectedID ?? group.bestAssetID ?? group.assetIDs.first
        VStack(spacing: 0) {
            if let catalog = model.catalog, let id = currentID, let asset = catalog.assets[id] {
                DevelopedPreview(asset: asset, recipe: catalog.recipe(for: id))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                MetadataBar(asset: asset, analysis: catalog.analyses[id], isBest: id == group.bestAssetID,
                            isAutoTonePending: model.isAutoTonePending(id), isAutoTonePaused: model.isAutoTonePaused)
            }
            if group.assetIDs.count > 1 {
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
                    .padding()
                }
                .background(.bar)
            }
        }
        .navigationTitle("\(group.assetIDs.count) 枚の類似ショット")
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

private struct MetadataBar: View {
    let asset: PhotoAsset
    let analysis: ImageAnalysis?
    let isBest: Bool
    let isAutoTonePending: Bool
    let isAutoTonePaused: Bool

    var body: some View {
        HStack(spacing: 16) {
            if isBest { Label("ベスト", systemImage: "star.fill").foregroundStyle(.yellow) }
            Text(asset.fileName).bold()
            Text(exposureSummary).foregroundStyle(.secondary)
            Spacer()
            if isAutoTonePending {
                HStack(spacing: 6) {
                    if isAutoTonePaused {
                        Image(systemName: "pause.circle")
                        Text("自動補正は一時停止中（撮って出し）")
                    } else {
                        ProgressView().controlSize(.small)
                        Text("自動補正を計算中（今は撮って出し）")
                    }
                }
                .foregroundStyle(.secondary)
            }
            if let score = analysis?.aestheticsScore {
                Text("美しさ \(score, format: .number.precision(.fractionLength(2)))")
            }
            if let sharpness = analysis?.sharpness {
                Text("シャープ \(sharpness, format: .number.precision(.fractionLength(2)))")
            }
        }
        .font(.callout)
        .monospacedDigit()
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var exposureSummary: String {
        let m = asset.metadata
        let parts: [String?] = [
            m.cameraModel,
            m.focalLength.map { "\(Int($0))mm" },
            m.fNumber.map { "f/\($0.formatted(.number.precision(.fractionLength(0...1))))" },
            m.exposureTime.map { $0 >= 1 ? "\($0.formatted())s" : "1/\(Int((1 / $0).rounded()))s" },
            m.iso.map { "ISO \($0)" },
        ]
        return parts.compactMap { $0 }.joined(separator: "  ")
    }
}
