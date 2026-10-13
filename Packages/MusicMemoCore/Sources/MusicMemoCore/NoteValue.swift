/// 音価の基本形（入力パレットの全音符〜16分）。
public enum NoteValue: String, CaseIterable, Codable, Sendable {
    case whole
    case half
    case quarter
    case eighth
    case sixteenth

    public var ticks: Tick {
        switch self {
        case .whole: Timing.ticksPerQuarter * 4
        case .half: Timing.ticksPerQuarter * 2
        case .quarter: Timing.ticksPerQuarter
        case .eighth: Timing.ticksPerQuarter / 2
        case .sixteenth: Timing.ticksPerQuarter / 4
        }
    }
}

/// 入力する長さ。基本の音価に付点・3連符を重ねる。
public struct NoteDuration: Hashable, Codable, Sendable {
    public var value: NoteValue
    public var isDotted: Bool
    public var isTriplet: Bool

    public init(_ value: NoteValue, dotted: Bool = false, triplet: Bool = false) {
        self.value = value
        self.isDotted = dotted
        self.isTriplet = triplet
    }

    public var ticks: Tick {
        var ticks = value.ticks
        if isDotted { ticks = ticks * 3 / 2 }
        if isTriplet { ticks = ticks * 2 / 3 }
        return ticks
    }
}
