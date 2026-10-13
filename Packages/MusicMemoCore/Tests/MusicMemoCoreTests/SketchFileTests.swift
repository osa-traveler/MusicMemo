import Foundation
import Testing
@testable import MusicMemoCore

struct SketchFileTests {
    @Test func roundTrip() throws {
        var sketch = SampleData.sketch03()
        NoteEditing.enter(pitches: [71], at: 1920 * 7 + 1440, duration: 960, in: &sketch.tracks[0],
                          timeSignature: sketch.timeSignature, totalTicks: sketch.totalTicks)
        var editor = SampleData.editorState(for: sketch)
        editor.zoom = 1.5
        editor.duration = NoteDuration(.eighth, triplet: true)
        let file = SketchFile(sketch: sketch, editor: editor)
        let decoded = try SketchFile.decode(try file.encoded())
        #expect(decoded == file)
    }

    @Test func rejectsNewerFormat() throws {
        var file = SketchTemplate.blank()
        file.formatVersion = SketchFile.currentFormatVersion + 1
        let data = try file.encoded()
        #expect(throws: SketchFile.ReadError.newerFormat(SketchFile.currentFormatVersion + 1)) {
            try SketchFile.decode(data)
        }
    }

    @Test func formatVersionIsWritten() throws {
        let text = String(decoding: try SketchTemplate.blank().encoded(), as: UTF8.self)
        #expect(text.contains("\"formatVersion\" : 1"))
    }

    @Test func blankTemplate() {
        let file = SketchTemplate.blank()
        let sketch = file.sketch
        #expect(sketch.title == "無題")
        #expect(sketch.key == .cMajor)
        #expect(sketch.tempo == 120)
        #expect(sketch.barCount == 16)
        #expect(sketch.sections.map(\.name) == ["Aメロ"])
        #expect(sketch.sections[0].bars == 1...16)
        #expect(sketch.tracks.map(\.name) == ["Piano", "E.Piano", "Finger Bass"])
        #expect(sketch.tracks.map(\.role) == [.melody, .chords, .bass])
        #expect(sketch.tracks[2].clef == .bass)
        #expect(sketch.chords.isEmpty)
        #expect(sketch.tracks.allSatisfy { $0.notes.isEmpty })
        #expect(file.editor?.selectedTrackID == sketch.tracks[0].id)
    }
}
