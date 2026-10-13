import Foundation
import Testing
@testable import MusicMemoCore

struct ModelTests {
    @Test func durations() {
        #expect(NoteDuration(.whole).ticks == 1920)
        #expect(NoteDuration(.quarter).ticks == 480)
        #expect(NoteDuration(.quarter, dotted: true).ticks == 720)
        #expect(NoteDuration(.eighth, triplet: true).ticks == 160)
        #expect(NoteDuration(.sixteenth, triplet: true).ticks == 80)
        #expect(NoteDuration(.eighth, dotted: true, triplet: true).ticks == 240)
    }

    @Test func panLabels() {
        #expect(Track.panLabel(0) == "C")
        #expect(Track.panLabel(-16) == "L16")
        #expect(Track.panLabel(20) == "R20")
        #expect(Track.panLabel(-64) == "L64")
    }

    @Test func trackClampsVolumeAndPan() {
        let track = Track(name: "X", role: .other, color: .gray, volume: 140, pan: -100)
        #expect(track.volume == 100)
        #expect(track.pan == -64)
    }

    @Test func rest() {
        let rest = Note.rest(start: 0, duration: 480)
        #expect(rest.isRest)
        #expect(rest.end == 480)
    }

    @Test func codableRoundTrip() throws {
        let sketch = SampleData.sketch03()
        let data = try JSONEncoder().encode(sketch)
        #expect(try JSONDecoder().decode(Sketch.self, from: data) == sketch)
    }
}

struct SampleDataTests {
    let sketch = SampleData.sketch03()

    @Test func header() {
        #expect(sketch.title == "スケッチ 03")
        #expect(sketch.key.description == "C major")
        #expect(sketch.tempo == 96)
        #expect(sketch.barCount == 16)
        #expect(sketch.tracks.map(\.name) == ["Piano", "E.Piano", "Finger Bass", "Strings"])
        #expect(sketch.tracks.map(\.panLabel) == ["C", "L16", "C", "R20"])
    }

    @Test func playRange() {
        let time = sketch.timeSignature
        #expect(time.position(of: sketch.playRange.lowerBound).barBeatDescription == "6.1")
        #expect(time.position(of: sketch.playRange.upperBound).barBeatDescription == "8.1")
        #expect(sketch.isLooping)
    }

    @Test func sectionsCoverAllBars() {
        let covered = sketch.sections.flatMap { Array($0.bars) }
        #expect(covered == Array(1...sketch.barCount))
        #expect(sketch.section(containingBar: 9)?.name == "サビ")
    }

    @Test func chordAtEditPosition() {
        let state = SampleData.editorState(for: sketch)
        let chord = sketch.chord(at: state.editPosition)?.chord
        #expect(chord?.symbol == "Dm7")
        #expect(chord?.pitchClasses == [2, 5, 9, 0])  // D F A C
        #expect(sketch.chords(inBar: 14).isEmpty)
        #expect(sketch.chords(inBar: 10).map(\.chord.symbol) == ["G/B"])
    }

    @Test func notesStayInsideTheirBar() {
        let time = sketch.timeSignature
        for track in sketch.tracks {
            for note in track.notes {
                #expect(note.duration > 0)
                #expect(note.end <= sketch.totalTicks)
                #expect(time.bar(containing: note.start) == time.bar(containing: note.end - 1),
                        "\(track.name) の音符が小節線をまたいでいる: \(time.position(of: note.start).description)")
            }
        }
    }

    @Test func notesFillTheirBars() {
        // 各トラックの入力済み小節は、拍が過不足なく埋まっている（和音は1つと数える）
        let time = sketch.timeSignature
        for track in sketch.tracks {
            let starts = Dictionary(grouping: track.notes, by: \.start).mapValues { $0[0].duration }
            let byBar = Dictionary(grouping: starts, by: { time.bar(containing: $0.key) })
            for (bar, entries) in byBar {
                #expect(entries.map(\.value).reduce(0, +) == time.ticksPerBar, "\(track.name) \(bar)小節")
            }
        }
    }
}
