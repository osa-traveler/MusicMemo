#if DEBUG
import Foundation
import MusicMemoCore
import OSLog

/// 開発用：環境変数 MUSICMEMO_INPUT_DEMO=1 で起動すると、決まった入力操作を流す（撮影で入力の流れを確かめる）。
/// MUSICMEMO_INPUT_DEMO=2 なら、続けて音符の選択・移動・削除を流し、最後はドラッグの途中で止める。
enum DebugInputDemo {
    @MainActor
    static func runIfRequested(_ store: SketchStore) {
        let mode = ProcessInfo.processInfo.environment["MUSICMEMO_INPUT_DEMO"]
        guard mode == "1" || mode == "2" else { return }
        // 7小節目：F4（4分）→ G4+B4 の和音（4分）→ 4分休符
        store.keyDown(65); store.keyUp(65)
        store.keyDown(67); store.keyDown(71); store.keyUp(67); store.keyUp(71)
        store.enterRest()
        // 8分で A4、⇧クリックで C5 を重ねる、続けて B4
        store.selectNoteValue(.eighth)
        store.keyDown(69); store.keyUp(69)
        store.keyDown(72, addToChord: true); store.keyUp(72)
        store.keyDown(71); store.keyUp(71)
        // タイをつけて B4 の2分音符（小節線をまたぐので分割してタイ）
        store.selectNoteValue(.half)
        store.toggleTie()
        store.keyDown(71); store.keyUp(71)
        // 2分で D5 を入れてから、戻って消す
        store.keyDown(74); store.keyUp(74)
        store.backspace()
        // 8.3：16分×2＋8分（連桁）、9小節目：3連8分×3、8分＋16分×2
        store.selectNoteValue(.sixteenth)
        for pitch in [72, 74] { store.keyDown(pitch); store.keyUp(pitch) }
        store.selectNoteValue(.eighth)
        store.keyDown(76); store.keyUp(76)
        store.toggleTriplet()
        for pitch in [77, 76, 74] { store.keyDown(pitch); store.keyUp(pitch) }
        store.toggleTriplet()
        store.keyDown(72); store.keyUp(72)
        store.selectNoteValue(.sixteenth)
        for pitch in [71, 69] { store.keyDown(pitch); store.keyUp(pitch) }
        if mode == "2" { runSelectionDemo(store) }
    }

    /// 音符の選択・移動・削除。当たり判定は、描くときと同じ座標（行の高さは最小値）で符頭の位置を指して確かめる。
    @MainActor
    private static func runSelectionDemo(_ store: SketchStore) {
        let log = Logger(subsystem: "MusicMemo", category: "SelectDemo")
        guard let trackID = store.editor.selectedTrackID else { return }
        let layout = store.layout
        let rowHeight = layout.minimumRowHeight
        let bar7 = store.sketch.timeSignature.startTick(ofBar: 7)

        func describe(_ notes: [Note]) -> String {
            notes.map { "\($0.start - bar7):\($0.pitch.map { Pitch.noteName($0) } ?? "rest")/\($0.duration)\($0.tiesToNext ? "~" : "")" }
                .joined(separator: " ")
        }
        func bar7Notes() -> String {
            describe(store.selectedTrack?.notes.filter { $0.start >= bar7 && $0.start < bar7 + 1920 * 2 } ?? [])
        }
        /// 符頭の位置を指して選ぶ。
        func click(tick: Tick, pitch: MIDINote?) {
            guard let track = store.selectedTrack else { return }
            let bottom = layout.bottomLineY(rowHeight: rowHeight)
            let position = pitch.map { track.clef.staffPosition(of: SpelledPitch($0, in: store.sketch.key)) } ?? Notation.middleLine
            // 符頭の中心から少し外した位置（当たり判定の余裕も確かめる）
            let point = CGPoint(x: layout.x(tick: tick) + 0.3 * layout.staffSpace,
                                y: layout.y(staffPosition: position, bottomLineY: bottom) + 0.2 * layout.staffSpace)
            guard let id = StaffRowView.hitNote(at: point, track: track, sketch: store.sketch, layout: layout, rowHeight: rowHeight) else {
                log.error("hit failed tick=\(tick - bar7) pitch=\(pitch ?? -1)")
                return
            }
            store.selectNote(id, track: trackID)
            log.notice("selected \(describe(store.selectedNotes), privacy: .public)")
        }

        log.notice("before   \(bar7Notes(), privacy: .public)")
        // F4 を選んで 全音上げ（G4）、オクターブ上げてから戻す
        click(tick: bar7, pitch: 65)
        store.nudgeSelection(semitones: 2)
        store.nudgeSelection(semitones: 12)
        store.nudgeSelection(semitones: -12)
        log.notice("moved    \(bar7Notes(), privacy: .public)")
        // 和音の B4 だけを消す
        click(tick: bar7 + 480, pitch: 71)
        store.deleteKey()
        log.notice("deleted  \(bar7Notes(), privacy: .public)")
        // 休符を選んで消す
        click(tick: bar7 + 960, pitch: nil)
        store.deleteKey()
        log.notice("rest del \(bar7Notes(), privacy: .public)")
        // 和音に残った G4 を、空いた3拍目へ（16分×4 右へ）
        click(tick: bar7 + 480, pitch: 67)
        for _ in 0..<4 { store.nudgeSelection(ticks: 120) }
        log.notice("shifted  \(bar7Notes(), privacy: .public)")
        // 小節線をまたぐタイの後半を選ぶ → 一続きで選ばれる。ドラッグの途中（右へ2拍、上へ2段）で止めて撮影
        click(tick: bar7 + 1920, pitch: 71)
        store.dragSelection(translation: CGSize(width: 2 * 48 * layout.zoom, height: -layout.staffSpace))
        store.scroll(toLeadingBar: 7)
        log.notice("dragging preview \(describe(store.noteDrag?.preview ?? []), privacy: .public)")
    }
}
#endif
