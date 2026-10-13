#if DEBUG
import Foundation
import MusicMemoCore

/// 開発用：環境変数 MUSICMEMO_INPUT_DEMO=1 で起動すると、決まった入力操作を流す（撮影で入力の流れを確かめる）。
enum DebugInputDemo {
    @MainActor
    static func runIfRequested(_ store: SketchStore) {
        guard ProcessInfo.processInfo.environment["MUSICMEMO_INPUT_DEMO"] == "1" else { return }
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
    }
}
#endif
