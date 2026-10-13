import MusicMemoCore
import Observation

/// 編集中の曲と画面状態。画面はここを見て描き、操作はここを通して変える。
@MainActor
@Observable
final class SketchStore {
    var sketch: Sketch
    var editor: EditorState

    init(sketch: Sketch = SampleData.sketch03()) {
        self.sketch = sketch
        self.editor = SampleData.editorState(for: sketch)
    }

    func selectTrack(_ id: Track.ID) {
        editor.selectedTrackID = id
    }

    /// 編集位置を動かす（曲の範囲内に収める）。
    func setEditPosition(_ tick: Tick) {
        editor.editPosition = min(max(tick, 0), sketch.totalTicks - 1)
    }

    /// 再生範囲を変える。始点と終点は1拍以上あける。
    func setPlayRange(start: Tick? = nil, end: Tick? = nil) {
        let beat = sketch.timeSignature.ticksPerBeat
        var lower = start ?? sketch.playRange.lowerBound
        var upper = end ?? sketch.playRange.upperBound
        lower = min(max(lower, 0), sketch.totalTicks - beat)
        upper = min(max(upper, beat), sketch.totalTicks)
        if start != nil { lower = min(lower, upper - beat) }
        if end != nil { upper = max(upper, lower + beat) }
        sketch.playRange = lower..<upper
    }

    func toggleLoop() {
        sketch.isLooping.toggle()
    }

    func setVolume(_ volume: Int, of id: Track.ID) {
        updateTrack(id) { $0.volume = volume }
    }

    func setPan(_ pan: Int, of id: Track.ID) {
        updateTrack(id) { $0.pan = pan }
    }

    private func updateTrack(_ id: Track.ID, _ change: (inout Track) -> Void) {
        guard let index = sketch.tracks.firstIndex(where: { $0.id == id }) else { return }
        change(&sketch.tracks[index])
    }
}
