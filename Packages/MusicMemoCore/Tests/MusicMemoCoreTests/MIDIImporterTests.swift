import Foundation
import Testing
@testable import MusicMemoCore

/// テスト用の SMF を組み立てる。
private struct SMFBuilder {
    var format = 1
    var division = 480
    var tracks: [[UInt8]] = []

    static func vlq(_ value: Int) -> [UInt8] {
        var value = value
        var bytes = [UInt8(value & 0x7F)]
        value >>= 7
        while value > 0 { bytes.insert(UInt8(value & 0x7F) | 0x80, at: 0); value >>= 7 }
        return bytes
    }

    /// (tick, バイト列) からトラックを作る（tick は絶対位置）。
    static func track(_ events: [(Int, [UInt8])]) -> [UInt8] {
        var bytes: [UInt8] = []
        var last = 0
        for (tick, data) in events.sorted(by: { $0.0 < $1.0 }) {
            bytes += vlq(tick - last) + data
            last = tick
        }
        return bytes + [0, 0xFF, 0x2F, 0]
    }

    static func meta(_ type: UInt8, _ payload: [UInt8]) -> [UInt8] {
        [0xFF, type] + vlq(payload.count) + payload
    }

    var data: Data {
        var bytes = Array("MThd".utf8) + [0, 0, 0, 6, 0, UInt8(format), 0, UInt8(tracks.count), UInt8(division >> 8), UInt8(division & 0xFF)]
        for track in tracks {
            bytes += Array("MTrk".utf8) + [UInt8(track.count >> 24), UInt8(track.count >> 16 & 0xFF), UInt8(track.count >> 8 & 0xFF), UInt8(track.count & 0xFF)] + track
        }
        return Data(bytes)
    }
}

/// 音符を (開始, 長さ, 音高, タイ) で比べる。
private func shape(_ notes: [Note]) -> [[Int]] {
    notes.map { [$0.start, $0.duration, $0.pitch ?? -1, $0.tiesToNext ? 1 : 0] }
        .sorted { $0.lexicographicallyPrecedes($1) }
}

@Suite struct MIDIImportRoundTripTests {
    /// MusicMemo で書き出した MIDI を読み戻すと、曲の設定・トラック・音符（タイの分け方も）が元に戻る。
    @Test func sampleSketchRoundTrips() throws {
        let original = SampleData.sketch03()
        let data = MIDIExporter.data(for: original)
        let result = try MIDIImporter.convert(data, title: original.title)
        let sketch = result.file.sketch

        #expect(sketch.key == original.key)
        #expect(sketch.timeSignature == original.timeSignature)
        #expect(sketch.tempo == original.tempo)
        #expect(sketch.sections.map(\.name) == original.sections.map(\.name))
        #expect(sketch.sections.map(\.startBar) == original.sections.map(\.startBar))
        #expect(sketch.tracks.map(\.name) == original.tracks.map(\.name))
        #expect(sketch.tracks.map(\.program) == original.tracks.map(\.program))
        for (imported, source) in zip(sketch.tracks, original.tracks) {
            #expect(abs(imported.volume - source.volume) <= 1)
            #expect(imported.pan == source.pan)
            let expected = source.notes.filter { !$0.isRest }
            #expect(shape(imported.notes) == shape(expected), "\(source.name)")
        }
        #expect(result.warnings.isEmpty)
    }

    @Test func outputDecodesAsSketchFile() throws {
        let data = MIDIExporter.data(for: SampleData.sketch03())
        let result = try MIDIImporter.convert(data, title: "往復")
        let decoded = try SketchFile.decode(result.file.encoded())
        #expect(decoded.sketch.title == "往復")
        #expect(decoded.formatVersion == SketchFile.currentFormatVersion)
    }
}

@Suite struct MIDIImportQuantizeTests {
    private func convert(_ notes: [(start: Int, length: Int, pitch: UInt8)], division: Int = 480, extra: [(Int, [UInt8])] = [],
                         options: MIDIImportOptions = MIDIImportOptions()) throws -> MIDIImportResult {
        var events: [(Int, [UInt8])] = extra
        for note in notes {
            events.append((note.start, [0x90, note.pitch, 100]))
            events.append((note.start + note.length, [0x80, note.pitch, 0]))
        }
        var builder = SMFBuilder(division: division)
        builder.tracks = [SMFBuilder.track(events)]
        return try MIDIImporter.convert(builder.data, title: "t", options: options)
    }

