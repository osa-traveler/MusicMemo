#if DEBUG
import Foundation
import MusicMemoCore
import OSLog

/// 開発用：環境変数 MUSICMEMO_INPUT_DEMO=1 で起動すると、決まった入力操作を流す（撮影で入力の流れを確かめる）。
/// MUSICMEMO_INPUT_DEMO=2 なら、続けて音符の選択・移動・削除・範囲選択を流し、最後は複数の音のドラッグの途中で止める。
/// MUSICMEMO_INPUT_DEMO=3 なら、範囲選択の箱を出したところで止める。
/// MUSICMEMO_INPUT_DEMO=4 なら、10小節目に全音符の C E G を入れ、G だけを3拍目へ動かす（重なる音が和音になるか）。
/// MUSICMEMO_INPUT_DEMO=5 なら、上の3トラックの6〜7小節を箱で囲み（トラックをまたぐ範囲選択）、1拍右・半音上へ動かし、
/// 元に戻す1回で全トラックが戻るかをログに出す。最後はドラッグの途中で止める。
/// MUSICMEMO_INPUT_DEMO=6 なら、コピー・貼り付け・切り取り（1トラック、続けて貼る、元に戻す、トラックをまたぐ）を流してログに出す。
/// MUSICMEMO_INPUT_DEMO=7 なら、譜面の直接タップ（和音、♯、3連符、小節線をまたぐ音、元に戻す）を流してログに出し、
/// 最後は Mac のポインタを乗せたときの入る予定の音を出したところで止める。
enum DebugInputDemo {
    @MainActor
    static func runIfRequested(_ store: SketchStore) {
        let mode = ProcessInfo.processInfo.environment["MUSICMEMO_INPUT_DEMO"]
        guard let mode, ["1", "2", "3", "4", "5", "6", "7"].contains(mode) else { return }
        if mode == "7" {
            runScoreTapDemo(store)
            return
        }
        if mode == "6" {
            runCopyPasteDemo(store)
            return
        }
        if mode == "5" {
            runMultiTrackDemo(store)
            return
        }
        if mode == "4" {
            runChordToneMoveDemo(store)
            return
        }
        // 7小節目：F4（4分）→ G4+B4 の和音（4分）→ 4分休符
        store.keyDown(65); store.keyUp(65)
        store.keyDown(67); store.keyDown(71); store.keyUp(67); store.keyUp(71)
        store.enterRest()
        // 8分で A4、⇧クリックで C5 を重ねる、続けて B4
        store.selectNoteValue(.eighth)
        store.keyDown(69); store.keyUp(69)
        store.keyDown(72, addToChord: true); store.keyUp(72)
        store.keyDown(71); store.keyUp(71)
        // タイをつけて B4 の2分音符（小節線をまたぐので分割してタイ）
        store.selectNoteValue(.half)
        store.toggleTie()
        store.keyDown(71); store.keyUp(71)
        // 2分で D5 を入れてから、戻って消す
        store.keyDown(74); store.keyUp(74)
        store.backspace()
        // 8.3：16分×2＋8分（連桁）、9小節目：3連8分×3、8分＋16分×2
        store.selectNoteValue(.sixteenth)
        for pitch in [72, 74] { store.keyDown(pitch); store.keyUp(pitch) }
        store.selectNoteValue(.eighth)
        store.keyDown(76); store.keyUp(76)
        store.toggleTriplet()
        for pitch in [77, 76, 74] { store.keyDown(pitch); store.keyUp(pitch) }
        store.toggleTriplet()
        store.keyDown(72); store.keyUp(72)
        store.selectNoteValue(.sixteenth)
        for pitch in [71, 69] { store.keyDown(pitch); store.keyUp(pitch) }
        if mode != "1" { runSelectionDemo(store, stopsAtBox: mode == "3") }
    }

