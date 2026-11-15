import Testing
@testable import MusicMemoCore

struct NoteEditingTests {
    let time = TimeSignature.common
    let total = 1920 * 4

    func emptyTrack() -> Track {
        Track(name: "T", role: .melody, color: .blue)
    }

    @Test func entersAndReturnsRange() {
        var track = emptyTrack()
        let range = NoteEditing.enter(pitches: [64], at: 0, duration: 480, in: &track, timeSignature: time, totalTicks: total)
        #expect(range == 0..<480)
        #expect(track.notes.map(\.pitch) == [64])
    }

    @Test func overwritesOverlappingNotes() {
        var track = emptyTrack()
        track.notes = [
            Note(start: 0, duration: 960, pitch: 60),    // 途中から上書きされる → 切り詰め
            Note(start: 960, duration: 480, pitch: 62),  // 範囲内 → 消える
            Note(start: 1440, duration: 480, pitch: 64), // 範囲外 → 残る
        ]
        NoteEditing.enter(pitches: [67], at: 480, duration: 960, in: &track, timeSignature: time, totalTicks: total)
        #expect(track.notes.map { [$0.start, $0.duration, $0.pitch!] } == [[0, 480, 60], [480, 960, 67], [1440, 480, 64]])
    }

    @Test func splitsAtBarLineWithTie() {
        var track = emptyTrack()
        // 4拍目から2分音符 → 4分＋（次の小節）4分、タイでつなぐ
        NoteEditing.enter(pitches: [65], at: 1440, duration: 960, in: &track, timeSignature: time, totalTicks: total)
        #expect(track.notes.map { [$0.start, $0.duration] } == [[1440, 480], [1920, 480]])
        #expect(track.notes.map(\.tiesToNext) == [true, false])
    }

    @Test func splitsUnwritableLength() {
        // 4分＋16分（600）は1つの記号で書けない → 4分＋16分にタイ
        #expect(NoteEditing.split(0..<600, timeSignature: time) == [0..<480, 480..<600])
        // 付点4分は1つで書ける
        #expect(NoteEditing.split(0..<720, timeSignature: time) == [0..<720])
    }

    @Test func restsAreNotTied() {
        var track = emptyTrack()
        NoteEditing.enter(pitches: [], at: 1440, duration: 960, in: &track, timeSignature: time, totalTicks: total)
        let allRests = track.notes.allSatisfy(\.isRest)
        let anyTied = track.notes.contains(where: \.tiesToNext)
        #expect(allRests)
        #expect(!anyTied)
        #expect(track.notes.count == 2)
    }

    @Test func clipsAtSongEnd() {
        var track = emptyTrack()
        let range = NoteEditing.enter(pitches: [60], at: total - 480, duration: 1920, in: &track, timeSignature: time, totalTicks: total)
        #expect(range == (total - 480)..<total)
    }

    @Test func tieFromPrevious() {
        var track = emptyTrack()
        NoteEditing.enter(pitches: [60], at: 0, duration: 480, in: &track, timeSignature: time, totalTicks: total)
        NoteEditing.enter(pitches: [60], at: 480, duration: 480, tieFromPrevious: true, in: &track, timeSignature: time, totalTicks: total)
        #expect(track.notes.map(\.tiesToNext) == [true, false])
        // 音高が違えばタイはつけない
        NoteEditing.enter(pitches: [62], at: 960, duration: 480, tieFromPrevious: true, in: &track, timeSignature: time, totalTicks: total)
        #expect(track.notes.map(\.tiesToNext) == [true, false, false])
    }

    @Test func addToChord() {
        var track = emptyTrack()
        let range = NoteEditing.enter(pitches: [60], at: 0, duration: 480, in: &track, timeSignature: time, totalTicks: total)
        NoteEditing.addToChord(pitch: 64, range: range, in: &track, timeSignature: time)
        NoteEditing.addToChord(pitch: 64, range: range, in: &track, timeSignature: time)  // 重複は足さない
        #expect(track.notes.map(\.pitch) == [60, 64])
    }