    @Test func jitteredEighthsSnapToGrid() throws {
        // 8分音符の手弾き：頭が ±20 tick ずれ、長さも短め
        let starts = [0, 250, 470, 730, 955, 1195, 1450, 1690]
        let result = try convert(starts.enumerated().map { (Int($0.element) + ($0.offset == 0 ? 0 : 0), 200, UInt8(60 + $0.offset)) })
        let notes = result.file.sketch.tracks[0].notes
        #expect(notes.map(\.start) == [0, 240, 480, 720, 960, 1200, 1440, 1680])
        #expect(notes.allSatisfy { $0.duration == 240 })
    }

    @Test func tripletsAreDetected() throws {
        // 1拍目は8分3連、2拍目は16分
        let notes: [(Int, Int, UInt8)] = [(0, 150, 60), (165, 150, 62), (318, 150, 64), (480, 110, 65), (600, 110, 67), (720, 220, 69)]
        let track = try convert(notes).file.sketch.tracks[0]
        #expect(track.notes.map(\.start) == [0, 160, 320, 480, 600, 720])
        #expect(track.notes.map(\.duration) == [160, 160, 160, 120, 120, 240])
        let straight = try convert(notes, options: MIDIImportOptions(grid: .sixteenth)).file.sketch.tracks[0]
        #expect(straight.notes.allSatisfy { $0.start % 120 == 0 && $0.duration % 120 == 0 })
    }

    @Test func notesAcrossBarlinesAreTied() throws {
        // 3拍目から2拍半（2小節目の頭へまたぐ）
        let track = try convert([(960, 1200, 60)]).file.sketch.tracks[0]
        #expect(shape(track.notes) == [[960, 960, 60, 1], [1920, 240, 60, 0]])
    }

    @Test func unwritableLengthsAreSplit() throws {
        // 4分＋16分（600 tick）は1つの記号で書けないので 4分＋16分のタイ
        let track = try convert([(0, 600, 60)]).file.sketch.tracks[0]
        #expect(shape(track.notes) == [[0, 480, 60, 1], [480, 120, 60, 0]])
    }

    @Test func legatoOverlapIsTrimmed() throws {
        // 次の音の頭へ少し食い込む（レガート）→ 声部が増えないよう切る
        let track = try convert([(0, 520, 60), (480, 520, 62), (960, 480, 64)]).file.sketch.tracks[0]
        #expect(track.notes.map(\.duration) == [480, 480, 480])
        #expect(Notation.assignVoices(track.notes).voices.count == 1)
    }

    @Test func chordEndsAreUnified() throws {
        // 和音の離し方がばらつく
        let track = try convert([(0, 900, 60), (0, 960, 64), (0, 930, 67)]).file.sketch.tracks[0]
        #expect(track.notes.map(\.duration) == [960, 960, 960])
    }

    @Test func threeLayersAreJoinedIntoChords() throws {
        // 全音符・2分音符・4分音符が同時に始まる → 2声部に収まらないので境目で分けて和音に
        let track = try convert([(0, 1920, 48), (0, 960, 60), (0, 480, 72)]).file.sketch.tracks[0]
        #expect(!Notation.assignVoices(track.notes).overflows)
        #expect(Set(track.notes.map(\.start)) == [0, 480, 960])
        #expect(track.notes.filter { $0.pitch == 48 }.map(\.tiesToNext) == [true, true, false])
    }

    @Test func otherDivisionsAreScaled() throws {
        let track = try convert([(0, 96, 60), (96, 96, 62)], division: 96).file.sketch.tracks[0]
        #expect(track.notes.map(\.start) == [0, 480])
        #expect(track.notes.map(\.duration) == [480, 480])
    }

    @Test func compoundMeterBecomesSameLengthMeter() throws {
        let result = try convert([(0, 480, 60)], extra: [(0, SMFBuilder.meta(0x58, [6, 3, 24, 8]))])
        #expect(result.file.sketch.timeSignature == TimeSignature(beats: 3, beatUnit: 4))
        #expect(result.warnings.contains { $0.contains("6/8") })
    }

