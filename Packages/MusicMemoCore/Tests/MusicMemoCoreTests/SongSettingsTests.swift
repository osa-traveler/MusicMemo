import Foundation
import Testing
@testable import MusicMemoCore

struct SongSettingsTests {
    func sketch(barCount: Int = 4, notes: [Note] = [], sections: [SongSection] = [], chords: [ChordEvent] = []) -> Sketch {
        Sketch(title: "T", barCount: barCount, sections: sections, chords: chords,
               tracks: [Track(name: "T", role: .melody, color: .blue, notes: notes)])
    }

    // MARK: キー

    @Test func transpositionTakesNearestDirection() {
        let c = Key.cMajor
        #expect(SongSettings.transposition(from: c, to: Key(tonic: 2, mode: .major)) == 2)    // D：上へ2
        #expect(SongSettings.transposition(from: c, to: Key(tonic: 10, mode: .major)) == -2)  // Bb：下へ2
        #expect(SongSettings.transposition(from: c, to: Key(tonic: 6, mode: .major)) == 6)    // F#：上へ6
        #expect(SongSettings.transposition(from: c, to: Key(tonic: 9, mode: .minor)) == -3)   // Am：主音の差（下へ3）
    }

    @Test func setKeyTransposesNotesAndChords() {
        var song = sketch(notes: [Note(start: 0, duration: 480, pitch: 60), .rest(start: 480, duration: 480)],
                          chords: [ChordEvent(start: 0, chord: Chord("C/E")!)])
        SongSettings.setKey(Key(tonic: 10, mode: .major), transpose: true, in: &song)
        #expect(song.key == Key(tonic: 10, mode: .major))
        #expect(song.tracks[0].notes.map(\.pitch) == [58, nil])
        #expect(song.chords[0].chord.symbol == "Bb/D")
    }

    @Test func setKeyWithoutTransposeKeepsPitches() {
        var song = sketch(notes: [Note(start: 0, duration: 480, pitch: 60)], chords: [ChordEvent(start: 0, chord: Chord("C")!)])
        SongSettings.setKey(Key(tonic: 7, mode: .major), transpose: false, in: &song)
        #expect(song.key.tonic == 7)
        #expect(song.tracks[0].notes[0].pitch == 60)
        #expect(song.chords[0].chord.symbol == "C")
    }

    @Test func transposeKeepsMIDIRange() {
        var notes = [Note(start: 0, duration: 480, pitch: 126), Note(start: 0, duration: 480, pitch: 1)]
        SongSettings.transposeNotes(&notes, by: 5)
        #expect(notes.map(\.pitch) == [119, 6])
        SongSettings.transposeNotes(&notes, by: -10)
        #expect(notes.map(\.pitch) == [109, 8])
    }

    // MARK: 拍子

    @Test func timeSignatureKeepsTimesAndRebarsNotes() {
        // 4/4 の2小節目の頭から2分音符 → 3/4 では 1920 は2小節目の2拍目。2拍で収まる
        // 4/4 の3拍目からの2分音符（1小節目の終わりまで）→ 3/4 では小節線（1440）をまたぐのでタイで分ける
        var song = sketch(notes: [Note(start: 960, duration: 960, pitch: 60), Note(start: 1920, duration: 960, pitch: 62)])
        SongSettings.setTimeSignature(TimeSignature(beats: 3, beatUnit: 4), in: &song)
        #expect(song.timeSignature.beats == 3)
        #expect(song.barCount == 6)  // 4/4 × 4小節 = 7680 tick → 3/4（1440）で 5.33 → 6小節
        #expect(song.tracks[0].notes.map { [$0.start, $0.duration, $0.pitch!] } == [[960, 480, 60], [1440, 480, 60], [1920, 960, 62]])
        #expect(song.tracks[0].notes.map(\.tiesToNext) == [true, false, false])
    }

    @Test func timeSignatureMergesOldTieAcrossBarLine() {
        // 4/4 で小節線をまたいで分けた音（4分＋タイ＋4分）→ 3/4 では1つの2分音符に戻る
        var song = sketch(notes: [Note(start: 1440, duration: 480, pitch: 60, tiesToNext: true), Note(start: 1920, duration: 480, pitch: 60)])
        SongSettings.setTimeSignature(TimeSignature(beats: 3, beatUnit: 4), in: &song)
        #expect(song.tracks[0].notes.map { [$0.start, $0.duration] } == [[1440, 960]])
        #expect(song.tracks[0].notes[0].tiesToNext == false)
    }

