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
