/// 時間の位置。4分音符 = 480 tick（3連符も整数で表せる）。曲頭が 0。
public typealias Tick = Int

public enum Timing {
    public static let ticksPerQuarter: Tick = 480
    public static let ticksPerSixteenth: Tick = ticksPerQuarter / 4
}

/// 拍子。拍子記号は曲頭のみなので曲に1つだけ持つ。
public struct TimeSignature: Hashable, Codable, Sendable {
    public var beats: Int
    public var beatUnit: Int

    public init(beats: Int, beatUnit: Int) {
        self.beats = beats
        self.beatUnit = beatUnit
    }

    public static let common = TimeSignature(beats: 4, beatUnit: 4)

    public var ticksPerBeat: Tick { Timing.ticksPerQuarter * 4 / beatUnit }
    public var ticksPerBar: Tick { ticksPerBeat * beats }

    /// 小節の先頭 tick（小節番号は1始まり）。
    public func startTick(ofBar bar: Int) -> Tick {
        (bar - 1) * ticksPerBar
    }

    /// tick が含まれる小節番号（1始まり）。
    public func bar(containing tick: Tick) -> Int {
        tick / ticksPerBar + 1
    }

    public func position(of tick: Tick) -> BarPosition {
        let inBar = tick % ticksPerBar
        let inBeat = inBar % ticksPerBeat
        return BarPosition(
            bar: tick / ticksPerBar + 1,
            beat: inBar / ticksPerBeat + 1,
            sixteenth: inBeat / Timing.ticksPerSixteenth + 1,
            remainder: inBeat % Timing.ticksPerSixteenth
        )
    }

    public func tick(of position: BarPosition) -> Tick {
        startTick(ofBar: position.bar)
            + (position.beat - 1) * ticksPerBeat
            + (position.sixteenth - 1) * Timing.ticksPerSixteenth
            + position.remainder
    }
}

/// 「小節 . 拍 . 16分」の位置。いずれも1始まり。16分より細かい端数は remainder（tick）に持つ。
public struct BarPosition: Hashable, Codable, Sendable {
    public var bar: Int
    public var beat: Int
    public var sixteenth: Int
    public var remainder: Tick

    public init(bar: Int, beat: Int = 1, sixteenth: Int = 1, remainder: Tick = 0) {
        self.bar = bar
        self.beat = beat
        self.sixteenth = sixteenth
        self.remainder = remainder
    }

    /// 「7.1.1」形式（ルーラ左列の現在位置）。
    public var description: String { "\(bar).\(beat).\(sixteenth)" }

    /// 「6.1」形式（再生範囲の表示）。
    public var barBeatDescription: String { "\(bar).\(beat)" }
}
