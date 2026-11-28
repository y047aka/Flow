import FlowCore
import SwiftUI

/// グループ分けの設定パネル。値を動かすと即座に組み直され、スライダーから手を離すと保存される。
struct GroupingSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let settings = model.groupingSettings
        Form {
            Section {
                SettingSlider(
                    value: settings.similarityThreshold,
                    range: GroupingSettings.similarityThresholdRange,
                    minimumLabel: "厳しい", maximumLabel: "ゆるい",
                    valueText: settings.similarityThreshold.formatted(.number.precision(.fractionLength(2))),
                    onChange: { value in model.updateGrouping { $0.with(similarityThreshold: value) } },
                    onCommit: model.commitGrouping
                )
                Toggle("領域ごとにも比べる（2×2）", isOn: Binding(
                    get: { settings.usesTileComparison },
                    set: { value in
                        model.updateGrouping { $0.with(usesTileComparison: value) }
                        model.commitGrouping()
                    }
                ))
            } header: {
                Text("似たショットの判定")
            } footer: {
                Text("同じ構図で別の人が写った写真がまとまってしまうときは「厳しい」側へ。同じカメラで 1 秒以内に撮った連写は、この設定に関係なく同じグループになります。別のカメラの写真は同じグループにしません。「領域ごとにも比べる」をオンにすると、画像を 4 分割した領域ごとの違いも距離に含め、同じ構図で人や物の位置が違う写真を分けやすくなります（この機能より前に取り込んだ写真には効きません。取り込み直すと有効になります）。\(summary)")
            }

            Section {
                Text("撮影日ごとに 1 シーンにまとめます（朝 4 時切り替え。深夜の撮影は前日に含めます）。")
                    .foregroundStyle(.secondary)
            } header: {
                Text("シーンの区切り")
            }

            Section {
                Button("初期値に戻す") {
                    model.updateGrouping { _ in .default }
                    model.commitGrouping()
                }
                .disabled(settings == .default)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 360, idealWidth: 400, minHeight: 300)
    }

    private var summary: String {
        guard let catalog = model.catalog else { return "" }
        let groups = catalog.scenes.map(\.groups.count).reduce(0, +)
        return "\n現在 \(catalog.assets.count) 枚 → \(catalog.scenes.count) シーン / \(groups) グループ"
    }
}

/// 値の変化を即時に通知し、ドラッグの終わりに確定（保存）を通知するスライダー。
///
/// `onEditingChanged` のクロージャはドラッグ開始時点のものが使われることがあるため、
/// 確定時には値を渡さない（値を渡すと、ドラッグ開始時点の古い値に巻き戻ってしまう）。
private struct SettingSlider<Value: BinaryFloatingPoint>: View where Value.Stride: BinaryFloatingPoint {
    let value: Value
    let range: ClosedRange<Value>
    let minimumLabel: String
    let maximumLabel: String
    let valueText: String
    let onChange: (Value) -> Void
    let onCommit: () -> Void

    var body: some View {
        HStack {
            Slider(
                value: Binding(get: { value }, set: onChange),
                in: range
            ) {
                EmptyView()
            } minimumValueLabel: {
                Text(minimumLabel).font(.caption)
            } maximumValueLabel: {
                Text(maximumLabel).font(.caption)
            } onEditingChanged: { editing in
                if !editing { onCommit() }
            }
            Text(valueText).monospacedDigit().frame(minWidth: 52, alignment: .trailing)
        }
    }
}
