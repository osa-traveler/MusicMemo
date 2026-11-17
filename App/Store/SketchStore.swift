import MusicMemoCore
import Observation
import Foundation
import SwiftUI

/// 編集中の曲と画面状態。画面はここを見て描き、操作はここを通して変える。
@MainActor
@Observable
final class SketchStore {
    var sketch: Sketch {
        didSet { playbackScoreChanged() }
    }
    var editor: EditorState

    // 再生
    private(set) var isPlaying = false
    /// 再生位置（再生中だけ）。赤い線はこの位置に出す。
    private(set) var playheadTick: Tick?
    private(set) var isMetronomeOn = false
    private var playbackTask: Task<Void, Never>?

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
    /// 直前に積んだ変更のまとまり（テンポの −／＋ を続けて押したときなどは1つにまとめる）。
    private var lastUndoGroup: String?
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // 鍵盤入力の途中経過
    /// いま押されている鍵。
    private(set) var heldKeys: Set<MIDINote> = []
    /// 押している最中の入力（全部の鍵を離したら編集位置をその終わりへ進める）。
    private var pendingEntry: Range<Tick>?
    /// 直前に確定した入力（⇧クリックで音を重ねる先）。
    private var lastEntry: Range<Tick>?

    // 音符の選択（選択中のトラックの音符。画面だけの状態で、保存しない）
    /// 選んでいる音符。タイでつながった音は一続きで選ぶ。
    private(set) var selectedNoteIDs: Set<Note.ID> = []
    /// 選んだ音符のドラッグ中の状態（離すまで曲は変えず、移動先を半透明で出す）。
    struct NoteDrag {
        var ticks: Tick
        /// 上下に動かす段数（五線の1段 = 調の音階の1音）。
        var steps: Int
        /// 移動先に置かれる音符（動いていなければ空）。
        var preview: [Note]
    }
    private(set) var noteDrag: NoteDrag?

    // 入力パレット
    var inputMethod: InputMethod = .keyboard
    /// トラックごとの鍵盤の表示範囲（左端の C の MIDI ノート番号）。
    private var keyboardLowestC: [Track.ID: MIDINote] = [:]

    /// 鍵盤の音。
    private let sound = SoundEngine()

    init(file: SketchFile) {
        self.sketch = file.sketch
        self.editor = file.editor ?? EditorState(selectedTrackID: file.sketch.tracks.first?.id)
        if editor.selectedTrackID.map({ id in !sketch.tracks.contains { $0.id == id } }) ?? true {
            editor.selectedTrackID = sketch.tracks.first?.id
        }
        sound.prepare(sketch.tracks)
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
        if editor.selectedTrackID != id { clearNoteSelection() }
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
        clearNoteSelection()
        editor.previewPitch = pitch
        heldKeys.insert(pitch)
        if let id = editor.selectedTrackID { sound.noteOn(pitch, track: id) }
        // 再生中は音だけ鳴らして入力しない（赤い線が動いていて入る位置が分かりにくいため）
        guard !isPlaying, inputMethod == .keyboard, let trackIndex = selectedTrackIndex else { return }

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
        if let id = editor.selectedTrackID { sound.noteOff(pitch, track: id) }
        guard heldKeys.isEmpty, let range = pendingEntry else { return }
        pendingEntry = nil
        lastEntry = range
        advance(to: range.upperBound)
    }

