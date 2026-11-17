import MusicMemoCore
import SwiftUI

/// 曲の設定（トップバーの曲情報から開くポップオーバー）。キー・拍子・テンポ・小節数。
/// 変えたらすぐ曲に反映する（元に戻すで戻せる）。
struct SongSettingsView: View {
    let store: SketchStore

    /// キーを変えるとき、音符とコードも移調するか。
    @AppStorage("songSettings.transposes") private var transposes = true
    /// 小節数を減らすと音符が消えるときの確認（新しい小節数と消える音符の数）。
    @State private var pendingBarCount: (count: Int, removedNotes: Int)?

    private var sketch: Sketch { store.sketch }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("曲の設定")
                .font(.system(size: 15, weight: .bold))

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    label("キー")
                    HStack(spacing: 8) {
                        Picker("主音", selection: tonicBinding) {
                            ForEach(0..<12, id: \.self) { tonic in
                                Text(tonicName(tonic)).tag(tonic)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                        Picker("長調・短調", selection: modeBinding) {
                            Text("長調").tag(Key.Mode.major)
                            Text("短調").tag(Key.Mode.minor)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                }
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    Toggle("音符とコードも移調する", isOn: $transposes)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.inkSecondary)
                        #if os(macOS)
                        .toggleStyle(.checkbox)
                        #endif
                }
                GridRow {
                    label("拍子")
                    Picker("拍子", selection: timeBinding) {
                        ForEach(SongSettings.timeSignatures, id: \.self) { time in
                            Text("\(time.beats)/\(time.beatUnit)").tag(time)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                GridRow {
                    label("テンポ")
                    NumberStepper(prefix: "♩ =", value: Int(sketch.tempo.rounded()), range: SongSettings.tempoRange,
                                  isEditing: editingBinding) { store.setTempo(Double($0)) }
                }
                GridRow {
                    label("小節数")
                    NumberStepper(prefix: nil, value: sketch.barCount, range: SongSettings.barCountRange,
                                  isEditing: editingBinding, onCommit: requestBarCount)
                }
            }

            Text("拍子を変えると、音の時間はそのままで小節線を引き直します。")
                .font(.system(size: 11))
                .foregroundStyle(Palette.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: 330)
        .foregroundStyle(Palette.ink)
        .tint(Palette.accent)
        .alert("小節数を \(pendingBarCount?.count ?? 0) にしますか？", isPresented: alertBinding, presenting: pendingBarCount) { pending in
            Button("小節を減らす", role: .destructive) { store.setBarCount(pending.count) }
            Button("キャンセル", role: .cancel) {}
        } message: { pending in
            Text("\(pending.count + 1)小節目より後ろの音符（\(pending.removedNotes)個）が消えます。元に戻すで戻せます。")
        }
        .onDisappear { store.isEditingText = false }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Palette.inkSecondary)
            .gridColumnAlignment(.trailing)
    }

    /// 主音の名前。調号のつけ方（♯系か♭系か）に合わせる（短調の E♭ と D♯ など）。
    private func tonicName(_ tonic: PitchClass) -> String {
        let key = Key(tonic: tonic, mode: sketch.key.mode)
        return Pitch.name(of: tonic, preferFlats: key.prefersFlats)
    }

    private var tonicBinding: Binding<PitchClass> {
        Binding(get: { sketch.key.tonic },
                set: { store.setKey(Key(tonic: $0, mode: sketch.key.mode), transpose: transposes) })
    }

    private var modeBinding: Binding<Key.Mode> {
        Binding(get: { sketch.key.mode },
                set: { store.setKey(Key(tonic: sketch.key.tonic, mode: $0), transpose: transposes) })
    }

    private var timeBinding: Binding<TimeSignature> {
        Binding(get: { sketch.timeSignature }, set: { store.setTimeSignature($0) })
    }

    private var editingBinding: Binding<Bool> {
        Binding(get: { store.isEditingText }, set: { store.isEditingText = $0 })
    }

    private var alertBinding: Binding<Bool> {
        Binding(get: { pendingBarCount != nil }, set: { if !$0 { pendingBarCount = nil } })
    }

    /// 小節数を変える。減らして音符が消えるときは確かめる。
    private func requestBarCount(_ count: Int) {
        let removed = SongSettings.notesRemoved(byBarCount: count, in: sketch)
        if count < sketch.barCount, removed > 0 {
            pendingBarCount = (count, removed)
        } else {
            store.setBarCount(count)
        }
    }
}
