/// 和音の1つの符頭。
public struct NotatedHead: Hashable, Sendable {
    public var pitch: MIDINote
    /// 五線上の位置（第1線 = 0）。
    public var staffPosition: Int
    /// 付ける臨時記号の変化量（♯ = +1、♭ = -1、ナチュラル = 0）。nil なら付けない。
    public var accidental: Int?
    /// 長2度でぶつかるため符幹の反対側にずらすか。
    public var isDisplaced: Bool
    /// 次の同じ音高の音へタイでつなぐか。
    public var tiesToNext: Bool = false
}

/// 同じ開始位置の音符をまとめたもの（単音・和音・休符）。
public struct NotatedChord: Hashable, Sendable {
    public var start: Tick
    /// 終わりの位置（タイの行き先を探すのに使う）。
    public var end: Tick
    public var value: NoteDuration
    /// 低い順。休符なら空。
    public var heads: [NotatedHead]
    public var stemUp: Bool

    public var isRest: Bool { heads.isEmpty }

    /// 必要な加線の位置（偶数＝線の位置）。
    public var ledgerLinePositions: [Int] {
        guard let lowest = heads.first?.staffPosition, let highest = heads.last?.staffPosition else { return [] }
        var positions: [Int] = []
        if lowest <= -2 { positions += stride(from: -2, through: lowest, by: -2) }
        if highest >= 10 { positions += stride(from: 10, through: highest, by: 2) }
        return positions
    }
}

public enum Notation {
    /// 第3線（真ん中の線）の位置。
    public static let middleLine = 4

    /// トラックの音符を記譜用に変換する。開始位置順。
    public static func chords(for notes: [Note], clef: Clef, key: Key, timeSignature: TimeSignature) -> [NotatedChord] {
        let signature = KeySignature(key)
        let groups = Dictionary(grouping: notes, by: \.start).sorted { $0.key < $1.key }

        var result: [NotatedChord] = []
        var currentBar = 0
        // 小節内で付いた臨時記号の状態（段数 → 変化量）。小節が変わるとリセット。
        var alterations: [Int: Int] = [:]

        for (start, group) in groups {
            let bar = timeSignature.bar(containing: start)
            if bar != currentBar {
                currentBar = bar
                alterations = [:]
            }
            let duration = group.map(\.duration).max() ?? 0
            let value = NoteDuration(ticks: duration)
            let pitches = Set(group.compactMap(\.pitch)).sorted()

            guard !pitches.isEmpty else {
                result.append(NotatedChord(start: start, end: start + duration, value: value, heads: [], stemUp: true))
                continue
            }

            let tiedPitches = Set(group.filter(\.tiesToNext).compactMap(\.pitch))
            var heads: [NotatedHead] = pitches.map { pitch in
                let spelled = SpelledPitch(pitch, in: key)
                let step = spelled.diatonicStep
                let current = alterations[step] ?? signature.alter(forLetter: spelled.letter)
                let accidental: Int? = spelled.alter == current ? nil : spelled.alter
                alterations[step] = spelled.alter
                return NotatedHead(pitch: pitch, staffPosition: clef.staffPosition(of: spelled), accidental: accidental,
                                   isDisplaced: false, tiesToNext: tiedPitches.contains(pitch))
            }

            let stemUp = stemDirectionUp(positions: heads.map(\.staffPosition))
            displaceSeconds(&heads, stemUp: stemUp)
            result.append(NotatedChord(start: start, end: start + duration, value: value, heads: heads, stemUp: stemUp))
        }
        return result
    }

    /// 連桁でつなぐ音符のまとまり（chords の添字）。同じ拍の中で続く8分・16分（休符で区切る）を2つ以上まとめる。
    /// まとまりの符幹の向きは、まとまり全体で真ん中の線から一番遠い音で決め、各音符に反映する。
    public static func beamGroups(_ chords: inout [NotatedChord], timeSignature: TimeSignature) -> [[Int]] {
        var groups: [[Int]] = []
        var current: [Int] = []
        var currentBeat: Int?

        func flush() {
            if current.count >= 2 { groups.append(current) }
            current = []
            currentBeat = nil
        }

        for (index, chord) in chords.enumerated() {
            let beamable = !chord.isRest && chord.value.flagCount > 0
            guard beamable else {
                flush()
                continue
            }
            let beat = chord.start / timeSignature.ticksPerBeat
            let continues = currentBeat == beat && current.last.map { chords[$0].end == chord.start } == true
            if !continues { flush() }
            current.append(index)
            currentBeat = beat
        }
        flush()

        for group in groups {
            let positions = group.flatMap { chords[$0].heads.map(\.staffPosition) }
            let stemUp = stemDirectionUp(positions: positions)
            for index in group {
                chords[index].stemUp = stemUp
                for headIndex in chords[index].heads.indices { chords[index].heads[headIndex].isDisplaced = false }
                displaceSeconds(&chords[index].heads, stemUp: stemUp)
            }
        }
        return groups
    }

    /// 3連符のまとまり（chords の添字）。続く3連符を、合計が元の音価2つ分になるごとに区切る。
    public static func tupletGroups(_ chords: [NotatedChord]) -> [[Int]] {
        var groups: [[Int]] = []
        var current: [Int] = []
        var total: Tick = 0
        for (index, chord) in chords.enumerated() {
            guard chord.value.isTriplet, current.isEmpty || chords[current.last!].end == chord.start else {
                current = []
                total = 0
                if chord.value.isTriplet { current = [index]; total = chord.value.ticks }
                continue
            }
            current.append(index)
            total += chord.value.ticks
            let span = chords[current[0]].value.value.ticks * 2
            if total >= span {
                groups.append(current)
                current = []
                total = 0
            }
        }
        return groups
    }

    /// 真ん中の線から一番遠い音で決める。真ん中の線上や上下同じ距離なら下向き。
    static func stemDirectionUp(positions: [Int]) -> Bool {
        guard let lowest = positions.min(), let highest = positions.max() else { return true }
        return middleLine - lowest > highest - middleLine
    }

    /// 長2度で隣り合う符頭を、符幹の反対側にずらす。符幹が上向きなら下から、下向きなら上から数える。
    static func displaceSeconds(_ heads: inout [NotatedHead], stemUp: Bool) {
        let order = stemUp ? Array(heads.indices) : Array(heads.indices.reversed())
        var previous: (position: Int, displaced: Bool)?
        for index in order {
            let position = heads[index].staffPosition
            if let previous, abs(position - previous.position) == 1, !previous.displaced {
                heads[index].isDisplaced = true
            }
            previous = (position, heads[index].isDisplaced)
        }
    }
}