    @Test func timeSignatureSplitsRests() {
        var song = sketch(notes: [.rest(start: 0, duration: 1920)])
        SongSettings.setTimeSignature(TimeSignature(beats: 3, beatUnit: 4), in: &song)
        #expect(song.tracks[0].notes.map { [$0.start, $0.duration] } == [[0, 1440], [1440, 480]])
        #expect(song.tracks[0].notes.allSatisfy { $0.isRest })
    }

    @Test func timeSignatureMovesSectionBoundariesToNearestBar() {
        // 4/4 × 8小節：A 1–4、B 5–8 → 3/4 では 境目 7680 tick ≒ 5.33小節 → 6小節目の頭。曲は 11小節
        var song = sketch(barCount: 8, sections: [SongSection(name: "A", startBar: 1, barCount: 4), SongSection(name: "B", startBar: 5, barCount: 4)])
        SongSettings.setTimeSignature(TimeSignature(beats: 3, beatUnit: 4), in: &song)
        #expect(song.barCount == 11)
        #expect(song.sections.map { [$0.startBar, $0.barCount] } == [[1, 5], [6, 6]])
    }

    @Test func timeSignatureClampsPlayRange() {
        var song = sketch(barCount: 4)
        song.playRange = 1920..<7680
        SongSettings.setTimeSignature(TimeSignature(beats: 2, beatUnit: 4), in: &song)
        #expect(song.barCount == 8)
        #expect(song.playRange == 1920..<7680)
    }

    // MARK: テンポ・小節数

    @Test func tempoIsClamped() {
        var song = sketch()
        SongSettings.setTempo(300, in: &song)
        #expect(song.tempo == 240)
        SongSettings.setTempo(10, in: &song)
        #expect(song.tempo == 40)
    }

    @Test func shrinkingRemovesNotesChordsAndSections() {
        var song = sketch(
            barCount: 4,
            notes: [
                Note(start: 0, duration: 480, pitch: 60),
                Note(start: 3360, duration: 480, pitch: 62, tiesToNext: true),  // 2小節目の4拍目から、3小節目へタイ
                Note(start: 3840, duration: 480, pitch: 62),
                Note(start: 5760, duration: 480, pitch: 64),
            ],
            sections: [SongSection(name: "A", startBar: 1, barCount: 2), SongSection(name: "B", startBar: 3, barCount: 2)],
            chords: [ChordEvent(start: 0, chord: Chord("C")!), ChordEvent(start: 3840, chord: Chord("G")!)]
        )
        song.playRange = 1920..<7680
        // 消えるのは 4小節目の音（タイの続きは数えない）
        #expect(SongSettings.notesRemoved(byBarCount: 2, in: song) == 1)
        SongSettings.setBarCount(2, in: &song)
        #expect(song.tracks[0].notes.map { [$0.start, $0.duration] } == [[0, 480], [3360, 480]])
        #expect(song.tracks[0].notes[1].tiesToNext == false)
        #expect(song.chords.map(\.chord.symbol) == ["C"])
        #expect(song.sections.map(\.name) == ["A"])
        #expect(song.playRange == 1920..<3840)
    }

    @Test func shrinkingClipsSectionAndResetsEmptyPlayRange() {
        var song = sketch(barCount: 8, sections: [SongSection(name: "A", startBar: 1, barCount: 8)])
        song.playRange = 7680..<9600
        SongSettings.setBarCount(3, in: &song)
        #expect(song.sections.map(\.barCount) == [3])
        #expect(song.playRange == 0..<5760)
    }

    @Test func growingExtendsLastSectionOnlyWhenItReachesTheEnd() {
        var song = sketch(barCount: 4, sections: [SongSection(name: "A", startBar: 1, barCount: 4)])
        SongSettings.setBarCount(6, in: &song)
        #expect(song.sections.map(\.barCount) == [6])

        var partial = sketch(barCount: 4, sections: [SongSection(name: "A", startBar: 1, barCount: 2)])
        SongSettings.setBarCount(6, in: &partial)
        #expect(partial.sections.map(\.barCount) == [2])
    }
}
