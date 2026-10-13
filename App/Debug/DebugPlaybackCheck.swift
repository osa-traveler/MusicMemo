#if DEBUG
import Foundation
import MusicMemoCore
import os

/// 開発用：MUSICMEMO_PLAY_CHECK=1 で起動すると、メトロノーム付きで再生し、
/// 0.5秒ごとの再生位置と、各トラックの出力レベルをログに出す（MUSICMEMO_SILENT=1 と併用して音を出さない）。
enum DebugPlaybackCheck {
    @MainActor
    static func runIfRequested(_ store: SketchStore) {
        let mode = ProcessInfo.processInfo.environment["MUSICMEMO_PLAY_CHECK"]
        guard mode == "1" || mode == "2" else { return }  // 2 なら出力レベルは測らない
        let log = Logger(subsystem: "MusicMemo", category: "PlayCheck")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))  // 音色の読み込みを待つ
            store.toggleMetronome()
            store.startPlayback()
            if mode == "1" { store.debugMeasureLevels(seconds: 3) }
            for step in 1...8 {
                try? await Task.sleep(for: .milliseconds(500))
                let tick = store.playheadTick ?? -1
                let position = tick >= 0 ? store.sketch.timeSignature.position(of: tick).description : "停止"
                log.info("再生位置 \(Double(step) * 0.5, format: .fixed(precision: 1))秒: \(position, privacy: .public)")
            }
            store.stopPlayback()
            log.info("停止後の編集位置: \(store.sketch.timeSignature.position(of: store.editor.editPosition).description, privacy: .public)")
        }
    }
}
#endif
