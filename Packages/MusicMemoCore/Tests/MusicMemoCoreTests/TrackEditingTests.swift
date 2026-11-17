import Foundation
import Testing
@testable import MusicMemoCore

struct TrackEditingTests {
    func sketch(_ names: [String]) -> Sketch {
        Sketch(title: "T", barCount: 4, tracks: names.enumerated().map { index, name in
            Track(name: name, role: .melody, color: TrackColor.allCases[index % 6])
        })
    }

    @Test func gmTableHas128Names() {
        #expect(GMInstruments.names.count == 128)
        #expect(Set(GMInstruments.names).count == 128)
        #expect(GMInstruments.families.count == 16)
        #expect(GMInstruments.name(of: 0) == "Piano")
        #expect(GMInstruments.name(of: 4) == "E.Piano")
        #expect(GMInstruments.name(of: 33) == "Finger Bass")
        #expect(GMInstruments.name(of: 48) == "Strings")
        #expect(GMInstruments.family(of: 33)?.name == "ベース")
    }

    @Test func addUsesRoleTemplateAndUnusedColor() {
        var song = sketch(["A", "B"])  // blue, orange
        let track = TrackEditing.addTrack(role: .bass, at: 1, in: &song)
        #expect(track?.name == "Finger Bass")
        #expect(track?.clef == .bass)
        #expect(track?.program == 33)
        #expect(track?.color == .green)
        #expect(song.tracks.map(\.name) == ["A", "Finger Bass", "B"])
    }

    @Test func addStopsAtMaximum() {
        var song = sketch(Array(repeating: "T", count: TrackEditing.maximumCount))
        #expect(TrackEditing.addTrack(role: .melody, in: &song) == nil)
        #expect(song.tracks.count == TrackEditing.maximumCount)
    }

    @Test func colorsCycleWhenAllUsed() {
        let song = sketch(["1", "2", "3", "4", "5", "6", "7"])  // blue が2つ
        #expect(TrackEditing.nextColor(in: song.tracks) == .orange)
    }

    @Test func duplicateCopiesNotesWithNewIDs() {
        var song = sketch(["A", "B"])
        song.tracks[0].notes = [Note(start: 0, duration: 480, pitch: 60, tiesToNext: true), Note(start: 480, duration: 480, pitch: 60)]
        song.tracks[0].isSoloed = true
        let copy = TrackEditing.duplicateTrack(song.tracks[0].id, in: &song)
        #expect(song.tracks.map(\.name) == ["A", "A", "B"])
        #expect(copy?.id != song.tracks[0].id)
        #expect(copy?.isSoloed == false)
        #expect(copy?.notes.map(\.pitch) == [60, 60])
        #expect(copy?.notes.map(\.tiesToNext) == [true, false])
        #expect(Set(copy!.notes.map(\.id)).isDisjoint(with: song.tracks[0].notes.map(\.id)))
    }

    @Test func removeKeepsLastTrack() {
        var song = sketch(["A", "B"])
        #expect(TrackEditing.removeTrack(song.tracks[0].id, in: &song))
        #expect(song.tracks.map(\.name) == ["B"])
        #expect(!TrackEditing.removeTrack(song.tracks[0].id, in: &song))
        #expect(song.tracks.count == 1)
    }

    @Test func moveUsesInsertionIndex() {
        var song = sketch(["A", "B", "C", "D"])
        TrackEditing.moveTrack(song.tracks[0].id, to: 3, in: &song)  // A を C と D の間へ
        #expect(song.tracks.map(\.name) == ["B", "C", "A", "D"])
        TrackEditing.moveTrack(song.tracks[3].id, to: 0, in: &song)  // D を先頭へ
        #expect(song.tracks.map(\.name) == ["D", "B", "C", "A"])
        TrackEditing.moveTrack(song.tracks[1].id, to: 2, in: &song)  // 動かない（すぐ後ろ）
        #expect(song.tracks.map(\.name) == ["D", "B", "C", "A"])
        TrackEditing.moveTrack(song.tracks[0].id, to: 99, in: &song)  // 末尾へ
        #expect(song.tracks.map(\.name) == ["B", "C", "A", "D"])
    }

    @Test func programRenamesOnlyWhenNameFollowsInstrument() {
        var track = Track(name: "Piano", role: .melody, color: .blue, program: 0)
        TrackEditing.setProgram(24, of: &track)
        #expect(track.name == "Nylon Guitar")
        #expect(track.program == 24)

        var named = Track(name: "Lead", role: .melody, color: .blue, program: 0)
        TrackEditing.setProgram(24, of: &named)
        #expect(named.name == "Lead")
        #expect(named.program == 24)
    }

    @Test func emptyNameFallsBackToInstrument() {
        var track = Track(name: "Piano", role: .melody, color: .blue, program: 33)
        TrackEditing.setName("  Bass 2 ", of: &track)
        #expect(track.name == "Bass 2")
        TrackEditing.setName("   ", of: &track)
        #expect(track.name == "Finger Bass")
    }
}
