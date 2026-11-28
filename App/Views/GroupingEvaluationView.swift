import Charts
import FlowCore
import SwiftUI

/// グループ分けの判定を検証する画面。
///
/// 同じカメラで続けて撮った 2 枚ごとに、判定の理由（連写の間隔・見た目の距離）と結果を並べ、
/// ユーザーが「同じ／別」の正解を付けられる。正解に対する正解率と、閾値を変えたときの誤りの数を表示する。
struct GroupingEvaluationView: View {
    @Environment(AppModel.self) private var model
    @State private var filter: Filter = .all
    @State private var sweep: [SweepPoint] = []
    @State private var comparing: ComparingPair?

    enum Filter: String, CaseIterable, Identifiable {
        case all = "すべて"
        case unlabeled = "正解が未設定"
        case errors = "誤判定"
        var id: Self { self }
    }

    /// 閾値を試す範囲（設定パネルのスライダーと同じ範囲を 0.02 刻み）。
    private static let sweepThresholds: [Float] = Array(
        stride(from: GroupingSettings.similarityThresholdRange.lowerBound,
               through: GroupingSettings.similarityThresholdRange.upperBound + 0.0001,
               by: 0.02)
    )

    var body: some View {
        if let catalog = model.catalog {
            content(catalog)
        } else {
            ContentUnavailableView("写真がありません", systemImage: "photo")
        }
    }

