import Foundation
import Testing
@testable import MusicMemoCore

/// テスト用の最小限の SMF 読み取り。
private struct ParsedMIDI {
    struct Event { var tick: Int; var bytes: [UInt8] }
    var format = 0, division = 0
    var tracks: [[Event]] = []

    init(_ data: Data) {
        let bytes = [UInt8](data)
        var i = 0
        func u32() -> Int { defer { i += 4 }; return Int(bytes[i]) << 24 | Int(bytes[i+1]) << 16 | Int(bytes[i+2]) << 8 | Int(bytes[i+3]) }
        func u16() -> Int { defer { i += 2 }; return Int(bytes[i]) << 8 | Int(bytes[i+1]) }
        func vlq() -> Int { var v = 0; while true { let b = bytes[i]; i += 1; v = v << 7 | Int(b & 0x7F); if b & 0x80 == 0 { return v } } }
        precondition(String(decoding: bytes[0..<4], as: UTF8.self) == "MThd"); i = 4
        _ = u32(); format = u16(); let count = u16(); division = u16()
        for _ in 0..<count {
            precondition(String(decoding: bytes[i..<i+4], as: UTF8.self) == "MTrk"); i += 4
            let end = u32() + i
            var tick = 0, events: [Event] = []
            while i < end {
                tick += vlq()
                let status = bytes[i]
                if status == 0xFF {
                    let start = i; i += 2; let length = vlq(); i += length
                    events.append(Event(tick: tick, bytes: Array(bytes[start..<i])))
                } else {
                    let length = (status & 0xF0) == 0xC0 ? 2 : 3
                    events.append(Event(tick: tick, bytes: Array(bytes[i..<i+length]))); i += length
                }
            }
            tracks.append(events)
        }
    }

    func meta(_ type: UInt8, in track: Int) -> [Event] {
        tracks[track].filter { $0.bytes.count >= 2 && $0.bytes[0] == 0xFF && $0.bytes[1] == type }
    }
}

struct MIDIExporterTests {
    @Test func header() {
        let midi = ParsedMIDI(MIDIExporter.data(for: SampleData.sketch03()))
        #expect(midi.format == 1)
        #expect(midi.division == 480)
        #expect(midi.tracks.count == 5)  // 1 + 4トラック
    }

    @Test func conductorTrack() {
        let midi = ParsedMIDI(MIDIExporter.data(for: SampleData.sketch03()))
        // ♩=96 → 625000 µs
        #expect(midi.meta(0x51, in: 0).first?.bytes == [0xFF, 0x51, 3, 0x09, 0x89, 0x68])
        #expect(midi.meta(0x58, in: 0).first?.bytes == [0xFF, 0x58, 4, 4, 2, 24, 8])
        #expect(midi.meta(0x59, in: 0).first?.bytes == [0xFF, 0x59, 2, 0, 0])
        let markers = midi.meta(0x06, in: 0)
        #expect(markers.map(\.tick) == [0, 1920 * 8])
        #expect(markers.map { String(decoding: $0.bytes.dropFirst(3), as: UTF8.self) } == ["Aメロ", "サビ"])
    }

    @Test func instrumentTrack() {
        let midi = ParsedMIDI(MIDIExporter.data(for: SampleData.sketch03()))
        let bass = midi.tracks[3]
        #expect(String(decoding: midi.meta(0x03, in: 3)[0].bytes.dropFirst(3), as: UTF8.self) == "Finger Bass")
        #expect(bass.contains { $0.bytes == [0xC2, 33] })              // 音色
        #expect(bass.contains { $0.bytes == [0xB2, 7, 91] })              // 音量 72 → 91/127
        let noteOns = bass.filter { $0.bytes[0] == 0x92 }
        #expect(noteOns.first.map { [$0.tick, Int($0.bytes[1])] } == [1920 * 4, 52])  // 5小節目 E3
        #expect(noteOns.count == 8)
    }

    @Test func tiesAreMerged() {
        var sketch = Sketch(title: "T", barCount: 2)
        var track = Track(name: "Lead", role: .melody, color: .blue)
        NoteEditing.enter(pitches: [65], at: 1440, duration: 960, in: &track, timeSignature: sketch.timeSignature, totalTicks: sketch.totalTicks)
        sketch.tracks = [track]
        let events = ParsedMIDI(MIDIExporter.data(for: sketch)).tracks[1]
        let on = events.filter { $0.bytes[0] == 0x90 }
        let off = events.filter { $0.bytes[0] == 0x80 }
        #expect(on.map(\.tick) == [1440])
        #expect(off.map(\.tick) == [2400])  // 4分＋4分のタイが1つの2分音符に
    }

    @Test func mutedTracksAreExported() {
        var sketch = SampleData.sketch03()
        sketch.tracks[0].isMuted = true
        #expect(ParsedMIDI(MIDIExporter.data(for: sketch)).tracks.count == 5)
    }

    @Test func channelsSkipDrums() {
        #expect((0..<11).map { MIDIExporter.channel(forTrackAt: $0) } == [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11])
    }

    @Test func variableLength() {
        #expect(MIDIExporter.variableLength(0) == [0x00])
        #expect(MIDIExporter.variableLength(0x7F) == [0x7F])
        #expect(MIDIExporter.variableLength(0x80) == [0x81, 0x00])
        #expect(MIDIExporter.variableLength(1920) == [0x8F, 0x00])
    }
}
