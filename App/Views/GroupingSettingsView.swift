import FlowCore
import SwiftUI

/// グループ分けの設定パネル。値を動かすと即座に組み直される。
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
                    valueText: settings.similarityThreshold.formatted(.number.precision(.fractionLength(2)))
                ) { value, persist in
                    model.updateGrouping(settings.with(similarityThreshold: value), persist: persist)
                }
            } header: {
                Text("似たショットの判定")
            } footer: {
                Text("同じ構図で別の人が写った写真がまとまってしまうときは「厳しい」側へ。\(summary)")
            }

            Section {
                Toggle("撮影日が変わったら区切る（朝 4 時切り替え）", isOn: Binding(
                    get: { settings.splitsByDay },
                    set: { model.updateGrouping(settings.with(splitsByDay: $0)) }
                ))
                LabeledContent("場所が離れたら区切る") {
                    Text(distanceText(settings.sceneDistance)).monospacedDigit()
                }
                SettingSlider(
                    value: settings.sceneDistance,
                    range: GroupingSettings.sceneDistanceRange,
                    minimumLabel: "100 m", maximumLabel: "5 km",
                    valueText: nil
                ) { value, persist in
                    model.updateGrouping(settings.with(sceneDistance: (value / 50).rounded() * 50), persist: persist)
                }
                LabeledContent("位置情報が無いときの撮影間隔") {
                    Text(Duration.seconds(settings.sceneTimeGap).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                        .monospacedDigit()
                }
                SettingSlider(
                    value: settings.sceneTimeGap,
                    range: GroupingSettings.sceneTimeGapRange,
                    minimumLabel: "5 分", maximumLabel: "3 時間",
                    valueText: nil
                ) { value, persist in
                    model.updateGrouping(settings.with(sceneTimeGap: (value / 300).rounded() * 300), persist: persist)
                }
            } header: {
                Text("シーンの区切り")
            } footer: {
                Text("位置情報がある写真は撮影場所で、無い写真は撮影間隔で区切ります。")
            }

            Section {
                Button("初期値に戻す") { model.updateGrouping(.default) }
                    .disabled(settings == .default)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 360, idealWidth: 400, minHeight: 440)
    }

    private var summary: String {
        guard let catalog = model.catalog else { return "" }
        let groups = catalog.scenes.map(\.groups.count).reduce(0, +)
        return "\n現在 \(catalog.assets.count) 枚 → \(catalog.scenes.count) シーン / \(groups) グループ"
    }

    private func distanceText(_ meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }
}

/// 値の変化を即時に通知し、ドラッグの終わりに「確定（保存）」を通知するスライダー。
private struct SettingSlider<Value: BinaryFloatingPoint>: View where Value.Stride: BinaryFloatingPoint {
    let value: Value
    let range: ClosedRange<Value>
    let minimumLabel: String
    let maximumLabel: String
    let valueText: String?
    /// (新しい値, 確定したか)
    let onChange: (Value, Bool) -> Void

    var body: some View {
        HStack {
            Slider(
                value: Binding(get: { value }, set: { onChange($0, false) }),
                in: range
            ) {
                EmptyView()
            } minimumValueLabel: {
                Text(minimumLabel).font(.caption)
            } maximumValueLabel: {
                Text(maximumLabel).font(.caption)
            } onEditingChanged: { editing in
                if !editing { onChange(value, true) }
            }
            if let valueText {
                Text(valueText).monospacedDigit().frame(minWidth: 40, alignment: .trailing)
            }
        }
    }
}
