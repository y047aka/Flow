import FlowCore
import SwiftUI

/// グループ分けの判定を確認する画面（閲覧のみ）。
///
/// 同じカメラで続けて撮った 2 枚ごとに、判定の結果と理由（連写の間隔・見た目の距離）を並べる。
/// 閾値の調整の目安にする。
struct GroupingDecisionsView: View {
    @Environment(AppModel.self) private var model
    @State private var filter: Filter = .all
    @State private var comparing: PhotoLink?

    enum Filter: String, CaseIterable, Identifiable {
        case all = "すべて"
        case joined = "同じグループ"
        case split = "別グループ"
        var id: Self { self }

        func includes(_ link: PhotoLink) -> Bool {
            switch self {
            case .all: true
            case .joined: link.decision.joins
            case .split: !link.decision.joins
            }
        }
    }

    var body: some View {
        if let catalog = model.catalog {
            content(catalog)
        } else {
            ContentUnavailableView("写真がありません", systemImage: "photo")
        }
    }

    private func content(_ catalog: Catalog) -> some View {
        let linksByScene = catalog.linksByScene
        let threshold = catalog.grouping.similarityThreshold

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DecisionSummary(links: linksByScene.values.flatMap { $0 }, threshold: threshold)

                Picker("表示", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                LazyVStack(alignment: .leading, spacing: 8, pinnedViews: [.sectionHeaders]) {
                    ForEach(catalog.scenes) { scene in
                        let links = (linksByScene[scene.id] ?? []).filter(filter.includes)
                        if !links.isEmpty {
                            Section {
                                ForEach(links) { link in
                                    DecisionRow(link: link, threshold: threshold) { comparing = link }
                                }
                            } header: {
                                HStack {
                                    Text(scene.startDate?.formatted(date: .complete, time: .omitted) ?? "日時不明")
                                        .font(.headline)
                                    Text("\(links.count) 組").foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background(.bar, in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("判定の確認")
        .sheet(item: $comparing) { link in
            PairComparisonSheet(link: link, threshold: threshold)
        }
    }
}

// MARK: - まとめ

private struct DecisionSummary: View {
    let links: [PhotoLink]
    let threshold: Float

    var body: some View {
        let bursts = links.filter { if case .burst = $0.decision { true } else { false } }.count
        let similar = links.filter { if case .similar = $0.decision { true } else { false } }.count
        let split = links.count - bursts - similar
        GroupBox {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow { Text("連写として同じグループ"); Text("\(bursts) 組").bold() }
                GridRow { Text("見た目が近く同じグループ"); Text("\(similar) 組").bold() }
                GridRow { Text("別グループ"); Text("\(split) 組").bold() }
            }
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("同じカメラで続けて撮った \(links.count) 組（閾値 \(threshold.formatted(.number.precision(.fractionLength(2)))))")
        }
    }
}

// MARK: - 1 組の行

private struct DecisionRow: View {
    let link: PhotoLink
    let threshold: Float
    let compare: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: compare) {
                HStack(spacing: 6) {
                    AssetThumbnail(asset: link.previous, size: 120).clipShape(RoundedRectangle(cornerRadius: 6))
                    Image(systemName: link.decision.joins ? "link" : "scissors").foregroundStyle(.secondary)
                    AssetThumbnail(asset: link.next, size: 120).clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .buttonStyle(.plain)
            .help("大きく表示して比べる")

            VStack(alignment: .leading, spacing: 4) {
                Text(link.decision.joins ? "同じグループ" : "別グループ").font(.headline)
                Text(link.decision.explanation(threshold: threshold))
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                Text("\(link.previous.fileName) → \(link.next.fileName)")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - 2 枚を大きく比べる

private struct PairComparisonSheet: View {
    @Environment(\.dismiss) private var dismiss
    let link: PhotoLink
    let threshold: Float

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                PreviewImage(asset: link.previous)
                PreviewImage(asset: link.next)
            }
            HStack {
                Text("\(link.previous.fileName) → \(link.next.fileName)")
                Text(link.decision.explanation(threshold: threshold)).foregroundStyle(.secondary)
                Spacer()
                Button("閉じる") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(minWidth: 800, minHeight: 500)
    }
}

/// 埋め込みプレビューを縦横比を保って表示する。
private struct PreviewImage: View {
    @Environment(AppModel.self) private var model
    let asset: PhotoAsset
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: asset.id) {
            image = await model.thumbnails.thumbnail(for: asset.fileURL)
        }
    }
}

extension LinkDecision {
    /// 判定の理由の説明。
    func explanation(threshold: Float) -> String {
        let format = FloatingPointFormatStyle<Float>.number.precision(.fractionLength(2))
        func describe(_ d: VisualDistance) -> String {
            d.tiles.map { "距離 \(d.combined.formatted(format))（全体 \(d.whole.formatted(format))・領域 \($0.formatted(format))）" }
                ?? "距離 \(d.combined.formatted(format))（全体のみ）"
        }
        return switch self {
        case .burst(let interval):
            "連写（\(interval.formatted(.number.precision(.fractionLength(1)))) 秒間隔）"
        case .similar(let distance):
            "\(describe(distance)) ≤ 閾値 \(threshold.formatted(format))"
        case .different(let distance?):
            "\(describe(distance)) > 閾値 \(threshold.formatted(format))"
        case .different(nil):
            "特徴ベクトルが無いため比較できません"
        }
    }
}
