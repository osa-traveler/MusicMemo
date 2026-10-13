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

    // 元に戻す／やり直す（曲データと編集位置の組を積む）
    private struct Snapshot {
        var sketch: Sketch
        var editPosition: Tick
    }
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // 鍵盤入力の途中経過
    /// いま押されている鍵。
    private(set) var heldKeys: Set<MIDINote> = []
    /// 押している最中の入力（全部の鍵を離したら編集位置をその終わりへ進める）。
    private var pendingEntry: Range<Tick>?
    /// 直前に確定した入力（⇧クリックで音を重ねる先）。
    private var lastEntry: Range<Tick>?

    // 入力パレット
    var inputMethod: InputMethod = .keyboard
    /// トラックごとの鍵盤の表示範囲（左端の C の MIDI ノート番号）。
    private var keyboardLowestC: [Track.ID: MIDINote] = [:]

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

    // MARK: 入力パレット

    var selectedTrack: Track? {
        sketch.tracks.first { $0.id == editor.selectedTrackID }
    }

    /// 編集位置で鳴っているコード（鍵盤のコードトーン表示）。
    var chordAtEditPosition: Chord? {
        sketch.chord(at: editor.editPosition)?.chord
    }

    /// 鍵盤の左端の C。初期値はトラックの音部記号に合わせる（ト音記号 C4、ヘ音記号 C2）。
    var keyboardLowestNote: MIDINote {
        guard let track = selectedTrack else { return 60 }
        return keyboardLowestC[track.id] ?? (track.clef == .bass ? 36 : 60)
    }

    /// 鍵盤を1オクターブずつ動かす（C1〜C7 の範囲）。
    func shiftKeyboard(octaves: Int) {
        guard let id = selectedTrack?.id else { return }
        keyboardLowestC[id] = min(max(keyboardLowestNote + octaves * 12, 24), 96)
    }

    // MARK: 入力（上書き方式）

    /// 鍵を押した。押している鍵が無ければ新しい音として入力し、他の鍵を押している間や addToChord のときは和音に重ねる。
    func keyDown(_ pitch: MIDINote, addToChord: Bool = false) {
        editor.previewPitch = pitch
        heldKeys.insert(pitch)
        guard inputMethod == .keyboard, let trackIndex = selectedTrackIndex else { return }

        if let range = pendingEntry ?? (addToChord ? lastEntry : nil) {
            // 和音に重ねる（押している途中の入力は同じ取り消し単位にまとめる）
            if pendingEntry == nil { recordUndo() }
            NoteEditing.addToChord(pitch: pitch, range: range, in: &sketch.tracks[trackIndex], timeSignature: sketch.timeSignature)
            return
        }

        recordUndo()
        let range = NoteEditing.enter(
            pitches: [pitch],
            at: editor.editPosition,
            duration: editor.duration.ticks,
            tieFromPrevious: editor.isTieOn,
            in: &sketch.tracks[trackIndex],
            timeSignature: sketch.timeSignature,
            totalTicks: sketch.totalTicks
        )
        editor.isTieOn = false  // タイは1回使うと戻す
        pendingEntry = range
    }

    /// 鍵を離した。全部離したら編集位置を入力した音の終わりへ進める。
    func keyUp(_ pitch: MIDINote) {
        heldKeys.remove(pitch)
        guard heldKeys.isEmpty, let range = pendingEntry else { return }
        pendingEntry = nil
        lastEntry = range
        advance(to: range.upperBound)
    }

    /// 休符を選択中の音価で入力して進める。
    func enterRest() {
        guard inputMethod == .keyboard, let trackIndex = selectedTrackIndex else { return }
        recordUndo()
        let range = NoteEditing.enter(
            pitches: [],
            at: editor.editPosition,
            duration: editor.duration.ticks,
            in: &sketch.tracks[trackIndex],
            timeSignature: sketch.timeSignature,
            totalTicks: sketch.totalTicks
        )
        lastEntry = range
        advance(to: range.upperBound)
    }

    /// 戻って消す：編集位置の直前の音符を消し、その位置へ戻る。
    func backspace() {
        guard let trackIndex = selectedTrackIndex else { return }
        var track = sketch.tracks[trackIndex]
        guard let start = NoteEditing.deleteBefore(editor.editPosition, in: &track) else { return }
        recordUndo()
        sketch.tracks[trackIndex] = track
        lastEntry = nil
        setEditPosition(start)
        revealEditPosition()
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(Snapshot(sketch: sketch, editPosition: editor.editPosition))
        restore(snapshot)
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(Snapshot(sketch: sketch, editPosition: editor.editPosition))
        restore(snapshot)
    }

    private func restore(_ snapshot: Snapshot) {
        sketch = snapshot.sketch
        pendingEntry = nil
        lastEntry = nil
        setEditPosition(snapshot.editPosition)
        revealEditPosition()
    }

    private func recordUndo() {
        undoStack.append(Snapshot(sketch: sketch, editPosition: editor.editPosition))
        redoStack.removeAll()
    }

    private var selectedTrackIndex: Int? {
        sketch.tracks.firstIndex { $0.id == editor.selectedTrackID }
    }

    private func advance(to tick: Tick) {
        setEditPosition(tick)
        revealEditPosition()
    }

    /// 編集位置が見えなくなったら、左から1/3あたりに来るようにスクロールする。
    func revealEditPosition() {
        let layout = layout
        let x = layout.x(tick: editor.editPosition)
        let visibleStart = horizontalOffset + layout.stickyWidth
        let visibleEnd = horizontalOffset + visibleStaffWidth
        guard visibleStaffWidth > 0, x < visibleStart + 8 || x > visibleEnd - 24 else { return }
        scrollStaff(toOffset: x - layout.stickyWidth - (visibleStaffWidth - layout.stickyWidth) / 3)
    }

    /// 音価を選ぶ。付点・3連符はそのまま保つ。
    func selectNoteValue(_ value: NoteValue) {
        editor.duration.value = value
    }

    func toggleDotted() {
        editor.duration.isDotted.toggle()
    }

    func toggleTriplet() {
        editor.duration.isTriplet.toggle()
    }

    func toggleTie() {
        editor.isTieOn.toggle()
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
