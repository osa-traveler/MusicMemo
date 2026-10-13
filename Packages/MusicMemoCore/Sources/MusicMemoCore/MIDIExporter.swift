import Foundation

/// Standard MIDI File（フォーマット1、4分音符 = 480 tick）への書き出し。
/// 1本目はテンポ・拍子・調号・セクション名（マーカー）、2本目以降は楽器ごとのトラック。
/// タイでつながった音は1つの長い音にまとめる。ミュート中のトラックも書き出す。
public enum MIDIExporter {
    static let velocity: UInt8 = 90

    public static func data(for sketch: Sketch) -> Data {
        var data = Data()
        data.append(contentsOf: Array("MThd".utf8))
        data.append(uint32: 6)
        data.append(uint16: 1)                                   // フォーマット1
        data.append(uint16: UInt16(1 + sketch.tracks.count))
        data.append(uint16: UInt16(Timing.ticksPerQuarter))

        data.append(chunk: conductorTrack(sketch))
        for (index, track) in sketch.tracks.enumerated() {
            data.append(chunk: instrumentTrack(track, channel: channel(forTrackAt: index)))
        }
        return data
    }

    /// トラックごとのチャンネル。10ch（ドラム）は飛ばす。
    static func channel(forTrackAt index: Int) -> UInt8 {
        let channel = index % 15
        return UInt8(channel >= 9 ? channel + 1 : channel)
    }

    // MARK: トラック

    private static func conductorTrack(_ sketch: Sketch) -> [UInt8] {
        var events: [Event] = []
        events.append(Event(tick: 0, order: 0, bytes: meta(0x03, Array(sketch.title.utf8))))

        let microseconds = UInt32((60_000_000 / sketch.tempo).rounded())
        events.append(Event(tick: 0, order: 0, bytes: meta(0x51, [UInt8(microseconds >> 16 & 0xFF), UInt8(microseconds >> 8 & 0xFF), UInt8(microseconds & 0xFF)])))

        let time = sketch.timeSignature
        let denominatorPower = UInt8(log2(Double(time.beatUnit)))
        events.append(Event(tick: 0, order: 0, bytes: meta(0x58, [UInt8(time.beats), denominatorPower, 24, 8])))

        let fifths = KeySignature(sketch.key).fifths
        events.append(Event(tick: 0, order: 0, bytes: meta(0x59, [UInt8(bitPattern: Int8(fifths)), sketch.key.mode == .minor ? 1 : 0])))

        for section in sketch.sections {
            events.append(Event(tick: time.startTick(ofBar: section.startBar), order: 1, bytes: meta(0x06, Array(section.name.utf8))))
        }
        return encode(events)
    }

    private static func instrumentTrack(_ track: Track, channel: UInt8) -> [UInt8] {
        var events: [Event] = [
            Event(tick: 0, order: 0, bytes: meta(0x03, Array(track.name.utf8))),
            Event(tick: 0, order: 0, bytes: [0xC0 | channel, UInt8(clamping: track.program)]),
            Event(tick: 0, order: 0, bytes: [0xB0 | channel, 7, UInt8(track.volume * 127 / 100)]),
            Event(tick: 0, order: 0, bytes: [0xB0 | channel, 10, UInt8(clamping: track.pan + 64)]),
        ]
        for note in mergedNotes(track.notes) {
            guard let pitch = note.pitch else { continue }
            // 同じ位置では音を止めてから鳴らす（order 1 → 2）
            events.append(Event(tick: note.start, order: 2, bytes: [0x90 | channel, UInt8(clamping: pitch), velocity]))
            events.append(Event(tick: note.end, order: 1, bytes: [0x80 | channel, UInt8(clamping: pitch), 0]))
        }
        return encode(events)
    }

    /// タイでつながった同じ音高の音を1つにまとめる。
    public static func mergedNotes(_ notes: [Note]) -> [Note] {
        let sorted = notes.sorted { ($0.start, $0.pitch ?? -1) < ($1.start, $1.pitch ?? -1) }
        var result: [Note] = []
        var consumed = Set<Int>()
        for (index, note) in sorted.enumerated() where !consumed.contains(index) {
            var merged = note
            var current = note
            while current.tiesToNext,
                  let nextIndex = sorted.indices.first(where: { !consumed.contains($0) && $0 != index
                      && sorted[$0].start == current.end && sorted[$0].pitch == current.pitch }) {
                consumed.insert(nextIndex)
                current = sorted[nextIndex]
                merged.duration = current.end - merged.start
            }
            merged.tiesToNext = false
            result.append(merged)
        }
        return result
    }

    // MARK: バイト列

    private struct Event {
        var tick: Tick
        var order: Int
        var bytes: [UInt8]
    }

    private static func meta(_ type: UInt8, _ payload: [UInt8]) -> [UInt8] {
        [0xFF, type] + variableLength(payload.count) + payload
    }

    private static func encode(_ events: [Event]) -> [UInt8] {
        let sorted = events.enumerated().sorted { ($0.element.tick, $0.element.order, $0.offset) < ($1.element.tick, $1.element.order, $1.offset) }
        var bytes: [UInt8] = []
        var last: Tick = 0
        for (_, event) in sorted {
            bytes += variableLength(event.tick - last) + event.bytes
            last = event.tick
        }
        bytes += [0x00, 0xFF, 0x2F, 0x00]  // トラックの終わり
        return bytes
    }

    /// 可変長数値（7ビットずつ、続きがあれば最上位ビットを立てる）。
    static func variableLength(_ value: Int) -> [UInt8] {
        var value = max(value, 0)
        var bytes = [UInt8(value & 0x7F)]
        value >>= 7
        while value > 0 {
            bytes.insert(UInt8(value & 0x7F) | 0x80, at: 0)
            value >>= 7
        }
        return bytes
    }
}

private extension Data {
    mutating func append(uint16 value: UInt16) {
        append(contentsOf: [UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    mutating func append(uint32 value: UInt32) {
        append(contentsOf: [UInt8(value >> 24), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
    }

    mutating func append(chunk: [UInt8]) {
        append(contentsOf: Array("MTrk".utf8))
        append(uint32: UInt32(chunk.count))
        append(contentsOf: chunk)
    }
}