    @Test func addToChordReplacesRest() {
        var track = emptyTrack()
        let range = NoteEditing.enter(pitches: [], at: 0, duration: 480, in: &track, timeSignature: time, totalTicks: total)
        NoteEditing.addToChord(pitch: 64, range: range, in: &track, timeSignature: time)
        #expect(track.notes.map(\.pitch) == [64])
    }

    @Test func deleteBefore() {
        var track = emptyTrack()
        NoteEditing.enter(pitches: [60], at: 0, duration: 480, in: &track, timeSignature: time, totalTicks: total)
        NoteEditing.enter(pitches: [60, 64], at: 480, duration: 480, tieFromPrevious: true, in: &track, timeSignature: time, totalTicks: total)
        let newPosition = NoteEditing.deleteBefore(960, in: &track)
        #expect(newPosition == 480)
        #expect(track.notes.map(\.pitch) == [60])
        #expect(track.notes[0].tiesToNext == false)  // 消した音へのタイは外れる
        #expect(NoteEditing.deleteBefore(0, in: &track) == nil)
    }

    // MARK: 選んだ音の移動・削除

    @Test func tiedChainFollowsTiesBothWays() {
        var track = emptyTrack()
        // 4拍目から2分音符（小節線で分かれてタイ）と、その前の別の音
        NoteEditing.enter(pitches: [60], at: 960, duration: 480, in: &track, timeSignature: time, totalTicks: total)
        NoteEditing.enter(pitches: [65], at: 1440, duration: 960, in: &track, timeSignature: time, totalTicks: total)
        let second = track.notes.first { $0.start == 1920 }!
        let chain = NoteEditing.tiedChain(containing: second.id, in: track.notes)
        #expect(chain.map(\.start) == [1440, 1920])
        let rest = Note.rest(start: 0, duration: 480)
        #expect(NoteEditing.tiedChain(containing: rest.id, in: [rest]).count == 1)
    }

    @Test func deleteRemovesTiesIntoDeletedNote() {
        var track = emptyTrack()
        track.notes = [
            Note(start: 0, duration: 480, pitch: 60, tiesToNext: true),
            Note(start: 480, duration: 480, pitch: 60),
            Note(start: 960, duration: 480, pitch: 62),
        ]
        NoteEditing.delete(ids: [track.notes[1].id], in: &track)
        #expect(track.notes.map(\.start) == [0, 960])
        #expect(track.notes[0].tiesToNext == false)
    }

    @Test func moveChangesPitchAndPosition() {
        var track = emptyTrack()
        track.notes = [Note(start: 0, duration: 480, pitch: 60), Note(start: 960, duration: 480, pitch: 64)]
        let ids = NoteEditing.move(ids: [track.notes[0].id], by: 480, to: 62, in: &track, timeSignature: time, totalTicks: total)
        #expect(track.notes.map { [$0.start, $0.pitch!] } == [[480, 62], [960, 64]])
        #expect(ids == [track.notes[0].id])
    }

    @Test func moveIntoLongerNoteLayersWithoutCutting() {
        var track = emptyTrack()
        track.notes = [Note(start: 0, duration: 480, pitch: 60), Note(start: 480, duration: 960, pitch: 64)]
        // 64 の途中（960）へ 60 を動かす → 64 はそのまま、60 が重なる（2つの声部）
        NoteEditing.move(ids: [track.notes[0].id], by: 960, to: 60, in: &track, timeSignature: time, totalTicks: total)
        #expect(track.notes.map { [$0.start, $0.duration, $0.pitch!] } == [[480, 960, 64], [960, 480, 60]])
        #expect(track.notes.allSatisfy { !$0.tiesToNext })
    }

