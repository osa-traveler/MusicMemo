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

/// 音符の長さの書き方。基本の音価に付点・3連符を重ねる（入力パレットの選択と譜面の記号の両方に使う）。
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

    /// 長さに一致する書き方。付点 → 3連符の順に探し、無ければ長さを超えない最大の音価。
    /// （1つの記号で書けない長さをタイで分けるのは入力の段階で扱う）
    public init(ticks: Tick) {
        let candidates = NoteValue.allCases.flatMap { value in
            [NoteDuration(value), NoteDuration(value, dotted: true), NoteDuration(value, triplet: true)]
        }
        if let exact = candidates.first(where: { $0.ticks == ticks }) {
            self = exact
        } else {
            self = candidates
                .filter { $0.ticks <= ticks && !$0.isTriplet }
                .max { $0.ticks < $1.ticks } ?? NoteDuration(.sixteenth)
        }
    }

    public var hasStem: Bool { value != .whole }

    /// 旗の本数。
    public var flagCount: Int {
        switch value {
        case .eighth: 1
        case .sixteenth: 2
        default: 0
        }
    }
}
