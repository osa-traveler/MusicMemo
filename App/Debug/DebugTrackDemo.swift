#if DEBUG
import Foundation
import MusicMemoCore
import OSLog

/// 開発用：MUSICMEMO_TRACK_DEMO でトラックの操作を自動で流す。結果はログ（category == "TrackDemo"）に出す。
/// - 1：先頭のトラックの設定を開く（撮影用。開くのは ScoreView）
/// - 2：トラックの追加・複製・設定の変更・並べ替え・削除をして、その状態で止める。最後に元に戻す／やり直すで戻るかを確かめる
/// - 3：再生しながら音色を何度か替え、トラックを足し、そのたびに再生し直して出力レベルを測る（落ちないかの確認）
enum DebugTrackDemo {
    static var mode: String? {
        ProcessInfo.processInfo.environment["MUSICMEMO_TRACK_DEMO"]
    }

    private static let log = Logger(subsystem: "MusicMemo", category: "TrackDemo")

    @MainActor
    static func runIfRequested(_ store: SketchStore) {
        switch mode {
        case "2": runEditing(store)
        case "3": Task { await runSoundCheck(store) }
        default: break
        }
    }

    private static func describe(_ sketch: Sketch) -> String {
        sketch.tracks.map { "\($0.name)[\($0.role.displayName)/\($0.clef.rawValue)/\($0.color.rawValue)/\($0.program)]" }
            .joined(separator: ", ")
    }

    @MainActor
    private static func runEditing(_ store: SketchStore) {
        let before = store.sketch
        log.info("前: \(describe(before), privacy: .public)")
        let piano = before.tracks[0].id
        store.addTrack(role: .bass, below: piano)                  // 1. Piano の下にベース
        store.setTrackProgram(24, of: piano)                       // 2. Piano → Nylon Guitar（名前も変わる）
        store.setTrackName("Lead", of: piano)                      // 3. 名前
        store.setTrackProgram(25, of: piano)                       // 4. 名前は Lead のまま
        store.setTrackRole(.other, of: piano)                      // 5
        store.setTrackColor(.ochre, of: piano)                     // 6
        let strings = store.sketch.tracks.last!.id
        store.moveTrack(strings, to: 0)                            // 7. Strings を先頭へ
        store.duplicateTrack(strings)                              // 8
        store.setTrackClef(.bass, of: store.sketch.tracks[1].id)   // 9. 複製したトラックをヘ音記号に
        let ePiano = store.sketch.tracks.first { $0.name == "E.Piano" }!.id
        store.removeTrack(ePiano)                                  // 10
        let after = store.sketch
        log.info("後: \(describe(after), privacy: .public) 選択: \(after.tracks.first { $0.id == store.editor.selectedTrackID }?.name ?? "-", privacy: .public)")
        for _ in 0..<10 { store.undo() }
        log.info("10回元に戻した: \(store.sketch == before ? "元どおり" : "違う: " + describe(store.sketch), privacy: .public)")
        for _ in 0..<10 { store.redo() }
        log.info("10回やり直した: \(store.sketch == after ? "同じ" : "違う: " + describe(store.sketch), privacy: .public)")
    }

    @MainActor
    private static func runSoundCheck(_ store: SketchStore) async {
        let wait = { (seconds: Double) in try? await Task.sleep(for: .seconds(seconds)) }
        await wait(1.5)
        let piano = store.sketch.tracks[0].id
        for (round, program) in [24, 40, 56, 0].enumerated() {
            store.startPlayback()
            await wait(0.8)
            store.setTrackProgram(program, of: piano)  // 再生中に替える → 止めてから読み込む
            log.info("\(round + 1)回目：音色 \(program) に替えた。再生中: \(store.isPlaying)")
            await wait(0.5)
        }
        store.startPlayback()
        await wait(0.5)
        store.addTrack(role: .pad)
        log.info("再生中にトラックを足した。再生中: \(store.isPlaying)")
        if let added = store.editor.selectedTrackID { store.setTrackName("Added Pad", of: added) }  // 出力レベルを分けて測る
        // 足したトラックに音符を入れて、全部のトラックが鳴るか測る
        store.setEditPosition(0)
        store.keyDown(72); store.keyUp(72)
        store.setEditPosition(0)
        store.startPlayback()
        store.debugMeasureLevels(seconds: 2)
        await wait(2.5)
        store.stopPlayback()
        log.info("確認おわり: トラック \(store.sketch.tracks.count)本")
    }
}
#endif