    /// 音符の選択・移動・削除。当たり判定は、描くときと同じ座標（行の高さは最小値）で符頭の位置を指して確かめる。
    @MainActor
    private static func runSelectionDemo(_ store: SketchStore, stopsAtBox: Bool) {
        let log = Logger(subsystem: "MusicMemo", category: "SelectDemo")
        guard let trackID = store.editor.selectedTrackID else { return }
        let layout = store.layout
        let rowHeight = layout.minimumRowHeight
        let bar7 = store.sketch.timeSignature.startTick(ofBar: 7)

        func describe(_ notes: [Note]) -> String {
            notes.map { "\($0.start - bar7):\($0.pitch.map { Pitch.noteName($0) } ?? "rest")/\($0.duration)\($0.tiesToNext ? "~" : "")" }
                .joined(separator: " ")
        }
        func bar7Notes() -> String {
            describe(store.selectedTrack?.notes.filter { $0.start >= bar7 && $0.start < bar7 + 1920 * 2 } ?? [])
        }
        /// 符頭の位置を指して選ぶ。
        func click(tick: Tick, pitch: MIDINote?) {
            guard let track = store.selectedTrack else { return }
            let bottom = layout.bottomLineY(rowHeight: rowHeight)
            let position = pitch.map { track.clef.staffPosition(of: SpelledPitch($0, in: store.sketch.key)) } ?? Notation.middleLine
            // 符頭の中心から少し外した位置（当たり判定の余裕も確かめる）
            let point = CGPoint(x: layout.x(tick: tick) + 0.3 * layout.staffSpace,
                                y: layout.y(staffPosition: position, bottomLineY: bottom) + 0.2 * layout.staffSpace)
            guard let id = StaffRowView.hitNote(at: point, track: track, sketch: store.sketch, layout: layout, rowHeight: rowHeight) else {
                log.error("hit failed tick=\(tick - bar7) pitch=\(pitch ?? -1)")
                return
            }
            store.selectNote(id, track: trackID)
            log.notice("selected \(describe(store.selectedNotes), privacy: .public)")
        }

        log.notice("before   \(bar7Notes(), privacy: .public)")
        // F4 を選んで 全音上げ（G4）、オクターブ上げてから戻す
        click(tick: bar7, pitch: 65)
        store.nudgeSelection(semitones: 2)
        store.nudgeSelection(semitones: 12)
        store.nudgeSelection(semitones: -12)
        log.notice("moved    \(bar7Notes(), privacy: .public)")
        // 和音の B4 だけを消す
        click(tick: bar7 + 480, pitch: 71)
        store.deleteKey()
        log.notice("deleted  \(bar7Notes(), privacy: .public)")
        // 休符を選んで消す
        click(tick: bar7 + 960, pitch: nil)
        store.deleteKey()
        log.notice("rest del \(bar7Notes(), privacy: .public)")
        // 和音に残った G4 を、空いた3拍目へ（16分×4 右へ）
        click(tick: bar7 + 480, pitch: 67)
        for _ in 0..<4 { store.nudgeSelection(ticks: 120) }
        log.notice("shifted  \(bar7Notes(), privacy: .public)")
        // 範囲選択：3拍目〜4拍目の裏（G4、A4+C5 の和音、タイでつながった B4）を箱で囲む
        store.scroll(toLeadingBar: 7)
        if let track = store.selectedTrack {
            let rect = CGRect(x: layout.x(tick: bar7 + 900), y: 0, width: layout.x(tick: bar7 + 1700) - layout.x(tick: bar7 + 900),
                              height: rowHeight)
            store.beginBoxSelection(track: trackID, adding: false)
            store.updateBoxSelection(rect: rect, hits: StaffRowView.notes(in: rect, track: track, sketch: store.sketch,
                                                                         layout: layout, rowHeight: rowHeight))
        }
        log.notice("box      \(describe(store.selectedNotes), privacy: .public)")
        if stopsAtBox { return }
        store.endBoxSelection()
        // まとめて4分左へ、半音上げてから戻す
        store.nudgeSelection(ticks: -480)
        log.notice("group <- \(bar7Notes(), privacy: .public)")
        store.nudgeSelection(semitones: 1)
        log.notice("group +1 \(bar7Notes(), privacy: .public)")
        store.nudgeSelection(ticks: 480, semitones: -1)
        log.notice("group -> \(bar7Notes(), privacy: .public)")
        // ドラッグの途中（右へ1拍、上へ1段）で止めて撮影
        store.dragSelection(translation: CGSize(width: 48 * layout.zoom, height: -layout.staffSpace / 2))
        log.notice("dragging preview \(describe(store.noteDrag?.preview.values.flatMap { $0 } ?? []), privacy: .public)")
    }

