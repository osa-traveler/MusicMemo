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
}
