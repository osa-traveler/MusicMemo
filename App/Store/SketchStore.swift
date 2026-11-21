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
        /// 移動先に置かれる音符（トラックごと。動いていなければ空）。
        var preview: [Track.ID: [Note]]
    }
    private(set) var noteDrag: NoteDrag?

    // 入力パレット
    private(set) var inputMethod: InputMethod = .keyboard

    /// 入力方法を切り替える。譜面の直接タップでは、編集位置の入力予定の音（鍵盤で直前に入れた音）は出さない。
    func setInputMethod(_ method: InputMethod) {
        guard method.isAvailable else { return }
        inputMethod = method
        tapHover = nil
        if method == .scoreTap { editor.previewPitch = nil }
    }
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
        heldKeys.insert(pitch)
        if let id = editor.selectedTrackID { sound.noteOn(pitch, track: id) }
        // ドラムのトラックは音だけ鳴らす（その楽器の音。ドラムの入力はまだ作っていない）
        guard selectedTrack?.isDrums != true else { return }
        editor.previewPitch = pitch
        // 再生中は音だけ鳴らして入力しない（赤い線が動いていて入る位置が分かりにくいため）
        guard !isPlaying, inputMethod != .midiKeyboard, let trackIndex = selectedTrackIndex else { return }

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
        guard !isPlaying, inputMethod != .midiKeyboard, let trackIndex = selectedTrackIndex, !sketch.tracks[trackIndex].isDrums else { return }
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

    /// 選んだ音符（トラックをまたいで選べる）。
    var selectedNotes: [Note] {
        guard !selectedNoteIDs.isEmpty else { return [] }
        return sketch.tracks.flatMap { $0.notes.filter { selectedNoteIDs.contains($0.id) } }
    }

    var hasNoteSelection: Bool { !selectedNotes.isEmpty }

    /// 選んだ音符があるトラックの添字。
    private var selectedTrackIndices: [Int] {
        guard !selectedNoteIDs.isEmpty else { return [] }
        return sketch.tracks.indices.filter { sketch.tracks[$0].notes.contains { selectedNoteIDs.contains($0.id) } }
    }

    /// 選んだ音符のうち、動かすときの基準にする音（一番早い位置の、一番高い音）と、そのトラック。横の移動量と、鳴らす音に使う。
    private var anchor: (note: Note, trackID: Track.ID)? {
        sketch.tracks.flatMap { track in track.notes.filter { selectedNoteIDs.contains($0.id) }.map { ($0, track.id) } }
            .min { ($0.0.start, -($0.0.pitch ?? -1)) < ($1.0.start, -($1.0.pitch ?? -1)) }
            .map { (note: $0.0, trackID: $0.1) }
    }

    /// タイでつながった音は一続きで選ぶ（音符のあるトラックの中で探す）。
    private func withTiedChains(_ ids: some Sequence<Note.ID>) -> Set<Note.ID> {
        var result = Set<Note.ID>()
        for id in ids where !result.contains(id) {
            guard let track = sketch.tracks.first(where: { $0.notes.contains { $0.id == id } }) else { continue }
            result.formUnion(NoteEditing.tiedChain(containing: id, in: track.notes).map(\.id))
        }
        return result
    }

    /// 音符（休符）を選ぶ。そのトラックも選ぶ。音符なら音を鳴らす。
    /// toggles（Mac の ⇧クリック）なら、今の選択に足す（選んであれば外す）。別のトラックの音符も足せる。
    func selectNote(_ id: Note.ID, track trackID: Track.ID, toggles: Bool = false) {
        guard !isPlaying else { return }
        if toggles {
            editor.selectedTrackID = trackID  // 選択は残したまま、トラックだけ選ぶ
        } else {
            selectTrack(trackID)
        }
        let chain = withTiedChains([id])
        noteDrag = nil
        if toggles {
            selectedNoteIDs = selectedNoteIDs.isSuperset(of: chain) ? selectedNoteIDs.subtracting(chain) : selectedNoteIDs.union(chain)
        } else {
            selectedNoteIDs = chain
        }
        if selectedNoteIDs.isSuperset(of: chain), let pitch = sketch.tracks.first(where: { $0.id == trackID })?.notes.first(where: { $0.id == id })?.pitch {
            audition(pitch, track: trackID)
        }
    }

    func clearNoteSelection() {
        selectedNoteIDs = []
        noteDrag = nil
        selectionBox = nil
    }

    // MARK: 範囲選択

    /// 範囲選択の箱。rect はトラックの行を縦に並べた座標（x は譜面のコンテンツ座標、y は先頭のトラックの行の上端から）。
    /// 箱はトラックをまたげる。trackID はドラッグを始めたトラック（入力先として選ぶ）。
    struct SelectionBox {
        var trackID: Track.ID
        var rect: CGRect
    }
    private(set) var selectionBox: SelectionBox?
    /// 範囲選択を始める前の選択（⇧＋箱で足すとき）。
    private var boxBaseSelection: Set<Note.ID> = []

    /// 範囲選択を始める。adding（Mac の ⇧）なら今の選択に足す（別のトラックの選択も残す）。
    func beginBoxSelection(track trackID: Track.ID, adding: Bool) {
        guard !isPlaying else { return }
        if adding {
            editor.selectedTrackID = trackID
        } else {
            selectTrack(trackID)
        }
        boxBaseSelection = adding ? selectedNoteIDs : []
        selectedNoteIDs = boxBaseSelection
        noteDrag = nil
        selectionBox = SelectionBox(trackID: trackID, rect: .zero)
    }

    /// 箱を広げる。hits は箱の中に符頭がある音符（どのトラックのものでもよい。ドラッグ中から選んだ表示にする）。
    func updateBoxSelection(rect: CGRect, hits: [Note.ID]) {
        guard let box = selectionBox else { return }
        selectionBox = SelectionBox(trackID: box.trackID, rect: rect)
        selectedNoteIDs = boxBaseSelection.union(withTiedChains(hits))
    }

    func endBoxSelection() {
        // トラックをまたいで選んだら、一番上のトラックを選択中にする（下から上へ囲んでも、貼り付けの基準が上になるように）
        if selectedTrackIndices.count > 1, let top = selectedTrackIndices.min() {
            editor.selectedTrackID = sketch.tracks[top].id
        }
        selectionBox = nil
        boxBaseSelection = []
    }

    // MARK: 移動・削除

    /// 矢印キー：選んだ音符を全部 ticks だけずらし、semitones 半音だけ上下する。
    func nudgeSelection(ticks: Tick = 0, semitones: Int = 0) {
        moveSelection(by: ticks, pitch: { track in
            self.movesVertically(track) ? { $0 + semitones } : { $0 }
        })
    }

    /// 選んだ音符を消す（跡は空白のまま）。トラックをまたいでいれば、どのトラックからも消す。
    func deleteSelection() {
        let indices = selectedTrackIndices
        guard !isPlaying, !indices.isEmpty else { return }
        recordUndo()
        for index in indices {
            NoteEditing.delete(ids: selectedNoteIDs, in: &sketch.tracks[index])
        }
        lastEntry = nil
        clearNoteSelection()
    }

    // MARK: コピー・切り取り・貼り付け

    /// 選んだ音符をコピーする（トラックをまたいでいれば、トラックごとにまとめて）。
    func copySelection() {
        let indices = selectedTrackIndices
        let notes = selectedNotes
        guard !indices.isEmpty, let origin = notes.map(\.start).min(), let end = notes.map(\.end).max() else { return }
        let melodic = sketch.tracks.indices.filter { !sketch.tracks[$0].isDrums }
        let parts = indices.map { index in
            let track = sketch.tracks[index]
            return NoteClipboard.Part(isDrums: track.isDrums, row: melodic.firstIndex(of: index) ?? 0,
                                      notes: track.notes.filter { selectedNoteIDs.contains($0.id) })
        }
        NoteClipboard.shared.set(NoteClipboard.Content(parts: parts, origin: origin, length: end - origin))
    }

    /// 選んだ音符をコピーして消す。
    func cutSelection() {
        guard hasNoteSelection, !isPlaying else { return }
        copySelection()
        deleteSelection()
    }

    /// 貼り付ける先（トラックの添字と、そこへ貼る音符）。
    /// - ドラム以外の音符：コピーした一番上のトラックの分を選択中のトラックへ、ほかはそこから下へ、コピー元と同じ間隔で
    ///   （ドラムのトラックは数えない。下にはみ出す分は貼らない）
    /// - ドラムの音符：ドラムのトラックへ
    /// - 1本のトラックからのコピーは、選択中のトラックに合うときだけ（ドラムはドラムのトラック、ほかはドラム以外）
    /// - 選択中がドラムのトラックで、ドラム以外の音符も含むときは、ドラム以外はコピー元と同じ並びの位置へ
    private func pasteTargets(_ content: NoteClipboard.Content) -> [(index: Int, part: NoteClipboard.Part)] {
        guard let selected = selectedTrackIndex else { return [] }
        let selectedIsDrums = sketch.tracks[selected].isDrums
        if content.parts.count == 1 {
            let part = content.parts[0]
            return part.isDrums == selectedIsDrums ? [(selected, part)] : []
        }
        let melodic = sketch.tracks.indices.filter { !sketch.tracks[$0].isDrums }
        let drums = sketch.tracks.indices.first { sketch.tracks[$0].isDrums }
        let topRow = content.parts.filter { !$0.isDrums }.map(\.row).min() ?? 0
        let anchor = selectedIsDrums ? topRow : (melodic.firstIndex(of: selected) ?? 0)
        return content.parts.compactMap { part in
            if part.isDrums { return drums.map { ($0, part) } }
            let row = anchor + part.row - topRow
            return melodic.indices.contains(row) ? (melodic[row], part) : nil
        }
    }

    /// 貼れるか（クリップボードに音符があり、貼る先のトラックがある）。
    var canPaste: Bool {
        guard !isPlaying, let content = NoteClipboard.shared.content else { return false }
        return !pasteTargets(content).isEmpty
    }

    /// 編集位置に貼る（一番早い音符を編集位置に合わせ、今ある音符に重ねる）。貼った音符を選び、編集位置を貼った範囲の終わりへ進める。
    func paste() {
        guard !isPlaying, let content = NoteClipboard.shared.content else { return }
        let targets = pasteTargets(content)
        guard !targets.isEmpty else { return }
        let offset = editor.editPosition - content.origin
        var tracks = sketch.tracks
        var pasted = Set<Note.ID>()
        for target in targets {
            pasted.formUnion(NoteEditing.paste(target.part.notes, offset: offset, in: &tracks[target.index],
                                               timeSignature: sketch.timeSignature, totalTicks: sketch.totalTicks))
        }
        guard !pasted.isEmpty, tracks != sketch.tracks else { return }
        recordUndo()
        sketch.tracks = tracks
        noteDrag = nil
        selectionBox = nil
        selectedNoteIDs = pasted
        lastEntry = nil
        setEditPosition(editor.editPosition + content.length)
        revealEditPosition()
    }

    // MARK: 譜面の直接タップ

    /// Mac：ポインタを乗せた所に入る予定の音（半透明の青で出す）。
    struct TapHover: Equatable {
        var trackID: Track.ID
        var tick: Tick
        var pitch: MIDINote
    }
    var tapHover: TapHover?

    /// 譜面タップで置く位置の刻み：16分。3連符がオンなら3連の刻み（3連8分、それより短い音価ならその長さ）。
    var tapGrid: Tick {
        editor.duration.isTriplet
            ? min(editor.duration.ticks, NoteDuration(.eighth, triplet: true).ticks)
            : NoteDuration(.sixteenth).ticks
    }

    /// 五線上の位置の音（調の音階の音。ドラム譜なら、その位置の楽器）。
    func tapPitch(track: Track, staffPosition: Int) -> MIDINote {
        min(max(track.clef.pitch(atStaffPosition: staffPosition, in: sketch.key), 0), 127)
    }

    /// 譜面タップで1音を置く：選択中の音価で、今ある音符に重ねる（同じ高さの音と休符は上書き）。
    /// 置いた音を鳴らして選んだ状態にし、編集位置を置いた音の終わりへ進める。
    func placeNote(track id: Track.ID, at tick: Tick, staffPosition: Int) {
        guard !isPlaying, inputMethod == .scoreTap, let index = sketch.tracks.firstIndex(where: { $0.id == id }) else { return }
        selectTrack(id)
        clearNoteSelection()
        var track = sketch.tracks[index]
        let pitch = tapPitch(track: track, staffPosition: staffPosition)
        let ids = NoteEditing.place(pitch: pitch, at: tick, duration: editor.duration.ticks, tieFromPrevious: editor.isTieOn,
                                    in: &track, timeSignature: sketch.timeSignature, totalTicks: sketch.totalTicks)
        guard !ids.isEmpty else { return }
        recordUndo()
        sketch.tracks[index] = track
        editor.isTieOn = false  // タイは1回使うと戻す
        lastEntry = nil
        tapHover = nil
        editor.previewPitch = nil
        selectedNoteIDs = Set(ids)
        audition(pitch, track: id)
        setEditPosition(track.notes.filter { ids.contains($0.id) }.map(\.end).max() ?? tick)
        revealEditPosition()
    }

    /// ♯・♭ボタンで変えられるか（ドラム以外の音符を選んでいる）。
    var canChangeAccidental: Bool {
        !isPlaying && selectedTrackIndices.contains { !sketch.tracks[$0].isDrums }
            && selectedNotes.contains { $0.pitch != nil }
    }

    /// ♯・♭ボタン：選んだ音を半音上げる／下げる（ドラムは動かさない）。
    func changeAccidental(semitones: Int) {
        guard canChangeAccidental else { return }
        moveSelection(by: 0, pitch: { track in track.isDrums ? { $0 } : { $0 + semitones } })
    }

    /// 上下に動かすトラックか。ドラムは上下に動かすと楽器が変わるので、ほかのトラックと一緒に選んでいるときは横にだけ動かす。
    private func movesVertically(_ track: Track) -> Bool {
        !(track.isDrums && selectedTrackIndices.count > 1)
    }

    /// 五線の段数 steps だけ上下するトラックごとの変換（調の音階の音。ドラムなら楽器の位置）。
    private func staffStepTransform(_ steps: Int) -> (Track) -> (MIDINote) -> MIDINote {
        let key = sketch.key
        return { track in
            let clef = track.clef
            guard steps != 0, self.movesVertically(track) else { return { $0 } }
            return { pitch in clef.pitch(atStaffPosition: clef.staffPosition(ofPitch: pitch, in: key) + steps, in: key) }
        }
    }

    /// 選んだ全部を動かすときの横の移動量。曲の端では、選んだまとまり全体（トラックをまたいでも1つ）で止まる。
    private func clampedShift(_ ticks: Tick) -> Tick {
        let notes = selectedNotes
        guard let groupStart = notes.map(\.start).min(), let groupEnd = notes.map(\.end).max() else { return 0 }
        return min(max(ticks, -groupStart), max(sketch.totalTicks - groupEnd, -groupStart))
    }

    /// ドラッグ中：横は16分単位、縦は五線の1段（調の音階の音）単位で移動先を決め、半透明で出す。
    /// 複数選んでいるときは、全部を同じ量（同じ段数）だけ動かす。トラックをまたいでいれば、各トラックで同じ段数だけ。
    func dragSelection(translation: CGSize) {
        guard !isPlaying, let anchor else { return }
        let layout = layout
        let grid = RulerView.seekGrid
        var ticks: Tick = 0
        if abs(translation.width) >= CGFloat(grid) * layout.pointsPerTick / 2 {
            ticks = layout.tick(atContentX: layout.x(tick: anchor.note.start) + translation.width, grid: grid) - anchor.note.start
        }
        ticks = clampedShift(ticks)
        let steps = Int((-translation.height / (layout.staffSpace / 2)).rounded())
        let transform = staffStepTransform(steps)
        if let anchorTrack = sketch.tracks.first(where: { $0.id == anchor.trackID }),
           let pitch = anchor.note.pitch.map(transform(anchorTrack)), steps != noteDrag?.steps ?? 0, pitch != anchor.note.pitch {
            audition(min(max(pitch, 0), 127), track: anchor.trackID)
        }

        var preview: [Track.ID: [Note]] = [:]
        if ticks != 0 || steps != 0 {
            for index in selectedTrackIndices {
                var copy = sketch.tracks[index]
                let ids = Set(NoteEditing.move(ids: selectedNoteIDs, by: ticks, pitch: transform(copy), in: &copy,
                                               timeSignature: sketch.timeSignature, totalTicks: sketch.totalTicks))
                preview[copy.id] = copy.notes.filter { ids.contains($0.id) }
            }
        }
        noteDrag = NoteDrag(ticks: ticks, steps: steps, preview: preview)
    }

    /// ドラッグを離した：移動先へ動かす。
    func endDragSelection() {
        guard let drag = noteDrag else { return }
        noteDrag = nil
        moveSelection(by: drag.ticks, pitch: staffStepTransform(drag.steps), playsSound: false)
    }

    /// 選んだ音符を、選んだ音符のある全トラックで動かす（取り消しは1回にまとめる）。pitch はトラックごとの音高の変換。
    private func moveSelection(by ticks: Tick, pitch transform: (Track) -> (MIDINote) -> MIDINote, playsSound: Bool = true) {
        guard !isPlaying, let anchor else { return }
        let shift = clampedShift(ticks)
        var moved = sketch.tracks
        var ids = Set<Note.ID>()
        for index in selectedTrackIndices {
            let change = transform(moved[index])
            ids.formUnion(NoteEditing.move(ids: selectedNoteIDs, by: shift, pitch: change, in: &moved[index],
                                           timeSignature: sketch.timeSignature, totalTicks: sketch.totalTicks))
        }
        guard moved != sketch.tracks else { return }
        recordUndo()
        sketch.tracks = moved
        selectedNoteIDs = ids
        lastEntry = nil
        if playsSound, let pitch = anchor.note.pitch, let anchorTrack = sketch.tracks.first(where: { $0.id == anchor.trackID }) {
            let changed = transform(anchorTrack)(pitch)
            if changed != pitch { audition(min(max(changed, 0), 127), track: anchor.trackID) }
        }
    }

    /// トラックの音色で短く鳴らす（音符を選んだとき・上下に動かしたとき）。
    /// track を省くと選択中のトラック。トラックをまたいで選んでいるときは、その音符のトラックの音色で鳴らす。
    private func audition(_ pitch: MIDINote, track: Track.ID? = nil) {
        guard let id = track ?? editor.selectedTrackID else { return }
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
        // トラックの増減や音色が戻るときは、音色を読み込み直す（再生中なら止める）
        let programs = { (sketch: Sketch) in Dictionary(uniqueKeysWithValues: sketch.tracks.map { ($0.id, $0.program) }) }
        if programs(snapshot.sketch) != programs(sketch) {
            stopPlayback()
            sound.prepare(snapshot.sketch.tracks)
        }
        sketch = snapshot.sketch
        if editor.selectedTrackID.map({ id in !sketch.tracks.contains { $0.id == id } }) ?? true {
            editor.selectedTrackID = sketch.tracks.first?.id
        }
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

    // MARK: セクションの操作

    /// 曲の最後に小節を足して新しいセクションにし、その頭へ移る。
    func appendSection() {
        var added: SongSection?
        changeSettings { added = SectionEditing.appendSection(in: &$0) }
        if let added { jump(toBar: added.startBar) }
    }

    /// 編集位置の小節から後ろを新しいセクションに分ける。
    func splitSectionAtEditPosition() {
        let bar = editPositionBar
        guard SectionEditing.canSplit(at: bar, in: sketch) else { return }
        changeSettings { SectionEditing.splitSection(at: bar, in: &$0) }
    }

    var canSplitSectionAtEditPosition: Bool {
        SectionEditing.canSplit(at: editPositionBar, in: sketch)
    }

    func renameSection(_ id: SongSection.ID, to name: String) {
        guard let section = sketch.sections.first(where: { $0.id == id }),
              section.name != name.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        changeSettings(group: "sectionName:\(id)") { SectionEditing.rename(id, to: name, in: &$0) }
    }

    func resizeSection(_ id: SongSection.ID, to barCount: Int) {
        changeSettings(group: "sectionLength:\(id)") { SectionEditing.resize(id, to: barCount, in: &$0) }
    }

    func duplicateSection(_ id: SongSection.ID) {
        changeSettings { SectionEditing.duplicate(id, in: &$0) }
    }

    func mergeSectionWithPrevious(_ id: SongSection.ID) {
        changeSettings { SectionEditing.mergeWithPrevious(id, in: &$0) }
    }

    func deleteSection(_ id: SongSection.ID) {
        changeSettings { SectionEditing.delete(id, in: &$0) }
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
        var changed = sketch
        change(&changed)
        guard changed != sketch else { return }
        clearNoteSelection()
        recordUndo(group: group)
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
        #if DEBUG
        FrameProbe.playheadUpdated()
        #endif
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
        #if DEBUG
        FrameProbe.scrolls += 1
        #endif
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

    // MARK: トラックの操作

    var canAddTrack: Bool { TrackEditing.canAdd(to: sketch) }

    /// 役割のひな形でトラックを足す。below のトラック（省略なら選択中のトラック）のすぐ下に入れ、そのトラックを選ぶ。
    func addTrack(role: TrackRole, below id: Track.ID? = nil) {
        guard canAddTrack else { return }
        let anchor = (id ?? editor.selectedTrackID).flatMap { id in sketch.tracks.firstIndex { $0.id == id } }
        changeTracks {
            guard let track = TrackEditing.addTrack(role: role, at: anchor.map { $0 + 1 }, in: &$0) else { return }
            editor.selectedTrackID = track.id
        }
    }

    func duplicateTrack(_ id: Track.ID) {
        guard canAddTrack else { return }
        changeTracks {
            guard let copy = TrackEditing.duplicateTrack(id, in: &$0) else { return }
            editor.selectedTrackID = copy.id
        }
    }

    /// トラックを消す。選択中のトラックなら、同じ位置（無ければ1つ上）のトラックを選ぶ。
    func removeTrack(_ id: Track.ID) {
        guard sketch.tracks.count > 1, let index = sketch.tracks.firstIndex(where: { $0.id == id }) else { return }
        changeTracks {
            TrackEditing.removeTrack(id, in: &$0)
            if editor.selectedTrackID == id {
                editor.selectedTrackID = $0.tracks[min(index, $0.tracks.count - 1)].id
            }
        }
    }

    /// トラックを並べ替える。destination は動かす前の並びでの挿入位置。
    func moveTrack(_ id: Track.ID, to destination: Int) {
        var moved = sketch
        TrackEditing.moveTrack(id, to: destination, in: &moved)
        guard moved.tracks.map(\.id) != sketch.tracks.map(\.id) else { return }
        recordUndo()
        sketch = moved
    }

    func setTrackName(_ name: String, of id: Track.ID) {
        editTrack(id, group: "name:\(id)") { TrackEditing.setName(name, of: &$0) }
    }

    func setTrackRole(_ role: TrackRole, of id: Track.ID) {
        editTrack(id) { $0.role = role }
    }

    func setTrackClef(_ clef: Clef, of id: Track.ID) {
        editTrack(id) { $0.clef = clef }
    }

    func setTrackColor(_ color: TrackColor, of id: Track.ID) {
        editTrack(id) { $0.color = color }
    }

    /// 音色を変える（名前が音色名のままなら名前も変わる）。再生中なら止めてから読み込み、試しに1音鳴らす。
    func setTrackProgram(_ program: Int, of id: Track.ID) {
        guard let track = sketch.tracks.first(where: { $0.id == id }), track.program != program else { return }
        stopPlayback()
        editTrack(id) { TrackEditing.setProgram(program, of: &$0) }
        sound.prepare(sketch.tracks.filter { $0.id == id })
        let pitch = track.clef == .bass ? 43 : 67  // G2／G4
        sound.noteOn(pitch, track: id)
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            sound.noteOff(pitch, track: id)
        }
    }

    /// トラックの設定を変える（元に戻すで戻せる）。
    private func editTrack(_ id: Track.ID, group: String? = nil, _ change: (inout Track) -> Void) {
        guard let index = sketch.tracks.firstIndex(where: { $0.id == id }) else { return }
        var track = sketch.tracks[index]
        change(&track)
        guard track != sketch.tracks[index] else { return }
        recordUndo(group: group)
        sketch.tracks[index] = track
    }

    /// トラックを足す・消す変更。新しいトラックの音色を読み込むので、再生中なら止める。
    private func changeTracks(_ change: (inout Sketch) -> Void) {
        stopPlayback()
        clearNoteSelection()
        recordUndo()
        var changed = sketch
        change(&changed)
        sketch = changed
        pendingEntry = nil
        lastEntry = nil
        sound.prepare(sketch.tracks)
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