    @Test func movingChordToneOfWholeNotesKeepsOthersSounding() {
        var track = emptyTrack()
        // 小節頭の C E G（全音符）から G だけを3拍目へ → C E は全音符のまま、G は2分＋（次の小節）2分のタイ
        track.notes = [60, 64, 67].map { Note(start: 0, duration: 1920, pitch: $0) }
        NoteEditing.move(ids: [track.notes[2].id], by: 960, to: 67, in: &track, timeSignature: time, totalTicks: total)
        #expect(track.notes.map { [$0.start, $0.duration, $0.pitch!] } == [[0, 1920, 60], [0, 1920, 64], [960, 960, 67], [1920, 960, 67]])
        #expect(track.notes.map(\.tiesToNext) == [false, false, true, false])
    }

    @Test func movingShortNoteIntoWholeNoteKeepsWholeNote() {
        var track = emptyTrack()
        track.notes = [Note(start: 0, duration: 1920, pitch: 60), Note(start: 1920, duration: 240, pitch: 62)]
        // 2小節目の8分 D を 1小節目の2拍目へ → C は全音符のまま
        NoteEditing.move(ids: [track.notes[1].id], by: -1440, to: 62, in: &track, timeSignature: time, totalTicks: total)
        #expect(track.notes.map { [$0.start, $0.duration, $0.pitch!] } == [[0, 1920, 60], [480, 240, 62]])
    }

    @Test func fallsBackToChordWhenThreeLayersOverlap() {
        var track = emptyTrack()
        // C 全音符と E 2分（3拍目から）がすでに2つの声部。そこへ G を 3.3 に動かすと3つ目になる → 境目で分けて和音に
        track.notes = [Note(start: 0, duration: 1920, pitch: 60), Note(start: 960, duration: 960, pitch: 64),
                       Note(start: 1920, duration: 240, pitch: 67)]
        NoteEditing.move(ids: [track.notes[2].id], by: -720, to: 67, in: &track, timeSignature: time, totalTicks: total)
        #expect(!Notation.assignVoices(track.notes).overflows)
        #expect(track.notes.filter { $0.pitch == 67 }.map { [$0.start, $0.duration] } == [[1200, 240]])
        #expect(track.notes.filter { $0.pitch == 60 }.map(\.start) == [0, 960, 1200, 1440])
    }

    @Test func moveOverwritesSamePitchAndRests() {
        var track = emptyTrack()
        track.notes = [
            Note(start: 0, duration: 480, pitch: 60),
            Note(start: 960, duration: 960, pitch: 60),   // 同じ高さ → 切り詰め
            Note.rest(start: 1920, duration: 960),        // 休符 → 切り詰め
        ]
        NoteEditing.move(ids: [track.notes[0].id], by: 1200, to: 60, in: &track, timeSignature: time, totalTicks: total)
        #expect(track.notes.map { [$0.start, $0.duration, $0.pitch ?? -1] } == [[960, 240, 60], [1200, 480, 60], [1920, 960, -1]])
        NoteEditing.move(ids: [track.notes[1].id], by: 960, to: 60, in: &track, timeSignature: time, totalTicks: total)
        #expect(track.notes.map { [$0.start, $0.duration, $0.pitch ?? -1] } == [[960, 240, 60], [1920, 240, -1], [2160, 480, 60]])
    }

    @Test func moveIntoSameLengthNoteMakesChord() {
        var track = emptyTrack()
        track.notes = [Note(start: 0, duration: 480, pitch: 60), Note(start: 480, duration: 480, pitch: 64)]
        NoteEditing.move(ids: [track.notes[0].id], by: 480, to: 67, in: &track, timeSignature: time, totalTicks: total)
        #expect(track.notes.map { [$0.start, $0.pitch!] } == [[480, 64], [480, 67]])
    }

    @Test func movingChordToneKeepsOtherTones() {
        var track = emptyTrack()
        track.notes = [Note(start: 0, duration: 480, pitch: 60), Note(start: 0, duration: 480, pitch: 64)]
        NoteEditing.move(ids: [track.notes[1].id], by: 0, to: 65, in: &track, timeSignature: time, totalTicks: total)
        #expect(track.notes.map { [$0.start, $0.pitch!] } == [[0, 60], [0, 65]])
    }

