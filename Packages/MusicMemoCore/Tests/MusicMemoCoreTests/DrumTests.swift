import Foundation
import Testing
@testable import MusicMemoCore

/// ドラムのトラック：記譜（ドラム譜）・読み込み・書き出し・ファイル形式・編集の決まり。
struct DrumTests {
    /// 8ビート1小節：ハイハット（8分）、スネア（2・4拍）、バスドラム（1・3拍）。
    private func eightBeat() -> Track {
        var notes: [Note] = []
        for eighth in 0..<8 { notes.append(Note(start: eighth * 240, duration: 240, pitch: 42)) }
        for beat in [1, 3] { notes.append(Note(start: beat * 480, duration: 240, pitch: 38)) }
        for beat in [0, 2] { notes.append(Note(start: beat * 480, duration: 960, pitch: 36)) }
        return Track(name: "Drums", role: .drums, clef: .percussion, color: .gray, notes: notes)
    }

    private func sketch(with drums: Track) -> Sketch {
        Sketch(title: "t", barCount: 2, tracks: [
            Track(name: "Piano", role: .melody, color: .blue, notes: [Note(start: 0, duration: 480, pitch: 60)]),
            drums,
        ])
    }

    @Test func drumNotationSplitsHandsAndFeet() {
        let voices = Notation.voices(for: eightBeat().notes, clef: .percussion, key: .cMajor, timeSignature: .common)
        #expect(voices.count == 2)
        #expect(voices[0].chords.allSatisfy { $0.stemUp && $0.heads.allSatisfy { $0.accidental == nil } })
        #expect(voices[1].chords.allSatisfy { !$0.stemUp })
        // ハイハットは五線の上に ×、スネアは第3間、バスドラムは第1間
        let hats = voices[0].chords.flatMap(\.heads).filter { $0.pitch == 42 }
        #expect(hats.allSatisfy { $0.staffPosition == 9 && $0.isCross })
        #expect(voices[0].chords.flatMap(\.heads).filter { $0.pitch == 38 }.allSatisfy { $0.staffPosition == 5 && !$0.isCross })
        #expect(voices[1].chords.flatMap(\.heads).allSatisfy { $0.staffPosition == 1 })
        // ハイハットの8分は拍ごとに連桁
        #expect(voices[0].beamGroups.count == 4)
    }

    @Test func percussionClefMapsPositionsBothWays() {
        #expect(Clef.percussion.staffPosition(ofPitch: 36, in: .cMajor) == 1)
        #expect(Clef.percussion.pitch(atStaffPosition: 5, in: .cMajor) == 38)
        #expect(Clef.percussion.pitch(atStaffPosition: 12, in: .cMajor) == 56)  // 表に無い位置は近い楽器
        #expect(KeySignature(fifths: 3).staffPositions(for: .percussion).isEmpty)
    }

    @Test func importedDrumsLastWithLengthsToNextHit() throws {
        // 10ch：バスドラム 1・3拍、スネア 2・4拍、ハイハット 8分（少しずらして弾いた）。ほかに 1ch のピアノ
        var events: [(Int, [UInt8])] = [(0, [0x90, 60, 100]), (480, [0x80, 60, 0]), (0, [0xC9, 0])]
        for eighth in 0..<8 {
            let tick = eighth * 240 + (eighth % 2 == 0 ? 0 : 12)
            events += [(tick, [0x99, 42, 90]), (tick + 30, [0x89, 42, 0])]
        }
        for beat in [1, 3] { events += [(beat * 480, [0x99, 38, 100]), (beat * 480 + 60, [0x89, 38, 0])] }
        for beat in [0, 2] { events += [(beat * 480 + 5, [0x99, 36, 100]), (beat * 480 + 60, [0x89, 36, 0])] }
        var builder = SMFTestBuilder()
        builder.tracks = [SMFTestBuilder.track(events)]
        let result = try MIDIImporter.convert(builder.data, title: "t")
        let tracks = result.file.sketch.tracks
        #expect(tracks.map(\.role) == [.melody, .drums])
        let drums = tracks[1]
        #expect(drums.clef == .percussion)
        // ハイハットは8分、スネアは次のスネアまで（手の声部はハイハットと同じ位置なので8分）、バスドラムは次のバスドラムまで（2分）
        #expect(drums.notes.filter { $0.pitch == 42 }.map(\.duration) == Array(repeating: 240, count: 8))
        #expect(drums.notes.filter { $0.pitch == 38 }.map(\.duration) == [240, 240])
        #expect(drums.notes.filter { $0.pitch == 36 }.map(\.start) == [0, 960])
        #expect(drums.notes.filter { $0.pitch == 36 }.map(\.duration) == [960, 960])
        #expect(drums.notes.allSatisfy { !$0.tiesToNext })
        #expect(result.warnings.isEmpty)
    }