    /// 休符を選択中の音価で入力して進める。
    func enterRest() {
        guard !isPlaying, inputMethod == .keyboard, let trackIndex = selectedTrackIndex else { return }
        clearNoteSelection()
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

    /// Delete キー・「戻って消す」ボタン：音符を選んでいればそれを消し、選んでいなければ戻って消す。
    func deleteKey() {
        hasNoteSelection ? deleteSelection() : backspace()
    }

    // MARK: 音符の選択・移動・削除

    var selectedNotes: [Note] {
        guard !selectedNoteIDs.isEmpty else { return [] }
        return selectedTrack?.notes.filter { selectedNoteIDs.contains($0.id) } ?? []
    }

    var hasNoteSelection: Bool { !selectedNotes.isEmpty }

    /// 選んだ音符のうち、動かすときの基準にする音（一番早い位置の、一番高い音）。横の移動量と、鳴らす音に使う。
    private var anchorNote: Note? {
        selectedNotes.min { ($0.start, -($0.pitch ?? -1)) < ($1.start, -($1.pitch ?? -1)) }
    }

    /// タイでつながった音は一続きで選ぶ。
    private func withTiedChains(_ ids: some Sequence<Note.ID>) -> Set<Note.ID> {
        guard let notes = selectedTrack?.notes else { return [] }
        var result = Set<Note.ID>()
        for id in ids where !result.contains(id) {
            result.formUnion(NoteEditing.tiedChain(containing: id, in: notes).map(\.id))
        }
        return result
    }

    /// 音符（休符）を選ぶ。そのトラックも選ぶ。音符なら音を鳴らす。
    /// toggles（Mac の ⇧クリック）なら、今の選択に足す（選んであれば外す）。
    func selectNote(_ id: Note.ID, track trackID: Track.ID, toggles: Bool = false) {
        guard !isPlaying else { return }
        selectTrack(trackID)
        let chain = withTiedChains([id])
        noteDrag = nil
        if toggles {
            selectedNoteIDs = selectedNoteIDs.isSuperset(of: chain) ? selectedNoteIDs.subtracting(chain) : selectedNoteIDs.union(chain)
        } else {
            selectedNoteIDs = chain
        }
        if selectedNoteIDs.isSuperset(of: chain), let pitch = selectedTrack?.notes.first(where: { $0.id == id })?.pitch {
            audition(pitch)
        }
    }

    func clearNoteSelection() {
        selectedNoteIDs = []
        noteDrag = nil
        selectionBox = nil
    }

    // MARK: 範囲選択

    /// 範囲選択の箱（トラックと、その行の座標）。
    struct SelectionBox {
        var trackID: Track.ID
        var rect: CGRect
    }
    private(set) var selectionBox: SelectionBox?
    /// 範囲選択を始める前の選択（⇧＋箱で足すとき）。
    private var boxBaseSelection: Set<Note.ID> = []

    /// 範囲選択を始める。箱はドラッグを始めたトラックの中だけ。adding（Mac の ⇧）なら今の選択に足す。
    func beginBoxSelection(track trackID: Track.ID, adding: Bool) {
        guard !isPlaying else { return }
        selectTrack(trackID)
        boxBaseSelection = adding ? selectedNoteIDs : []
        selectedNoteIDs = boxBaseSelection
        noteDrag = nil
        selectionBox = SelectionBox(trackID: trackID, rect: .zero)
    }

    /// 箱を広げる。hits は箱の中に符頭がある音符（ドラッグ中から選んだ表示にする）。
    func updateBoxSelection(rect: CGRect, hits: [Note.ID]) {
        guard let box = selectionBox else { return }
        selectionBox = SelectionBox(trackID: box.trackID, rect: rect)
        selectedNoteIDs = boxBaseSelection.union(withTiedChains(hits))
    }

    func endBoxSelection() {
        selectionBox = nil
        boxBaseSelection = []
    }

    // MARK: 移動・削除

    /// 矢印キー：選んだ音符を全部 ticks だけずらし、semitones 半音だけ上下する。
    func nudgeSelection(ticks: Tick = 0, semitones: Int = 0) {
        moveSelection(by: ticks, pitch: { $0 + semitones })
    }

    /// 選んだ音符を消す（跡は空白のまま）。
    func deleteSelection() {
        guard !isPlaying, let trackIndex = selectedTrackIndex, hasNoteSelection else { return }
        recordUndo()
        NoteEditing.delete(ids: selectedNoteIDs, in: &sketch.tracks[trackIndex])
        lastEntry = nil
        clearNoteSelection()
    }

    /// ドラッグ中：横は16分単位、縦は五線の1段（調の音階の音）単位で移動先を決め、半透明で出す。
    /// 複数選んでいるときは、全部を同じ量（同じ段数）だけ動かす。
    func dragSelection(translation: CGSize) {
        guard !isPlaying, let track = selectedTrack, let anchor = anchorNote else { return }
        let layout = layout
        let grid = RulerView.seekGrid
        var ticks: Tick = 0
        if abs(translation.width) >= CGFloat(grid) * layout.pointsPerTick / 2 {
            ticks = layout.tick(atContentX: layout.x(tick: anchor.start) + translation.width, grid: grid) - anchor.start
        }
        let steps = Int((-translation.height / (layout.staffSpace / 2)).rounded())
        let key = sketch.key
        let clef = track.clef
        let transform = { (pitch: MIDINote) -> MIDINote in
            guard steps != 0 else { return pitch }
            return clef.pitch(atStaffPosition: clef.staffPosition(of: SpelledPitch(pitch, in: key)) + steps, in: key)
        }
        if let pitch = anchor.pitch.map(transform), steps != noteDrag?.steps ?? 0 {
            audition(min(max(pitch, 0), 127))
        }

        var preview: [Note] = []
        if ticks != 0 || steps != 0 {
            var copy = track
            let ids = Set(NoteEditing.move(ids: selectedNoteIDs, by: ticks, pitch: transform, in: &copy,
                                           timeSignature: sketch.timeSignature, totalTicks: sketch.totalTicks))
            preview = copy.notes.filter { ids.contains($0.id) }
        }
        noteDrag = NoteDrag(ticks: ticks, steps: steps, preview: preview)
    }

    /// ドラッグを離した：移動先へ動かす。
    func endDragSelection() {
        guard let drag = noteDrag, let track = selectedTrack else { return }
        noteDrag = nil
        let key = sketch.key
        let clef = track.clef
        moveSelection(by: drag.ticks, pitch: { pitch in
            drag.steps == 0 ? pitch : clef.pitch(atStaffPosition: clef.staffPosition(of: SpelledPitch(pitch, in: key)) + drag.steps, in: key)
        }, playsSound: false)
    }

    private func moveSelection(by ticks: Tick, pitch transform: (MIDINote) -> MIDINote, playsSound: Bool = true) {
        guard !isPlaying, let trackIndex = selectedTrackIndex, let anchor = anchorNote else { return }
        var track = sketch.tracks[trackIndex]
        let ids = NoteEditing.move(ids: selectedNoteIDs, by: ticks, pitch: transform, in: &track,
                                   timeSignature: sketch.timeSignature, totalTicks: sketch.totalTicks)
        guard track != sketch.tracks[trackIndex] else { return }
        recordUndo()
        sketch.tracks[trackIndex] = track
        selectedNoteIDs = Set(ids)
        lastEntry = nil
        if playsSound, let pitch = anchor.pitch, transform(pitch) != pitch { audition(min(max(transform(pitch), 0), 127)) }
    }

    /// 選択中のトラックの音色で短く鳴らす（音符を選んだとき・上下に動かしたとき）。
    private func audition(_ pitch: MIDINote) {
        guard let id = editor.selectedTrackID else { return }
        sound.noteOn(pitch, track: id)
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            sound.noteOff(pitch, track: id)
        }
    }

