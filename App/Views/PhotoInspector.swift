import FlowCore
import SwiftUI

/// 写真詳細画面の右側に表示する情報パネル。
///
/// 一般的な写真編集アプリでは調整用の UI を置く場所だが、このアプリは自動現像なので、
/// 選べるのはプリセットだけにし、あとは自動補正の内容・スコア・撮影情報の表示に充てる。
struct PhotoInspector: View {
    @Environment(AppModel.self) private var model
    let asset: PhotoAsset
    let group: SimilarGroup

    var body: some View {
        if let catalog = model.catalog {
            Form {
                presetSection(catalog)
                autoToneSection(catalog)
                scoreSection(catalog)
                captureSection
            }
            .formStyle(.grouped)
        }
    }

    // MARK: - プリセット

    private func presetSection(_ catalog: Catalog) -> some View {
        Section {
            Picker("プリセット", selection: Binding(
                get: { catalog.presetID },
                set: { model.setPreset($0) }
            )) {
                ForEach(DevelopPreset.builtIn) { preset in
                    Text(preset.name).tag(preset.id)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("プリセット")
        } footer: {
            Text("すべての写真に共通です。プレビューと書き出しに反映されます。")
        }
    }

    // MARK: - 自動補正

    private func autoToneSection(_ catalog: Catalog) -> some View {
        Section("自動補正") {
            if let recipe = catalog.autoRecipes[asset.id] {
                LabeledContent("露出", value: signed(recipe.exposure, unit: " EV"))
                LabeledContent("ハイライトの抑制", value: percent(recipe.highlights))
                LabeledContent("シャドウの持ち上げ", value: percent(recipe.shadows))
            } else if model.isAutoTonePaused {
                Label("一時停止中（撮って出しで表示）", systemImage: "pause.circle")
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("計算中（今は撮って出しで表示）")
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - スコア

    private func scoreSection(_ catalog: Catalog) -> some View {
        let selector = BestShotSelector()
        let analysis = catalog.analyses[asset.id]
        // グループ内での順位（スコアの高い順）
        let ranking = group.assetIDs.sorted { selector.score(catalog.analyses[$0]) > selector.score(catalog.analyses[$1]) }
        let rank = ranking.firstIndex(of: asset.id).map { $0 + 1 }

        return Section {
            if asset.id == group.bestAssetID {
                Label("ベストショット", systemImage: "star.fill").foregroundStyle(.yellow)
            }
            LabeledContent("総合スコア", value: decimal(selector.score(analysis)))
            if let rank, group.assetIDs.count > 1 {
                LabeledContent("グループ内の順位", value: "\(rank) 位 / \(group.assetIDs.count) 枚")
            }
            LabeledContent("美しさ", value: analysis?.aestheticsScore.map(decimal) ?? "—")
            LabeledContent("シャープネス", value: analysis?.sharpness.map(decimal) ?? "—")
            LabeledContent("顔の数", value: analysis.map { "\($0.faceCount)" } ?? "—")
            if let quality = analysis?.minimumFaceQuality {
                LabeledContent("顔の写り（最小）", value: decimal(quality))
            }
            if analysis?.isUtility == true {
                Label("記録用の写真と判定（減点）", systemImage: "doc.text.image")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("スコア")
        } footer: {
            Text("総合スコアが最も高い写真が、グループのベストショットになります。")
        }
    }

    // MARK: - 撮影情報

    private var captureSection: some View {
        let m = asset.metadata
        return Section("撮影情報") {
            LabeledContent("ファイル", value: asset.fileName)
            if let date = m.captureDate {
                LabeledContent("撮影日時", value: date.formatted(date: .abbreviated, time: .standard))
            }
            if let camera = [m.cameraMake, m.cameraModel].compactMap({ $0 }).joined(separator: " ").nonEmpty {
                LabeledContent("カメラ", value: camera)
            }
            if let lens = m.lensModel { LabeledContent("レンズ", value: lens) }
            if let focal = m.focalLength { LabeledContent("焦点距離", value: "\(Int(focal.rounded())) mm") }
            if let f = m.fNumber { LabeledContent("絞り", value: "f/\(f.formatted(.number.precision(.fractionLength(0...1))))") }
            if let t = m.exposureTime {
                LabeledContent("シャッター速度", value: t >= 1 ? "\(t.formatted()) 秒" : "1/\(Int((1 / t).rounded())) 秒")
            }
            if let iso = m.iso { LabeledContent("ISO", value: "\(iso)") }
            if let w = m.pixelWidth, let h = m.pixelHeight {
                LabeledContent("画素数", value: "\(w) × \(h)")
            }
        }
    }

    // MARK: - 表示形式

    private func decimal(_ value: Float) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    private func signed(_ value: Double, unit: String) -> String {
        value.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always(includingZero: false))) + unit
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
