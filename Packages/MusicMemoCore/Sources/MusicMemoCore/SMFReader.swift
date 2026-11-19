import Foundation

/// Standard MIDI File の中身（読み取った結果）。tick は元のファイルの分解能のまま。
public struct SMFFile: Sendable {
    public var format: Int
    /// 4分音符あたりの tick。
    public var ticksPerQuarter: Int
    public var tracks: [SMFTrack]
}

public struct SMFTrack: Sendable {
    public var events: [SMFEvent]
}

public struct SMFEvent: Sendable, Equatable {
    public var tick: Int
    public var kind: Kind

    public enum Kind: Sendable, Equatable {
        case noteOn(channel: Int, pitch: Int, velocity: Int)
        case noteOff(channel: Int, pitch: Int)
        case controlChange(channel: Int, controller: Int, value: Int)
        case programChange(channel: Int, program: Int)
        /// メタイベント（0xFF）。種類と中身のバイト列。
        case meta(type: Int, data: [UInt8])
        /// それ以外（アフタータッチ、ピッチベンド、SysEx など）。変換には使わない。
        case other
    }
}

public enum SMFError: Error, CustomStringConvertible, Equatable {
    case notMIDI
    case truncated
    case smpteTimingUnsupported

    public var description: String {
        switch self {
        case .notMIDI: "MIDI ファイルではありません（MThd が見つからない）"
        case .truncated: "ファイルが途中で切れています"
        case .smpteTimingUnsupported: "SMPTE（時間）単位の MIDI ファイルには対応していません"
        }
    }
}

/// SMF（フォーマット0／1）の読み取り。ランニングステータス、RIFF（RMID）で包んだファイルにも対応する。
public enum SMFReader {
    public static func read(_ data: Data) throws -> SMFFile {
        let bytes = [UInt8](data)
        // RMID や、先頭に余分なデータがあるファイルもあるので MThd を探す
        guard let headerStart = find(Array("MThd".utf8), in: bytes) else { throw SMFError.notMIDI }
        var reader = ByteReader(bytes: bytes, position: headerStart + 4)
        let headerLength = try reader.uint32()
        let format = try reader.uint16()
        let trackCount = try reader.uint16()
        let division = try reader.uint16()
        reader.position = headerStart + 8 + headerLength
        guard division & 0x8000 == 0 else { throw SMFError.smpteTimingUnsupported }
        guard division > 0 else { throw SMFError.notMIDI }

        var tracks: [SMFTrack] = []
        while tracks.count < trackCount, reader.position + 8 <= bytes.count {
            let chunkID = try reader.bytes(4)
            let length = try reader.uint32()
            let end = min(reader.position + length, bytes.count)
            if chunkID == Array("MTrk".utf8) {
                tracks.append(SMFTrack(events: try readTrack(&reader, end: end)))
            }
            reader.position = end
        }
        return SMFFile(format: format, ticksPerQuarter: division, tracks: tracks)
    }

    private static func readTrack(_ reader: inout ByteReader, end: Int) throws -> [SMFEvent] {
        var events: [SMFEvent] = []
        var tick = 0
        var runningStatus: UInt8?
        while reader.position < end {
            tick += try reader.variableLength()
            guard reader.position < end else { break }
            var status = try reader.byte()
            var firstData: UInt8?
            if status < 0x80 {
                // ランニングステータス：直前のステータスを使い、読んだバイトはデータ
                guard let running = runningStatus else { throw SMFError.truncated }
                firstData = status
                status = running
            }

            switch status {
            case 0xFF:
                let type = Int(try reader.byte())
                let length = try reader.variableLength()
                let data = try reader.bytes(length)
                events.append(SMFEvent(tick: tick, kind: .meta(type: type, data: data)))
                if type == 0x2F { return events }  // トラックの終わり
            case 0xF0, 0xF7:
                let length = try reader.variableLength()
                _ = try reader.bytes(length)
                events.append(SMFEvent(tick: tick, kind: .other))
            default:
                guard status >= 0x80, status < 0xF0 else { throw SMFError.truncated }
                runningStatus = status
                let channel = Int(status & 0x0F)
                let data1 = Int(try firstData ?? reader.byte())
                let kind: SMFEvent.Kind
                switch status & 0xF0 {
                case 0x80:
                    _ = try reader.byte()
                    kind = .noteOff(channel: channel, pitch: data1)
                case 0x90:
                    let velocity = Int(try reader.byte())
                    kind = velocity == 0 ? .noteOff(channel: channel, pitch: data1) : .noteOn(channel: channel, pitch: data1, velocity: velocity)
                case 0xB0:
                    kind = .controlChange(channel: channel, controller: data1, value: Int(try reader.byte()))
                case 0xC0:
                    kind = .programChange(channel: channel, program: data1)
                case 0xD0:
                    kind = .other
                default:  // 0xA0 アフタータッチ、0xE0 ピッチベンド
                    _ = try reader.byte()
                    kind = .other
                }
                events.append(SMFEvent(tick: tick, kind: kind))
            }
        }
        return events
    }

    private static func find(_ pattern: [UInt8], in bytes: [UInt8]) -> Int? {
        guard bytes.count >= pattern.count else { return nil }
        return (0...(bytes.count - pattern.count)).first { Array(bytes[$0..<($0 + pattern.count)]) == pattern }
    }

    /// メタイベントの文字（トラック名・マーカー）。UTF-8 → Shift_JIS（古い日本の MIDI に多い）→ Latin-1 の順に試す。
    public static func text(_ data: [UInt8]) -> String {
        let trimmed = Array(data.prefix { $0 != 0 })
        let string = String(bytes: trimmed, encoding: .utf8)
            ?? String(bytes: trimmed, encoding: .shiftJIS)
            ?? String(bytes: trimmed, encoding: .isoLatin1)
            ?? ""
        return string.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ByteReader {
    let bytes: [UInt8]
    var position: Int

    mutating func byte() throws -> UInt8 {
        guard position < bytes.count else { throw SMFError.truncated }
        defer { position += 1 }
        return bytes[position]
    }

    mutating func bytes(_ count: Int) throws -> [UInt8] {
        guard count >= 0, position + count <= bytes.count else { throw SMFError.truncated }
        defer { position += count }
        return Array(bytes[position..<(position + count)])
    }

    mutating func uint16() throws -> Int {
        let b = try bytes(2)
        return Int(b[0]) << 8 | Int(b[1])
    }

    mutating func uint32() throws -> Int {
        let b = try bytes(4)
        return Int(b[0]) << 24 | Int(b[1]) << 16 | Int(b[2]) << 8 | Int(b[3])
    }

    mutating func variableLength() throws -> Int {
        var value = 0
        for _ in 0..<4 {
            let b = try byte()
            value = value << 7 | Int(b & 0x7F)
            if b & 0x80 == 0 { return value }
        }
        return value
    }
}