    func undo() {
        lastUndoGroup = nil
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(Snapshot(sketch: sketch, editPosition: editor.editPosition))
        restore(snapshot)
    }

    func redo() {
        lastUndoGroup = nil
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(Snapshot(sketch: sketch, editPosition: editor.editPosition))
        restore(snapshot)
    }

    private func restore(_ snapshot: Snapshot) {
        clearNoteSelection()
        sketch = snapshot.sketch
        pendingEntry = nil
        lastEntry = nil
        setEditPosition(snapshot.editPosition)
        revealEditPosition()
    }

    /// 変更の前の状態を積む。group が直前と同じなら積まない（続けた操作を1回で戻す）。
    private func recordUndo(group: String? = nil) {
        defer { lastUndoGroup = group }
        if let group, group == lastUndoGroup, !undoStack.isEmpty { return }
        undoStack.append(Snapshot(sketch: sketch, editPosition: editor.editPosition))
        redoStack.removeAll()
    }

    // MARK: 曲の設定

    /// テキスト入力欄を編集中か（Mac の Delete・矢印・スペースのメニューを止める）。
    var isEditingText = false

    /// キーを変える。transpose が true なら音符とコードも移調する。
    func setKey(_ key: Key, transpose: Bool) {
        guard key != sketch.key else { return }
        changeSettings { SongSettings.setKey(key, transpose: transpose, in: &$0) }
    }

    func setTimeSignature(_ time: TimeSignature) {
        guard time != sketch.timeSignature else { return }
        changeSettings { SongSettings.setTimeSignature(time, in: &$0) }
    }