    private func content(_ catalog: Catalog) -> some View {
        let linksByScene = catalog.linksByScene
        let predictions = catalog.predictions(for: linksByScene.values.flatMap { $0.map(\.pair) })
        let labels = catalog.labels
        let threshold = catalog.grouping.similarityThreshold

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                EvaluationSummary(
                    evaluation: catalog.evaluation,
                    threshold: threshold,
                    sweep: sweep,
                    apply: { best in
                        model.updateGrouping { $0.with(similarityThreshold: best) }
                        model.commitGrouping()
                    }
                )

                Picker("表示", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                LazyVStack(alignment: .leading, spacing: 8, pinnedViews: [.sectionHeaders]) {
                    ForEach(catalog.scenes) { scene in
                        let links = (linksByScene[scene.id] ?? []).filter { link in
                            let predicted = predictions[link.pair] ?? link.decision.joins
                            return switch filter {
                            case .all: true
                            case .unlabeled: labels[link.pair] == nil
                            case .errors: labels[link.pair].map { $0 != predicted } ?? false
                            }
                        }
                        if !links.isEmpty {
                            Section {
                                ForEach(links, id: \.pair) { link in
                                    PairRow(
                                        link: link,
                                        threshold: threshold,
                                        predictedSame: predictions[link.pair] ?? link.decision.joins,
                                        label: labels[link.pair],
                                        setLabel: { model.setLabel($0, for: link.pair) },
                                        compare: { comparing = ComparingPair(link: link) }
                                    )
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
        .navigationTitle("判定の検証")
        // 閾値ごとの評価はグループ分けを数十回やり直すので、正解や設定が変わったときだけ裏で計算する。
        .task(id: SweepKey(labels: labels, grouping: catalog.grouping, assetCount: catalog.assets.count)) {
            let thresholds = Self.sweepThresholds
            let result = await Task.detached(priority: .userInitiated) { catalog.thresholdSweep(thresholds) }.value
            sweep = result.map { SweepPoint(threshold: $0.threshold, evaluation: $0.evaluation) }
        }
        .sheet(item: $comparing) { item in
            PairComparisonSheet(
                link: item.link,
                label: model.catalog?.labels[item.link.pair],
                setLabel: { model.setLabel($0, for: item.link.pair) }
            )
        }
    }

    private struct SweepKey: Equatable {
        let labels: [PhotoPair: Bool]
        let grouping: GroupingSettings
        let assetCount: Int
    }
}

struct SweepPoint: Identifiable {
    let threshold: Float
    let evaluation: GroupingEvaluation
    var id: Float { threshold }
}

/// 大きく比べる 2 枚（シートの表示用）。
struct ComparingPair: Identifiable {
    let link: PhotoLink
    var id: PhotoPair { link.pair }
}

// MARK: - 評価のまとめ

private struct EvaluationSummary: View {
    let evaluation: GroupingEvaluation
    let threshold: Float
    let sweep: [SweepPoint]
    let apply: (Float) -> Void

    var body: some View {
        GroupBox {
            if evaluation.labeledCount == 0 {
                Text("下の一覧で、続けて撮った 2 枚ごとに「同じ」「別」の正解を付けると、正解率と閾値ごとの誤りの数が表示されます。正解はカタログに保存され、閾値やロジックを変えても、同じフォルダを取り込み直しても引き継がれます。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    metrics
                    if sweep.count > 1 { chart }
                    if let best = bestThreshold {
                        HStack {
                            Text("誤りが最も少ない閾値: \(best.threshold.formatted(.number.precision(.fractionLength(2))))（誤り \(best.evaluation.errorCount) 件）")
                            Spacer()
                            Button("この閾値にする") { apply(best.threshold) }
                                .disabled(abs(best.threshold - threshold) < 0.005)
                        }
                    }
                }
            }
        } label: {
            Text("現在の閾値 \(threshold.formatted(.number.precision(.fractionLength(2)))) での評価")
        }
    }

    private var metrics: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            GridRow {
                Text("正解率")
                Text(evaluation.accuracy?.formatted(.percent.precision(.fractionLength(1))) ?? "—").bold()
                Text("正解を付けた \(evaluation.labeledCount) 組のうち").foregroundStyle(.secondary)
            }
            GridRow {
                Text("誤って統合")
                Text("\(evaluation.falseMerges) 件").bold().foregroundStyle(evaluation.falseMerges > 0 ? Color.red : Color.primary)
                Text("別のショットなのに同じグループにした").foregroundStyle(.secondary)
            }
            GridRow {
                Text("誤って分割")
                Text("\(evaluation.falseSplits) 件").bold().foregroundStyle(evaluation.falseSplits > 0 ? Color.orange : Color.primary)
                Text("同じショットなのに別のグループにした").foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
    }

    private var chart: some View {
        Chart {
            ForEach(sweep) { point in
                LineMark(x: .value("閾値", point.threshold), y: .value("件数", point.evaluation.falseMerges))
                    .foregroundStyle(by: .value("種類", "誤って統合"))
                LineMark(x: .value("閾値", point.threshold), y: .value("件数", point.evaluation.falseSplits))
                    .foregroundStyle(by: .value("種類", "誤って分割"))
                LineMark(x: .value("閾値", point.threshold), y: .value("件数", point.evaluation.errorCount))
                    .foregroundStyle(by: .value("種類", "誤りの合計"))
            }
            RuleMark(x: .value("閾値", threshold))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .top, alignment: .leading) {
                    Text("現在").font(.caption).foregroundStyle(.secondary)
                }
        }
        .chartForegroundStyleScale([
            "誤って統合": Color.red, "誤って分割": Color.orange, "誤りの合計": Color.primary,
        ])
        .chartXAxisLabel("閾値（小さいほど厳しい）")
        .chartYAxisLabel("誤りの件数")
        .frame(height: 180)
    }

    /// 誤りが最も少ない閾値。同数なら現在の閾値に近いもの。
    private var bestThreshold: SweepPoint? {
        sweep.min { a, b in
            (a.evaluation.errorCount, abs(a.threshold - threshold)) < (b.evaluation.errorCount, abs(b.threshold - threshold))
        }
    }
}

// MARK: - 1 組の行

private struct PairRow: View {
    let link: PhotoLink
    let threshold: Float
    let predictedSame: Bool
    let label: Bool?
    let setLabel: (Bool?) -> Void
    let compare: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: compare) {
                HStack(spacing: 6) {
                    AssetThumbnail(asset: link.previous, size: 120).clipShape(RoundedRectangle(cornerRadius: 6))
                    Image(systemName: predictedSame ? "link" : "scissors").foregroundStyle(.secondary)
                    AssetThumbnail(asset: link.next, size: 120).clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .buttonStyle(.plain)
            .help("大きく表示して比べる")

            VStack(alignment: .leading, spacing: 4) {
                Text(predictedSame ? "同じグループ" : "別グループ").font(.headline)
                Text(link.decision.explanation(threshold: threshold))
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                Text("\(link.previous.fileName) → \(link.next.fileName)")
                    .font(.caption).foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                LabelPicker(label: label, setLabel: setLabel)
                if let label {
                    let correct = label == predictedSame
                    Label(correct ? "判定は正しい" : "判定は誤り", systemImage: correct ? "checkmark.circle" : "xmark.circle")
                        .font(.caption)
                        .foregroundStyle(correct ? Color.green : Color.red)
                }
            }
        }
        .padding(8)
        .background(background, in: RoundedRectangle(cornerRadius: 10))
    }

    private var background: Color {
        switch label.map({ $0 == predictedSame }) {
        case nil: Color.secondary.opacity(0.06)
        case true?: Color.green.opacity(0.08)
        case false?: Color.red.opacity(0.12)
        }
    }
}

/// 正解の選択（未設定／同じ／別）。
private struct LabelPicker: View {
    let label: Bool?
    let setLabel: (Bool?) -> Void

    var body: some View {
        Picker("正解", selection: Binding(get: { label }, set: setLabel)) {
            Text("未設定").tag(Bool?.none)
            Text("同じ").tag(Bool?.some(true))
            Text("別").tag(Bool?.some(false))
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 220)
    }
}

// MARK: - 2 枚を大きく比べる

private struct PairComparisonSheet: View {
    @Environment(\.dismiss) private var dismiss
    let link: PhotoLink
    let label: Bool?
    let setLabel: (Bool?) -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                PreviewImage(asset: link.previous)
                PreviewImage(asset: link.next)
            }
            HStack {
                Text("\(link.previous.fileName) → \(link.next.fileName)").foregroundStyle(.secondary)
                Spacer()
                LabelPicker(label: label, setLabel: setLabel)
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
        return switch self {
        case .burst(let interval):
            "連写（\(interval.formatted(.number.precision(.fractionLength(1)))) 秒間隔）"
        case .similar(let distance):
            "距離 \(distance.formatted(format)) ≤ 閾値 \(threshold.formatted(format))"
        case .different(let distance?):
            "距離 \(distance.formatted(format)) > 閾値 \(threshold.formatted(format))"
        case .different(nil):
            "特徴ベクトルが無いため比較できません"
        }
    }
}
