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
        if mode == "3" { return runFrameCheck(store) }
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

    /// MUSICMEMO_PLAY_CHECK=3：15秒再生し、再生位置の更新の間隔（16ms ごとのはず。画面の処理が重いと延びる）と、
    /// 五線（StaffRowView）の作り直しの回数をログに出す（再生中のなめらかさの確認用）。
    @MainActor
    private static func runFrameCheck(_ store: SketchStore) {
        let log = Logger(subsystem: "MusicMemo", category: "FrameCheck")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            FrameProbe.reset()
            store.startPlayback()
            try? await Task.sleep(for: .seconds(15))
            store.stopPlayback()
            let intervals = FrameProbe.intervals.sorted()
            let average = intervals.reduce(0, +) / Double(max(intervals.count, 1))
            let p95 = intervals.isEmpty ? 0 : intervals[min(intervals.count - 1, Int(Double(intervals.count) * 0.95))]
            let slow = intervals.filter { $0 > 33 }.count
            let summary = String(format: "更新 %d 回・間隔 平均 %.1fms・95%% %.1fms・最大 %.1fms・33ms 超 %d 回・五線の作り直し %d 回・描画 %d 回 計 %.0fms 最大 %.1fms・横スクロール %d 回（%d トラック・%d 小節）",
                                 intervals.count, average, p95, intervals.last ?? 0, slow, FrameProbe.staffBodies,
                                 FrameProbe.staffDraws, FrameProbe.drawTotal, FrameProbe.drawMax, FrameProbe.scrolls,
                                 store.sketch.tracks.count, store.sketch.barCount)
            log.info("\(summary, privacy: .public)")
        }
    }
}

/// 開発用：再生中の画面の処理の重さを測る（MUSICMEMO_PLAY_CHECK=3）。
@MainActor
enum FrameProbe {
    static var intervals: [Double] = []
    static var staffBodies = 0
    static var scrolls = 0
    nonisolated(unsafe) static var staffDraws = 0
    nonisolated(unsafe) static var drawTotal = 0.0
    nonisolated(unsafe) static var drawMax = 0.0
    private static var last: ContinuousClock.Instant?

    static func reset() {
        intervals = []
        staffBodies = 0
        scrolls = 0
        staffDraws = 0
        drawTotal = 0
        drawMax = 0
        last = nil
    }

    /// 五線の描画（Canvas）の時間を足す。描き始めの時刻を渡す。
    nonisolated static func recordDraw(since start: ContinuousClock.Instant) {
        let duration = ContinuousClock.now - start
        let ms = Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
        staffDraws += 1
        drawTotal += ms
        drawMax = max(drawMax, ms)
    }

    /// 再生位置を更新するたびに呼ぶ。
    static func playheadUpdated() {
        let now = ContinuousClock.now
        if let last {
            let duration = now - last
            intervals.append(Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15)
        }
        last = now
    }
}
#endif