    @Test func moveTiedChainResplitsAtBarLine() {
        var track = emptyTrack()
        // 4拍目からの2分音符（4分＋4分のタイ）を、4分だけ前へ → 3拍目からの2分音符（1つに戻る）
        NoteEditing.enter(pitches: [65], at: 1440, duration: 960, in: &track, timeSignature: time, totalTicks: total)
        let ids = Set(track.notes.map(\.id))
        let moved = NoteEditing.move(ids: ids, by: -480, to: 65, in: &track, timeSignature: time, totalTicks: total)
        #expect(track.notes.map { [$0.start, $0.duration] } == [[960, 960]])
        #expect(moved.count == 1)
        // 8分後ろへ → 3.3 から 4分＋付点4分？ではなく、小節線で分けて 1680–1920 と 1920–2640
        NoteEditing.move(ids: Set(moved), by: 720, to: 65, in: &track, timeSignature: time, totalTicks: total)
        #expect(track.notes.map { [$0.start, $0.duration] } == [[1680, 240], [1920, 720]])
        #expect(track.notes.map(\.tiesToNext) == [true, false])
    }

    @Test func moveDropsTiesToNeighbours() {
        var track = emptyTrack()
        track.notes = [
            Note(start: 0, duration: 480, pitch: 60, tiesToNext: true),
            Note(start: 480, duration: 480, pitch: 60),
        ]
        NoteEditing.move(ids: [track.notes[1].id], by: 0, to: 62, in: &track, timeSignature: time, totalTicks: total)
        #expect(track.notes[0].tiesToNext == false)
        #expect(track.notes[1].pitch == 62)
    }

    @Test func moveStaysInsideSong() {
        var track = emptyTrack()
        track.notes = [Note(start: 480, duration: 480, pitch: 60)]
        NoteEditing.move(ids: [track.notes[0].id], by: -9999, to: 60, in: &track, timeSignature: time, totalTicks: total)
        #expect(track.notes[0].start == 0)
        NoteEditing.move(ids: [track.notes[0].id], by: 99999, to: 60, in: &track, timeSignature: time, totalTicks: total)
        #expect(track.notes[0].start == total - 480)
    }

    @Test func moveRestIgnoresPitch() {
        var track = emptyTrack()
        track.notes = [Note.rest(start: 0, duration: 480)]
        NoteEditing.move(ids: [track.notes[0].id], by: 480, to: 70, in: &track, timeSignature: time, totalTicks: total)
        #expect(track.notes.count == 1)
        #expect(track.notes[0].isRest && track.notes[0].start == 480)
    }

    // MARK: 複数の音をまとめて動かす

    @Test func moveGroupKeepsShape() {
        var track = emptyTrack()
        track.notes = [
            Note(start: 0, duration: 480, pitch: 60), Note(start: 0, duration: 480, pitch: 64),
            Note(start: 480, duration: 480, pitch: 67),
            Note(start: 1440, duration: 480, pitch: 72),  // 選ばない
        ]
        let ids = Set(track.notes.prefix(3).map(\.id))
        let moved = NoteEditing.move(ids: ids, by: 480, pitch: { $0 + 2 }, in: &track, timeSignature: time, totalTicks: total)
        #expect(moved.count == 3)
        #expect(track.notes.map { [$0.start, $0.pitch!] } == [[480, 62], [480, 66], [960, 69], [1440, 72]])
    }

    @Test func groupMembersDoNotOverwriteEachOther() {
        var track = emptyTrack()
        // 隣り合う4分音符2つを4分右へ → 1つ目が2つ目の元の位置へ入るが、消し合わない
        track.notes = [Note(start: 0, duration: 480, pitch: 60), Note(start: 480, duration: 480, pitch: 62)]
        NoteEditing.move(ids: Set(track.notes.map(\.id)), by: 480, pitch: { $0 }, in: &track, timeSignature: time, totalTicks: total)
        #expect(track.notes.map { [$0.start, $0.pitch!] } == [[480, 60], [960, 62]])
    }