    func setTempo(_ tempo: Double) {
        guard tempo != sketch.tempo else { return }
        changeSettings(group: "tempo") { SongSettings.setTempo(tempo, in: &$0) }
    }

    func setBarCount(_ count: Int) {
        guard count != sketch.barCount else { return }
        changeSettings(group: "barCount") { SongSettings.setBarCount(count, in: &$0) }
    }

    private func changeSettings(group: String? = nil, _ change: (inout Sketch) -> Void) {
        clearNoteSelection()
        recordUndo(group: group)
        var changed = sketch
        change(&changed)
        sketch = changed
        pendingEntry = nil
        lastEntry = nil
        setEditPosition(editor.editPosition)
        if let tick = playheadTick, tick >= sketch.totalTicks { stopPlayback() }
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

    // MARK: 再生

    func togglePlayback() {
        isPlaying ? stopPlayback() : startPlayback()
    }

    /// 再生を始める。ループがオンなら再生範囲の始点から（編集位置が範囲内ならそこから）、オフなら編集位置から。
    func startPlayback() {
        guard !isPlaying else { return }
        clearNoteSelection()  // 再生中は選択・移動・削除をしない
        let range = sketch.playRange
        let start = sketch.isLooping && !range.contains(editor.editPosition) ? range.lowerBound : editor.editPosition
        isPlaying = true
        playheadTick = start
        lastPlaybackSketch = sketch
        sound.play(PlaybackScore(sketch, metronome: isMetronomeOn), from: start)
        playbackTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                self?.updatePlayhead()
            }
        }
    }

    /// 止める。赤い線は再生を始めた位置（編集位置）に戻る。
    func stopPlayback() {
        guard isPlaying else { return }
        isPlaying = false
        playheadTick = nil
        playbackTask?.cancel()
        playbackTask = nil
        sound.stop()
        revealEditPosition()
    }

    func toggleMetronome() {
        isMetronomeOn.toggle()
        if isPlaying { sound.updateMix(PlaybackScore(sketch, metronome: isMetronomeOn)) }
    }

    #if DEBUG
    /// 開発用：トラック名つきで出力レベルを測る。
    func debugMeasureLevels(seconds: Double) {
        sound.debugMeasureLevels(seconds: seconds, names: Dictionary(uniqueKeysWithValues: sketch.tracks.map { ($0.id, $0.name) }))
    }
    #endif

    private func updatePlayhead() {
        guard isPlaying, let tick = sound.playheadTick() else { return }
        if !sketch.isLooping, tick >= sketch.totalTicks {
            stopPlayback()
            return
        }
        playheadTick = tick
        followPlayhead(tick)
    }

    /// 再生位置が右端に近づいたら、ページ送りのようにスクロールする。ループで左へ戻ったときも追う。
    private func followPlayhead(_ tick: Tick) {
        let layout = layout
        let x = layout.x(tick: tick)
        let visibleStart = horizontalOffset + layout.stickyWidth
        let visibleEnd = horizontalOffset + visibleStaffWidth
        guard visibleStaffWidth > 0, x < visibleStart || x > visibleEnd - 40 else { return }
        scrollStaff(toOffset: x - layout.stickyWidth - 40)
    }

    /// 再生中に曲が変わったら、再生用の並びを作り直して同じ位置から続ける（ミュート・ソロだけなら切り替えるだけ）。
    private var lastPlaybackSketch: Sketch?
    private func playbackScoreChanged() {
        guard isPlaying else { return }
        let score = PlaybackScore(sketch, metronome: isMetronomeOn)
        if let tick = playheadTick, needsRebuild() {
            sound.play(score, from: tick)
        } else {
            sound.updateMix(score)
        }
        lastPlaybackSketch = sketch
    }

    private func needsRebuild() -> Bool {
        guard let last = lastPlaybackSketch else { return true }
        return last.tracks.map(\.notes) != sketch.tracks.map(\.notes)
            || last.playRange != sketch.playRange || last.isLooping != sketch.isLooping || last.tempo != sketch.tempo
            || last.timeSignature != sketch.timeSignature || last.barCount != sketch.barCount
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

    /// ファイルに保存する画面状態（入力予定の音高は保存しない）。
    var savedEditorState: EditorState {
        var state = editor
        state.previewPitch = nil
        return state
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
        sound.prepare([sketch.tracks[index]])
    }
}
