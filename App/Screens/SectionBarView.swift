import MusicMemoCore
import SwiftUI

/// セクション行。セクションの切り替え（Aメロ／サビ／＋セクション）と、右端に表示範囲と入力位置。
struct SectionBarView: View {
    let store: SketchStore

    var body: some View {
        HStack(spacing: 8) {
            ForEach(store.sketch.sections) { section in
                let isCurrent = store.currentSection?.id == section.id
                Button {
                    store.jump(toBar: section.startBar)
                } label: {
                    Text(section.name)
                        .font(.system(size: 12, weight: isCurrent ? .bold : .regular))
                        .foregroundStyle(isCurrent ? Palette.paper : Palette.inkSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(isCurrent ? Palette.ink : .clear, in: .capsule)
                        .overlay {
                            if !isCurrent { Capsule().strokeBorder(Palette.ruleStrong, lineWidth: 1) }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }

            // セクションの追加は未実装（操作は未決）
            Text("＋ セクション")
                .font(.system(size: 12))
                .foregroundStyle(Palette.inkSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .overlay(Capsule().strokeBorder(Palette.ruleStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))

            Spacer(minLength: 0)

            Text(status)
                .font(.system(size: 12))
                .foregroundStyle(Palette.inkSecondary)
                .monospacedDigit()
        }
        .frame(height: Metrics.sectionRowHeight)
    }

    /// 「表示 5〜8小節 · 入力位置 7小節 1拍目」
    private var status: String {
        let bars = store.visibleBars
        let position = store.sketch.timeSignature.position(of: store.editor.editPosition)
        let visible = bars.count == 1 ? "\(bars.lowerBound)小節" : "\(bars.lowerBound)〜\(bars.upperBound)小節"
        // トラック数は、全部が見えていないときかズーム中だけ出す（基準画面の100%には無い）
        let total = store.sketch.tracks.count
        let tracks = store.visibleTrackCount < total || store.editor.zoom != 1 ? " · \(store.visibleTrackCount)/\(total)トラック" : ""
        return "表示 \(visible)\(tracks) · 入力位置 \(position.bar)小節 \(position.beat)拍目"
    }
}
