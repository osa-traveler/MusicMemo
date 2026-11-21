import Foundation
import Testing
@testable import MusicMemoCore

/// 1音を重ねて置く（NoteEditing.place。譜面の直接タップ）：和音、同じ高さの上書き、休符、小節線、3連符、タイ、曲の終わり、ドラム。
struct PlaceTests {
    private let time = TimeSignature.common
    private func shape(_ notes: [Note]) -> [[Int]] {
        notes.map { [$0.start, $0.duration, $0.pitch ?? -1, $0.tiesToNext ? 1 : 0] }.sorted { $0.lexicographicallyPrecedes($1) }
    }

    @Test func placesIntoEmptyTrack() {
        var track = Track(name: "P", role: .melody, color: .blue)
        let ids = NoteEditing.place(pitch: 60, at: 480, duration: 480, in: &track, timeSignature: time, totalTicks: 1920 * 2)
        #expect(shape(track.notes) == [[480, 480, 60, 0]])
        #expect(ids == track.notes.map(\.id))
    }

    @Test func sameStartDifferentPitchMakesChord() {
        var track = Track(name: "P", role: .melody, color: .blue, notes: [Note(start: 0, duration: 480, pitch: 60)])
        NoteEditing.place(pitch: 64, at: 0, duration: 480, in: &track, timeSignature: time, totalTicks: 1920)
        #expect(shape(track.notes) == [[0, 480, 60, 0], [0, 480, 64, 0]])
    }

    @Test func samePitchIsOverwritten() {
        // 2分の C の2拍目に 4分の C → 前は切り詰め、新しい音で上書き
        var track = Track(name: "P", role: .melody, color: .blue, notes: [Note(start: 0, duration: 960, pitch: 60)])
        NoteEditing.place(pitch: 60, at: 480, duration: 480, in: &track, timeSignature: time, totalTicks: 1920)
        #expect(shape(track.notes) == [[0, 480, 60, 0], [480, 480, 60, 0]])
    }

    @Test func restIsOverwritten() {
        var track = Track(name: "P", role: .melody, color: .blue, notes: [Note.rest(start: 0, duration: 480)])
        NoteEditing.place(pitch: 67, at: 0, duration: 480, in: &track, timeSignature: time, totalTicks: 1920)
        #expect(shape(track.notes) == [[0, 480, 67, 0]])
    }

    @Test func splitsAcrossBarline() {
        // 4拍目から2分 → 4分＋タイ＋4分
        var track = Track(name: "P", role: .melody, color: .blue)
        let ids = NoteEditing.place(pitch: 62, at: 1440, duration: 960, in: &track, timeSignature: time, totalTicks: 1920 * 2)
        #expect(shape(track.notes) == [[1440, 480, 62, 1], [1920, 480, 62, 0]])
        #expect(ids.count == 2)
    }

    @Test func placesTriplet() {
        var track = Track(name: "P", role: .melody, color: .blue)
        let triplet = NoteDuration(.eighth, triplet: true).ticks
        NoteEditing.place(pitch: 60, at: triplet, duration: triplet, in: &track, timeSignature: time, totalTicks: 1920)
        #expect(shape(track.notes) == [[triplet, triplet, 60, 0]])
    }

    @Test func tiesFromPreviousSamePitch() {
        var track = Track(name: "P", role: .melody, color: .blue, notes: [
            Note(start: 0, duration: 480, pitch: 60), Note(start: 0, duration: 480, pitch: 64),
        ])
        NoteEditing.place(pitch: 60, at: 480, duration: 480, tieFromPrevious: true, in: &track, timeSignature: time, totalTicks: 1920)
        #expect(shape(track.notes) == [[0, 480, 60, 1], [0, 480, 64, 0], [480, 480, 60, 0]])
    }

    @Test func clipsAtTheEndOfTheSong() {
        var track = Track(name: "P", role: .melody, color: .blue)
        NoteEditing.place(pitch: 60, at: 1440, duration: 1920, in: &track, timeSignature: time, totalTicks: 1920)
        #expect(shape(track.notes) == [[1440, 480, 60, 0]])
    }

    @Test func drumsAreLayered() {
        var drums = Track(name: "D", role: .drums, clef: .percussion, color: .gray, notes: [Note(start: 0, duration: 480, pitch: 36)])
        NoteEditing.place(pitch: DrumMap.pitch(atStaffPosition: 5), at: 0, duration: 240, in: &drums, timeSignature: time, totalTicks: 1920)
        #expect(shape(drums.notes) == [[0, 240, 38, 0], [0, 480, 36, 0]])
    }
}
