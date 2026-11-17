#if DEBUG
import Foundation
import MusicMemoCore
import OSLog

/// 開発用：MUSICMEMO_SETTINGS_DEMO=1 で起動すると、曲の設定を開いた状態にする（撮影用。開くのは TopBarView）。
/// MUSICMEMO_SETTINGS_DEMO=2 なら、そのうえで曲の設定を変える（E♭ major へ移調、3/4、♩=96、小節数 +2）。
/// 結果をログ（category == "SettingsDemo"）に出す。
enum DebugSettingsDemo {
    @MainActor
    static func runIfRequested(_ store: SketchStore) {
        guard ProcessInfo.processInfo.environment["MUSICMEMO_SETTINGS_DEMO"] == "2" else { return }
        let log = Logger(subsystem: "MusicMemo", category: "SettingsDemo")
        let before = store.sketch
        store.setKey(Key(tonic: 3, mode: .major), transpose: true)
        store.setTimeSignature(TimeSignature(beats: 3, beatUnit: 4))
        store.setTempo(95)
        store.setTempo(96)  // テンポの続けた変更は、元に戻す1回分にまとまる
        store.setBarCount(store.sketch.barCount + 2)
        let after = store.sketch
        log.info("""
            \(before.key.description, privacy: .public) \(before.timeSignature.beats)/\(before.timeSignature.beatUnit) ♩=\(before.tempo) \(before.barCount)小節 \
            → \(after.key.description, privacy: .public) \(after.timeSignature.beats)/\(after.timeSignature.beatUnit) ♩=\(after.tempo) \(after.barCount)小節
            """)
        log.info("セクション: \(after.sections.map { "\($0.name) \($0.startBar)+\($0.barCount)" }.joined(separator: ", "), privacy: .public)")
        log.info("コード: \(after.chords.prefix(6).map(\.chord.symbol).joined(separator: " "), privacy: .public)")
        let notes = after.tracks.map { $0.notes.filter { !$0.isRest }.count }
        log.info("音符の数: \(before.tracks.map { $0.notes.filter { !$0.isRest }.count }.description, privacy: .public) → \(notes.description, privacy: .public)")
        // 元に戻す：4回（キー・拍子・テンポ・小節数）で元に戻るか
        for _ in 0..<4 { store.undo() }
        log.info("4回元に戻した: \(store.sketch == before ? "元どおり" : "違う", privacy: .public)")
        for _ in 0..<4 { store.redo() }
        log.info("4回やり直した: \(store.sketch == after ? "同じ" : "違う", privacy: .public)")
    }
}
#endif