    @Test func groupJoinsUnselectedNotes() {
        var track = emptyTrack()
        track.notes = [
            Note(start: 0, duration: 480, pitch: 60), Note(start: 480, duration: 480, pitch: 62),
            Note(start: 960, duration: 960, pitch: 64),  // 選ばない：途中から重なる → 境目で分けて和音に
        ]
        NoteEditing.move(ids: Set(track.notes.prefix(2).map(\.id)), by: 1200, pitch: { $0 }, in: &track,
                         timeSignature: time, totalTicks: total)
        #expect(track.notes.map { [$0.start, $0.duration, $0.pitch!] } == [[960, 960, 64], [1200, 480, 60], [1680, 240, 62], [1920, 240, 62]])
        #expect(track.notes.map(\.tiesToNext) == [false, false, true, false])
    }

    @Test func groupStopsAtSongEdgeAsAWhole() {
        var track = emptyTrack()
        track.notes = [Note(start: 480, duration: 480, pitch: 60), Note(start: 1440, duration: 480, pitch: 62)]
        NoteEditing.move(ids: Set(track.notes.map(\.id)), by: -9999, pitch: { $0 }, in: &track, timeSignature: time, totalTicks: total)
        #expect(track.notes.map(\.start) == [0, 960])
    }

    @Test func groupWithTiedChainAndRest() {
        var track = emptyTrack()
        NoteEditing.enter(pitches: [65], at: 1440, duration: 960, in: &track, timeSignature: time, totalTicks: total)
        track.notes.append(Note.rest(start: 960, duration: 480))
        let moved = NoteEditing.move(ids: Set(track.notes.map(\.id)), by: -960, pitch: { $0 + 1 }, in: &track,
                                     timeSignature: time, totalTicks: total)
        // 休符は横にだけ、タイの一続きは 2分音符1つに戻る
        #expect(moved.count == 2)
        #expect(track.notes.map { [$0.start, $0.duration, $0.pitch ?? -1] } == [[0, 480, -1], [480, 960, 66]])
    }

    @Test func nudgingStepByStepDoesNotFragment() {
        var track = emptyTrack()
        track.notes = [60, 64, 67].map { Note(start: 0, duration: 1920, pitch: $0) }
        var ids: Set<Note.ID> = [track.notes[2].id]
        // 16分ずつ8回 → 一度に2拍動かしたのと同じ結果
        for _ in 0..<8 {
            ids = Set(NoteEditing.move(ids: ids, by: 120, pitch: { $0 }, in: &track, timeSignature: time, totalTicks: total))
        }
        #expect(track.notes.map { [$0.start, $0.duration, $0.pitch!] } == [[0, 1920, 60], [0, 1920, 64], [960, 960, 67], [1920, 960, 67]])
        // 元の位置へ戻すと、C E G の全音符3つに戻る
        NoteEditing.move(ids: ids, by: -960, pitch: { $0 }, in: &track, timeSignature: time, totalTicks: total)
        #expect(track.notes.map { [$0.start, $0.duration, $0.pitch!] } == [[0, 1920, 60], [0, 1920, 64], [0, 1920, 67]])
        #expect(track.notes.allSatisfy { !$0.tiesToNext })
    }

    @Test func movingAwayRejoinsSplitNotes() {
        var track = emptyTrack()
        track.notes = [60, 64, 67].map { Note(start: 0, duration: 1920, pitch: $0) }
        let g = NoteEditing.move(ids: [track.notes[2].id], by: 960, pitch: { $0 }, in: &track, timeSignature: time, totalTicks: total)
        // G を次の小節の頭へ → C E は全音符1つに戻る
        NoteEditing.move(ids: Set(g), by: 960, pitch: { $0 }, in: &track, timeSignature: time, totalTicks: total)
        #expect(track.notes.map { [$0.start, $0.duration, $0.pitch!] } == [[0, 1920, 60], [0, 1920, 64], [1920, 1920, 67]])
    }
}
