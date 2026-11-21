import MusicMemoCore
import SwiftUI

/// 譜面の直接タップ（Mac）：ポインタを乗せた所に、入る予定の音を半透明の青で出す。五線（StaffRowView）の上に重ねる。
/// ポインタの位置は動かすたびに変わるので、ここで読む（五線は描き直さない）。
struct TapGhostLayer: View {
    let store: SketchStore
    let track: Track
    let layout: ScoreLayout
    let rowHeight: CGFloat

    var body: some View {
        if let hover = store.tapHover, hover.trackID == track.id {
            let duration = min(store.editor.duration.ticks, store.sketch.totalTicks - hover.tick)
            let note = Note(start: hover.tick, duration: max(duration, 1), pitch: hover.pitch)
            let chords = Notation.chords(for: [note], clef: track.clef, key: store.sketch.key, timeSignature: layout.timeSignature)
            // 符頭・旗・加線の分だけ広く
            let margin = 40 * layout.zoom
            let minX = layout.x(tick: hover.tick) - margin
            let maxX = (chords.map { layout.x(tick: $0.start) }.max() ?? minX) + margin
            Canvas { context, size in
                var context = context
                context.translateBy(x: -minX, y: 0)
                let drawing = NoteDrawing(layout: layout, bottomLineY: layout.bottomLineY(rowHeight: size.height),
                                          color: Palette.accent.opacity(0.45))
                for chord in chords {
                    drawing.draw(chord, in: context)
                }
            }
            .frame(width: maxX - minX, height: rowHeight)
            .offset(x: minX)
            .allowsHitTesting(false)
        }
    }
}