    @Test func keySignatureIsRead() throws {
        let minor = try convert([(0, 480, 60)], extra: [(0, SMFBuilder.meta(0x59, [0xFE, 1]))])   // ♭2つ・短調 = G minor
        #expect(minor.file.sketch.key == Key(tonic: 7, mode: .minor))
        let forced = try convert([(0, 480, 60)], extra: [(0, SMFBuilder.meta(0x59, [0xFE, 1]))],
                                 options: MIDIImportOptions(key: Key(tonic: 2, mode: .major)))
        #expect(forced.file.sketch.key == Key(tonic: 2, mode: .major))
    }
}

@Suite struct MIDIImportReaderTests {
    @Test func format0IsSplitByChannelAndDrumsAreSkipped() throws {
        let events: [(Int, [UInt8])] = [
            (0, SMFBuilder.meta(0x03, Array("曲名".utf8))),
            (0, [0xC0, 0]), (0, [0xC1, 33]),
            (0, [0x90, 72, 100]), (480, [0x80, 72, 0]),
            (0, [0x91, 36, 100]), (960, [0x81, 36, 0]),
            (0, [0x99, 36, 100]), (120, [0x89, 36, 0]),
        ]
        var builder = SMFBuilder(format: 0)
        builder.tracks = [SMFBuilder.track(events)]
        let result = try MIDIImporter.convert(builder.data, title: "t")
        let tracks = result.file.sketch.tracks
        #expect(tracks.map(\.name) == ["Piano", "Finger Bass"])
        #expect(tracks.map(\.role) == [.melody, .bass])
        #expect(tracks.map(\.clef) == [.treble, .bass])
        #expect(result.warnings.contains { $0.contains("ドラム") })
    }

    @Test func runningStatusAndZeroVelocityNoteOff() throws {
        // 0x90 を省略し、ベロシティ0で止める
        let track: [UInt8] = [0, 0x90, 60, 100, 0x83, 0x60, 60, 0, 0, 62, 100, 0x83, 0x60, 62, 0, 0, 0xFF, 0x2F, 0]
        var builder = SMFBuilder()
        builder.tracks = [track]
        let notes = try MIDIImporter.convert(builder.data, title: "t").file.sketch.tracks[0].notes
        #expect(shape(notes) == [[0, 480, 60, 0], [480, 480, 62, 0]])
    }

    @Test func shiftJISNamesAndMarkers() throws {
        let name = Array("ピアノ".data(using: .shiftJIS)!)
        let marker = Array("サビ".data(using: .shiftJIS)!)
        let events: [(Int, [UInt8])] = [
            (0, SMFBuilder.meta(0x03, name)),
            (1920 * 2, SMFBuilder.meta(0x06, marker)),
            (0, [0x90, 60, 100]), (480, [0x80, 60, 0]),
            (1920 * 3, [0x90, 62, 100]), (1920 * 3 + 480, [0x80, 62, 0]),
        ]
        var builder = SMFBuilder()
        builder.tracks = [SMFBuilder.track(events)]
        let sketch = try MIDIImporter.convert(builder.data, title: "t").file.sketch
        #expect(sketch.tracks[0].name == "ピアノ")
        #expect(sketch.sections.map(\.name) == ["サビ"])
        #expect(sketch.sections.map(\.startBar) == [3])
        #expect(sketch.barCount == 4)
    }

    @Test func rmidWrapperIsAccepted() throws {
        var builder = SMFBuilder()
        builder.tracks = [SMFBuilder.track([(0, [0x90, 60, 100]), (480, [0x80, 60, 0])])]
        let smf = builder.data
        var rmid = Data("RIFF".utf8) + Data([0, 0, 0, 0]) + Data("RMIDdata".utf8) + Data([0, 0, 0, 0])
        rmid += smf
        #expect(try MIDIImporter.convert(rmid, title: "t").file.sketch.tracks.count == 1)
    }

    @Test func notMIDIThrows() {
        #expect(throws: SMFError.notMIDI) { try SMFReader.read(Data("hello".utf8)) }
    }
}
