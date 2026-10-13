import MusicMemoCore
import Observation
import Foundation
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
    /// 譜面に見えているトラック数（縦スクロール）。
    var visibleTrackCount = 0

    init(sketch: Sketch = SampleData.sketch03()) {
        self.sketch = sketch
        self.editor = SampleData.editorState(for: sketch)
        #if DEBUG
        // 開発用：MUSICMEMO_ZOOM=2 などで起動時の倍率を指定する（ズーム時の画面確認用）
        if let zoom = ProcessInfo.processInfo.environment["MUSICMEMO_ZOOM"].flatMap(Double.init) {
            editor.zoom = zoom
        }
        #endif
    }

    var layout: ScoreLayout {
        layout(zoom: editor.zoom)
    }

    func layout(zoom: Double) -> ScoreLayout {
        ScoreLayout(
            zoom: zoom,
            timeSignature: sketch.timeSignature,
            keySignature: KeySignature(sketch.key),
            barCount: sketch.barCount
        )
    }

    // MARK: ズーム

    /// 倍率の範囲（SPEC 未決事項。触りながら調整する）。
    static let zoomRange: ClosedRange<Double> = 0.4...2.5
    /// 倍率HUDとメニューの −／＋ で移る段階。
    static let zoomSteps: [Double] = [0.4, 0.5, 0.75, 1, 1.5, 2, 2.5]

    /// 倍率を変える。譜面部分の左端から anchorX の位置にある内容（コンテンツ座標 contentX）がその場に残るよう横スクロールを補正する。
    /// ピンチ中はジェスチャ開始時の値（baseZoom, contentX）を渡し、途中の誤差がたまらないようにする。
    func setZoom(_ zoom: Double, anchorX: CGFloat? = nil, contentX: CGFloat? = nil, baseZoom: Double? = nil) {
        let newZoom = min(max(zoom, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        let anchor = anchorX ?? visibleStaffWidth / 2
        let base = baseZoom ?? editor.zoom
        let pointX = contentX ?? horizontalOffset + anchor
        editor.zoom = newZoom
        // コンテンツ座標は倍率に比例する
        let target = pointX * CGFloat(newZoom / base) - anchor
        horizontalOffset = min(max(target, 0), max(layout.contentWidth - visibleStaffWidth, 0))
        horizontalPosition.scrollTo(x: horizontalOffset)
    }

    /// 段階的に拡大（+1）／縮小（-1）する。
    func stepZoom(_ direction: Int) {
        let current = editor.zoom
        let next = direction > 0
            ? Self.zoomSteps.first { $0 > current + 0.001 }
            : Self.zoomSteps.last { $0 < current - 0.001 }
        if let next { setZoom(next) }
    }

    /// 全体ビューの枠の幅を変えたとき：小節 start〜end（0始まりの小数）がちょうど見える倍率にする。
    /// keepEnd が true なら右端（end）を、false なら左端（start）を動かさない。
    func zoomToShow(barsFrom start: CGFloat, to end: CGFloat, keepEnd: Bool) {
        let bars = max(end - start, 0.25)
        let unit = layout(zoom: 1)
        // 見える幅 = 固定領域（倍率に比例）＋ 小節数 × 小節幅（倍率に比例）
        let zoom = Double(visibleStaffWidth / (unit.stickyWidth + bars * unit.barWidth))
        let newZoom = min(max(zoom, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        editor.zoom = newZoom
        let layout = layout
        let offset = keepEnd
            ? layout.contentLeading + end * layout.barWidth - visibleStaffWidth
            : layout.contentLeading + start * layout.barWidth - layout.stickyWidth
        horizontalOffset = min(max(offset, 0), max(layout.contentWidth - visibleStaffWidth, 0))
        horizontalPosition.scrollTo(x: horizontalOffset)
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

    /// 小節を選ぶ（全体ビューのカード）。編集位置を小節の頭へ移し、見えていなければスクロールする。
    func select(bar: Int) {
        setEditPosition(sketch.timeSignature.startTick(ofBar: bar))
        if !visibleBars.contains(bar) {
            scroll(toLeadingBar: bar)
        }
    }

    /// 譜面を指定の横スクロール量へ（範囲内に収める）。
    func scrollStaff(toOffset offset: CGFloat) {
        let maxOffset = max(layout.contentWidth - visibleStaffWidth, 0)
        horizontalPosition.scrollTo(x: min(max(offset, 0), maxOffset))
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

    func toggleMute(of id: Track.ID) {
        updateTrack(id) { $0.isMuted.toggle() }
    }

    func toggleSolo(of id: Track.ID) {
        updateTrack(id) { $0.isSoloed.toggle() }
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
