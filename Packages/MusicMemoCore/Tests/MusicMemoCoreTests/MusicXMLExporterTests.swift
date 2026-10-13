import Foundation
import Testing
@testable import MusicMemoCore

/// テスト用：MusicXML を読み、パート・小節ごとの長さや要素を集める。
private final class ScoreReader: NSObject, XMLParserDelegate {
    struct Measure {
        var duration = 0
        var harmonies: [String] = []
        var rehearsals: [String] = []
        var tieStarts = 0
        var tieStops = 0
        var pitches: [String] = []
    }

    var parts: [String: [Measure]] = [:]
    var partNames: [String] = []
    var parseError: Error?

    private var part = ""
    private var path: [String] = []
    private var text = ""
    private var noteIsChord = false
    private var noteDuration = 0
    private var pitch = ""
    private var harmony = ""

    init(_ data: Data) {
        super.init()
        let parser = XMLParser(data: data)
        parser.delegate = self
        if !parser.parse() { parseError = parser.parserError }
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        path.append(name)
        text = ""
        switch name {
        case "part": part = attributes["id"] ?? ""; parts[part] = []
        case "measure": parts[part, default: []].append(Measure())
        case "note": noteIsChord = false; noteDuration = 0; pitch = ""
        case "chord": noteIsChord = true
        case "harmony": harmony = ""
        case "tie":
            if attributes["type"] == "start" { parts[part]![parts[part]!.count - 1].tieStarts += 1 }
            if attributes["type"] == "stop" { parts[part]![parts[part]!.count - 1].tieStops += 1 }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let parent = path.dropLast().last
        switch (name, parent) {
        case ("part-name", _): partNames.append(text)
        case ("duration", "note"): noteDuration = Int(text) ?? 0
        case ("step", "pitch"), ("alter", "pitch"), ("octave", "pitch"): pitch += text
        case ("root-step", _), ("root-alter", _), ("bass-step", _): harmony += (name == "bass-step" ? "/" : "") + text
        case ("kind", _): harmony += "|" + text
        case ("rehearsal", _): parts[part]![parts[part]!.count - 1].rehearsals.append(text)
        default: break
        }
        if name == "note" {
            let index = parts[part]!.count - 1
            if !noteIsChord { parts[part]![index].duration += noteDuration }
            if !pitch.isEmpty { parts[part]![index].pitches.append(pitch) }
        }
        if name == "harmony" { parts[part]![parts[part]!.count - 1].harmonies.append(harmony) }
        path.removeLast()
    }
}

struct MusicXMLExporterTests {
    let sketch = SampleData.sketch03()

    @Test func isWellFormed() {
        let reader = ScoreReader(MusicXMLExporter.data(for: sketch))
        #expect(reader.parseError == nil)
        #expect(reader.partNames == ["Piano", "E.Piano", "Finger Bass", "Strings"])
    }

    @Test func everyMeasureIsFilled() {
        let reader = ScoreReader(MusicXMLExporter.data(for: sketch))
        for (id, measures) in reader.parts {
            #expect(measures.count == 16, "\(id)")
            for (index, measure) in measures.enumerated() {
                #expect(measure.duration == 1920, "\(id) \(index + 1)小節")
            }
        }
    }

    @Test func chordSymbolsOnMelodyPart() {
        let reader = ScoreReader(MusicXMLExporter.data(for: sketch))
        let melody = reader.parts["P1"]!
        // 読み取りは「ルート|kind/ベース」の形（XML の並び順どおり）
        #expect(melody[4].harmonies == ["C|major/E"])
        #expect(melody[6].harmonies == ["D|minor-seventh"])
        #expect(melody[9].harmonies == ["G|major/B"])
        #expect(melody[13].harmonies.isEmpty)
        // 他のパートには付けない
        #expect(reader.parts["P2"]!.allSatisfy { $0.harmonies.isEmpty })
    }

    @Test func rehearsalMarksOnFirstPart() {
        let reader = ScoreReader(MusicXMLExporter.data(for: sketch))
        #expect(reader.parts["P1"]![0].rehearsals == ["Aメロ"])
        #expect(reader.parts["P1"]![8].rehearsals == ["サビ"])
    }

    @Test func pitchesAndTies() {
        var sketch = self.sketch
        // 8小節目の4拍目から2分音符（小節をまたいでタイ）
        NoteEditing.enter(pitches: [71], at: 1920 * 7 + 1440, duration: 960, in: &sketch.tracks[0],
                          timeSignature: sketch.timeSignature, totalTicks: sketch.totalTicks)
        let reader = ScoreReader(MusicXMLExporter.data(for: sketch))
        let melody = reader.parts["P1"]!
        #expect(melody[4].pitches == ["E4", "G4", "E5"])
        #expect(melody[7].tieStarts == 1)
        #expect(melody[8].tieStops == 1)
        #expect(melody[7].duration == 1920 && melody[8].duration == 1920)
    }

    @Test func tripletsAndAccidentalsStayValid() {
        var sketch = self.sketch
        let triplet = NoteDuration(.eighth, triplet: true).ticks
        for (index, pitch) in [66, 70, 73].enumerated() {
            NoteEditing.enter(pitches: [pitch], at: 1920 * 2 + index * triplet, duration: triplet, in: &sketch.tracks[0],
                              timeSignature: sketch.timeSignature, totalTicks: sketch.totalTicks)
        }
        let text = MusicXMLExporter.string(for: sketch)
        #expect(text.contains("<actual-notes>3</actual-notes>"))
        #expect(text.contains("<accidental>sharp</accidental>"))
        #expect(text.contains("<accidental>flat</accidental>"))
        let reader = ScoreReader(Data(text.utf8))
        #expect(reader.parts["P1"]![2].duration == 1920)
    }

    @Test func escapesText() {
        var sketch = self.sketch
        sketch.title = "A & B <test>"
        #expect(ScoreReader(MusicXMLExporter.data(for: sketch)).parseError == nil)
    }

    @Test func harmonyKinds() {
        #expect(MusicXMLExporter.harmonyKind(.minor7Flat5).0 == "half-diminished")
        #expect(MusicXMLExporter.spell(10, preferFlats: true) == ("B", -1))
        #expect(MusicXMLExporter.spell(6, preferFlats: false) == ("F", 1))
    }
}