    /// トラックをまたぐ範囲選択（箱の座標は全トラックの行を並べたもの。行の高さは最小値）。
    @MainActor
    private static func runMultiTrackDemo(_ store: SketchStore) {
        let log = Logger(subsystem: "MusicMemo", category: "SelectDemo")
        let layout = store.layout
        let rowHeight = layout.minimumRowHeight
        let time = store.sketch.timeSignature
        let start = time.startTick(ofBar: 6), end = time.startTick(ofBar: 8)
        func summary() -> String {
            store.sketch.tracks.prefix(4).map { track in
                let notes = track.notes.filter { $0.start >= start - 480 && $0.start < end + 480 && $0.pitch != nil }
                return "\(track.name)[" + notes.map { "\($0.start - start):\(Pitch.noteName($0.pitch!))" }.joined(separator: " ") + "]"
            }.joined(separator: " ")
        }
        guard store.sketch.tracks.count >= 3 else { return }
        log.notice("multi before \(summary(), privacy: .public)")
        store.scroll(toLeadingBar: 5)
        // 1本目の行の上端から3本目の行の下端まで、6小節目の頭〜7小節目の終わりの少し手前
        let rect = CGRect(x: layout.x(tick: start) - 4, y: 0, width: layout.x(tick: end - 60) - layout.x(tick: start) + 4,
                          height: rowHeight * 3)
        store.beginBoxSelection(track: store.sketch.tracks[0].id, adding: false)
        var hits: [Note.ID] = []
        for index in 0..<3 {
            let slice = CGRect(x: rect.minX, y: 0, width: rect.width, height: rowHeight)
            hits += StaffRowView.notes(in: slice, track: store.sketch.tracks[index], sketch: store.sketch, layout: layout, rowHeight: rowHeight)
        }
        store.updateBoxSelection(rect: rect, hits: hits)
        store.endBoxSelection()
        let byTrack = store.sketch.tracks.map { track in track.notes.filter { store.selectedNoteIDs.contains($0.id) }.count }
        log.notice("multi selected \(store.selectedNotes.count) notes per track \(byTrack.map(String.init).joined(separator: ","), privacy: .public)")
        store.nudgeSelection(ticks: 480)
        log.notice("multi -> beat \(summary(), privacy: .public)")
        store.nudgeSelection(semitones: 1)
        log.notice("multi +1 \(summary(), privacy: .public)")
        store.undo()
        log.notice("multi undo1 \(summary(), privacy: .public)")
        store.undo()
        log.notice("multi undo2 \(summary(), privacy: .public)")
        // もう一度囲んで、ドラッグの途中（右へ1拍、上へ1段）で止めて撮影
        store.beginBoxSelection(track: store.sketch.tracks[0].id, adding: false)
        store.updateBoxSelection(rect: rect, hits: hits)
        store.endBoxSelection()
        store.dragSelection(translation: CGSize(width: layout.x(tick: start + 480) - layout.x(tick: start), height: -layout.staffSpace / 2))
        let previewCounts = store.sketch.tracks.map { store.noteDrag?.preview[$0.id]?.count ?? 0 }
        log.notice("multi dragging preview per track \(previewCounts.map(String.init).joined(separator: ","), privacy: .public)")
    }

