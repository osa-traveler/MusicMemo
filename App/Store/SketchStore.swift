import MusicMemoCore
import Observation
import SwiftUI

/// 編集中の曲と画面状態。画面はここを見て描き、操作はここを通して変える。
@MainActor
@Observable
final class SketchStore {
    var sketch: Sketch
    var editor: EditorState

    // 譜面の横スクロール（セクション行・全体ビューからも参照する）
    var horizontalPosition = ScrollPosition()
    /// 横スクロール量（コンテンツ座標の表示左端）。
    var horizontalOffset: CGFloat = 0
    /// 譜面部分（トラック情報列と縦スクロール列を除く）の表示幅。
    var visibleStaffWidth: CGFloat = 0

    init(sketch: Sketch = SampleData.sketch03()) {
        self.sketch = sketch
        self.editor = SampleData.editorState(for: sketch)
    }

    var layout: ScoreLayout {
        ScoreLayout(
            zoom: editor.zoom,
            timeSignature: sketch.timeSignature,
            keySignature: KeySignature(sketch.key),
            barCount: sketch.barCount
        )
    }

    /// 譜面に見えている小節（端で 20pt 未満しか見えていない小節は数えない）。
    var visibleBars: ClosedRange<Int> {
        let layout = layout
        let first = layout.bar(atContentX: horizontalOffset + layout.stickyWidth + 20)
        let last = layout.bar(atContentX: horizontalOffset + visibleStaffWidth - 20)
        return first...max(first, last)
    }

    var editPositionBar: Int {
        sketch.timeSignature.bar(containing: editor.editPosition)
    }

    /// 編集位置があるセクション。
    var currentSection: SongSection? {
        sketch.section(containingBar: editPositionBar)
    }

    /// 小節が表示領域の左端に来るように横スクロールする。
    func scroll(toLeadingBar bar: Int) {
        let layout = layout
        horizontalPosition.scrollTo(x: max(layout.barLineX(bar: bar) - layout.stickyWidth, 0))
    }

    /// 小節の頭へ編集位置を移し、そこが左端に来るようにスクロールする。
    func jump(toBar bar: Int) {
        setEditPosition(sketch.timeSignature.startTick(ofBar: bar))
        scroll(toLeadingBar: bar)
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
