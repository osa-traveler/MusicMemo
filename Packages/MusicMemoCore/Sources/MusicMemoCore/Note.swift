import Foundation

/// 音符または休符。同じ開始位置に複数の音符を置くと和音になる。
public struct Note: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var start: Tick
    public var duration: Tick
    /// 音高。nil なら休符。
    public var pitch: MIDINote?
    /// 次の同じ音高の音符へタイで繋ぐか。
    public var tiesToNext: Bool

    public init(id: UUID = UUID(), start: Tick, duration: Tick, pitch: MIDINote?, tiesToNext: Bool = false) {
        self.id = id
        self.start = start
        self.duration = duration
        self.pitch = pitch
        self.tiesToNext = tiesToNext
    }

    public static func rest(id: UUID = UUID(), start: Tick, duration: Tick) -> Note {
        Note(id: id, start: start, duration: duration, pitch: nil)
    }

    public var isRest: Bool { pitch == nil }
    public var end: Tick { start + duration }
}