    /// コピー・貼り付け・切り取り。選択は箱と同じ当たり判定（行の高さは最小値）で作る。
    @MainActor
    private static func runCopyPasteDemo(_ store: SketchStore) {
        let log = Logger(subsystem: "MusicMemo", category: "SelectDemo")
        let layout = store.layout
        let rowHeight = layout.minimumRowHeight
        let time = store.sketch.timeSignature
        func bars(_ first: Int, _ last: Int) -> String {
            let start = time.startTick(ofBar: first), end = time.startTick(ofBar: last + 1)
            return store.sketch.tracks.prefix(3).map { track in
                let notes = track.notes.filter { $0.start >= start && $0.start < end && $0.pitch != nil }
                return "\(track.name)[" + notes.map { "\(time.position(of: $0.start).barBeatDescription):\(Pitch.noteName($0.pitch!))" }.joined(separator: " ") + "]"
            }.joined(separator: " ")
        }
        func select(tracks: Range<Int>, fromBar first: Int, throughBar last: Int) {
            let start = time.startTick(ofBar: first), end = time.startTick(ofBar: last + 1)
            let rect = CGRect(x: layout.x(tick: start) - 4, y: 0, width: layout.x(tick: end - 60) - layout.x(tick: start) + 4, height: rowHeight)
            store.beginBoxSelection(track: store.sketch.tracks[tracks.lowerBound].id, adding: false)
            var hits: [Note.ID] = []
            for index in tracks {
                hits += StaffRowView.notes(in: rect, track: store.sketch.tracks[index], sketch: store.sketch, layout: layout, rowHeight: rowHeight)
            }
            store.updateBoxSelection(rect: rect, hits: hits)
            store.endBoxSelection()
        }
        guard store.sketch.tracks.count >= 3 else { return }
        store.scroll(toLeadingBar: 5)
        // 1トラック：Piano の6小節目をコピーして、12小節目に2回続けて貼る
        select(tracks: 0..<1, fromBar: 6, throughBar: 6)
        log.notice("copy source \(bars(6, 6), privacy: .public) selected \(store.selectedNotes.count)")
        store.copySelection()
        store.setEditPosition(time.startTick(ofBar: 12))
        store.paste()
        store.paste()
        log.notice("paste x2 \(bars(12, 14), privacy: .public) edit \(time.position(of: store.editor.editPosition).description, privacy: .public) selected \(store.selectedNotes.count)")
        store.undo()
        log.notice("paste undo \(bars(12, 14), privacy: .public)")
        // トラックをまたぐ：上3トラックの6小節目をコピーして、13小節目へ
        select(tracks: 0..<3, fromBar: 6, throughBar: 6)
        store.copySelection()
        store.setEditPosition(time.startTick(ofBar: 13))
        store.paste()
        log.notice("multi paste \(bars(13, 13), privacy: .public)")
        // 同じコピーを、2本目のトラックを選んでから14小節目へ（2本目から下へ貼る。はみ出す分は貼らない）
        store.selectTrack(store.sketch.tracks[1].id)
        store.setEditPosition(time.startTick(ofBar: 14))
        store.paste()
        log.notice("multi paste to track2 \(bars(14, 14), privacy: .public) \(store.sketch.tracks.count > 3 ? store.sketch.tracks[3].name : "-", privacy: .public)[\(store.sketch.tracks.count > 3 ? store.sketch.tracks[3].notes.filter { $0.start >= time.startTick(ofBar: 14) && $0.start < time.startTick(ofBar: 15) && $0.pitch != nil }.count : 0)]")
        // 切り取り：Piano の12小節目
        select(tracks: 0..<1, fromBar: 12, throughBar: 12)
        store.cutSelection()
        log.notice("cut \(bars(12, 12), privacy: .public) canPaste \(store.canPaste)")
        store.scroll(toLeadingBar: 11)
    }