    @Test func midiExportPutsDrumsOnChannel10() {
        let channels = MIDIExporter.channels(for: sketch(with: eightBeat()).tracks)
        #expect(channels == [0, 9])
        // ドラムが先にあっても、ほかのトラックは 1ch から
        let reversed = MIDIExporter.channels(for: [eightBeat(), Track(name: "A", role: .melody, color: .blue)])
        #expect(reversed == [9, 0])
    }

    @Test func midiRoundTripKeepsDrums() throws {
        let original = sketch(with: eightBeat())
        let imported = try MIDIImporter.convert(MIDIExporter.data(for: original), title: "t").file.sketch
        #expect(imported.tracks.map(\.role) == [.melody, .drums])
        let shape = { (notes: [Note]) in notes.map { [$0.start, $0.duration, $0.pitch ?? -1] }.sorted { $0.lexicographicallyPrecedes($1) } }
        #expect(shape(imported.tracks[1].notes) == shape(eightBeat().notes))
    }

    @Test func musicXMLWritesPercussionPart() {
        let xml = MusicXMLExporter.string(for: sketch(with: eightBeat()))
        #expect(xml.contains("<sign>percussion</sign>"))
        #expect(xml.contains("<midi-unpitched>43</midi-unpitched>"))   // ハイハット 42 + 1
        #expect(xml.contains("<midi-channel>10</midi-channel>"))
        #expect(xml.contains("<display-step>G</display-step>"))         // ハイハット＝G5
        #expect(xml.contains("<instrument id=\"P2-I37\"/>"))            // バスドラム 36 + 1
        #expect(xml.contains("<notehead>x</notehead>"))
        // 音高で書かれるのはピアノの C4 だけ
        #expect(xml.components(separatedBy: "<step>").count - 1 == 1)
    }

    @Test func fileVersionDependsOnDrums() throws {
        let plain = SketchFile(sketch: SampleData.sketch03())
        #expect(String(decoding: try plain.encoded(), as: UTF8.self).contains("\"formatVersion\" : 1"))
        let withDrums = SketchFile(sketch: sketch(with: eightBeat()))
        let data = try withDrums.encoded()
        #expect(String(decoding: data, as: UTF8.self).contains("\"formatVersion\" : 2"))
        #expect(try SketchFile.decode(data).sketch.tracks[1].isDrums)
    }

    @Test func drumsAreOutsideTheTrackLimitAndNotDuplicated() {
        var sketch = Sketch(title: "t", barCount: 1, tracks: (0..<TrackEditing.maximumCount).map {
            Track(name: "T\($0)", role: .other, color: .gray)
        })
        sketch.tracks.append(eightBeat())
        #expect(!TrackEditing.canAdd(to: sketch))
        sketch.tracks.removeFirst()
        #expect(TrackEditing.canAdd(to: sketch))   // ドラム以外が14本
        #expect(TrackEditing.duplicateTrack(sketch.tracks.last!.id, in: &sketch) == nil)
    }

    @Test func transposingKeepsDrums() {
        var sketch = sketch(with: eightBeat())
        SongSettings.setKey(Key(tonic: 2, mode: .major), transpose: true, in: &sketch)
        #expect(sketch.tracks[0].notes[0].pitch == 62)
        #expect(sketch.tracks[1].notes.map(\.pitch) == eightBeat().notes.map(\.pitch))
    }
}