    /// 譜面の直接タップ。位置と五線上の位置を直接渡す（画面の座標からの変換と、符頭の当たり判定は撮影で確かめる）。
    @MainActor
    private static func runScoreTapDemo(_ store: SketchStore) {
        let log = Logger(subsystem: "MusicMemo", category: "SelectDemo")
        guard let trackID = store.editor.selectedTrackID else { return }
        let time = store.sketch.timeSignature
        let bar10 = time.startTick(ofBar: 10)
        func bars() -> String {
            let notes = store.selectedTrack?.notes.filter { $0.start >= bar10 && $0.start < bar10 + 2 * time.ticksPerBar } ?? []
            return notes.map { "\(time.position(of: $0.start).barBeatDescription)+\($0.start % 480 == 0 ? "" : "\($0.start % 480)"):\($0.pitch.map { Pitch.noteName($0) } ?? "rest")/\($0.duration)\($0.tiesToNext ? "~" : "")" }
                .joined(separator: " ")
        }
        store.setInputMethod(.scoreTap)
        store.selectNoteValue(.quarter)
        // 1拍目：G4（第2線）、続けて同じ位置に B4・D5 → 和音
        for position in [2, 4, 6] {
            store.placeNote(track: trackID, at: bar10, staffPosition: position)
        }
        log.notice("tap chord \(bars(), privacy: .public) edit \(time.position(of: store.editor.editPosition).description, privacy: .public)")
        // 2拍目：A4 を置いて ♯
        store.placeNote(track: trackID, at: bar10 + 480, staffPosition: 3)
        store.changeAccidental(semitones: 1)
        log.notice("tap sharp \(bars(), privacy: .public) selected \(store.selectedNotes.count)")
        // 3拍目：3連8分を3つ
        store.selectNoteValue(.eighth)
        store.toggleTriplet()
        let triplet = store.tapGrid
        for (offset, position) in [(0, 5), (1, 4), (2, 3)] {
            store.placeNote(track: trackID, at: bar10 + 960 + offset * triplet, staffPosition: position)
        }
        store.toggleTriplet()
        // 4拍目から2分の C5（小節線をまたぐ → 4分＋タイ＋4分）、続けて元に戻す1回
        store.selectNoteValue(.half)
        store.placeNote(track: trackID, at: bar10 + 1440, staffPosition: 5)
        log.notice("tap triplet+tie \(bars(), privacy: .public) edit \(time.position(of: store.editor.editPosition).description, privacy: .public)")
        store.undo()
        log.notice("tap undo \(bars(), privacy: .public)")
        store.redo()
        // ポインタを乗せたときの入る予定の音（11小節目の3拍目、F4）
        store.clearNoteSelection()
        store.selectNoteValue(.quarter)
        if let track = store.selectedTrack {
            store.tapHover = .init(trackID: trackID, tick: time.startTick(ofBar: 11) + 960, pitch: store.tapPitch(track: track, staffPosition: 1))
        }
        store.scroll(toLeadingBar: 10)
    }

    @MainActor
    private static func runChordToneMoveDemo(_ store: SketchStore) {
        let log = Logger(subsystem: "MusicMemo", category: "SelectDemo")
        guard let trackID = store.editor.selectedTrackID else { return }
        let bar10 = store.sketch.timeSignature.startTick(ofBar: 10)
        store.setEditPosition(bar10)
        store.selectNoteValue(.whole)
        for pitch in [60, 64, 67] { store.keyDown(pitch) }
        for pitch in [60, 64, 67] { store.keyUp(pitch) }
        let layout = store.layout
        let rowHeight = layout.minimumRowHeight
        guard let track = store.selectedTrack else { return }
        let point = CGPoint(x: layout.x(tick: bar10),
                            y: layout.y(staffPosition: track.clef.staffPosition(of: SpelledPitch(67, in: store.sketch.key)),
                                        bottomLineY: layout.bottomLineY(rowHeight: rowHeight)))
        if let id = StaffRowView.hitNote(at: point, track: track, sketch: store.sketch, layout: layout, rowHeight: rowHeight) {
            store.selectNote(id, track: trackID)
        }
        for _ in 0..<8 { store.nudgeSelection(ticks: RulerView.seekGrid) }
        let notes = store.selectedTrack?.notes.filter { $0.start >= bar10 && $0.start < bar10 + 1920 * 2 } ?? []
        log.notice("chord tone move \(notes.map { "\($0.start - bar10):\(Pitch.noteName($0.pitch ?? 0))/\($0.duration)\($0.tiesToNext ? "~" : "")" }.joined(separator: " "), privacy: .public)")
        // 12小節目：全音符 E と同じ位置の4分 F（2度でぶつかる → 下の声部を右へ）、続けて8分 A G（上の声部で連桁）
        let bar12 = store.sketch.timeSignature.startTick(ofBar: 12)
        if let index = store.sketch.tracks.firstIndex(where: { $0.id == trackID }) {
            store.sketch.tracks[index].notes += [
                Note(start: bar12, duration: 1920, pitch: 64), Note(start: bar12, duration: 480, pitch: 65),
                Note(start: bar12 + 480, duration: 240, pitch: 69), Note(start: bar12 + 720, duration: 240, pitch: 67),
            ]
        }
        store.scroll(toLeadingBar: 10)
    }
}
#endif
