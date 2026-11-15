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
    /// 2つの声部が重なる小節で、符幹の向きを声部で決めた（連桁でも変えない）。
    public var stemFixed: Bool = false
    /// 同じ位置の別の声部とぶつかるので、右へずらす量（符頭の幅の単位）。
    public var shift: Int = 0
    /// 声部（0 か 1）。
    public var voice: Int = 0

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
        chords(for: notes, clef: clef, key: key, timeSignature: timeSignature, accidentals: nil)
    }

    /// 臨時記号を付けるかどうかの表（開始位置と音高 → 変化量。nil なら付けない）。
    /// 2つの声部をまたいで、小節の中で付いた臨時記号を数える。
    struct AccidentalKey: Hashable {
        var start: Tick
        var pitch: MIDINote
    }

    static func accidentals(for notes: [Note], key: Key, timeSignature: TimeSignature) -> [AccidentalKey: Int?] {
        let signature = KeySignature(key)
        var result: [AccidentalKey: Int?] = [:]
        var currentBar = 0
        var alterations: [Int: Int] = [:]
        for (start, group) in Dictionary(grouping: notes, by: \.start).sorted(by: { $0.key < $1.key }) {
            let bar = timeSignature.bar(containing: start)
            if bar != currentBar {
                currentBar = bar
                alterations = [:]
            }
            for pitch in Set(group.compactMap(\.pitch)).sorted() {
                let spelled = SpelledPitch(pitch, in: key)
                let current = alterations[spelled.diatonicStep] ?? signature.alter(forLetter: spelled.letter)
                result[AccidentalKey(start: start, pitch: pitch)] = spelled.alter == current ? nil : spelled.alter
                alterations[spelled.diatonicStep] = spelled.alter
            }
        }
        return result
    }

    static func chords(for notes: [Note], clef: Clef, key: Key, timeSignature: TimeSignature,
                       accidentals table: [AccidentalKey: Int?]?) -> [NotatedChord] {
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
                var accidental: Int? = spelled.alter == current ? nil : spelled.alter
                if let table, let entry = table[AccidentalKey(start: start, pitch: pitch)] { accidental = entry }
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
            // 2つの声部が重なる小節では、声部で決めた向きを保つ
            let fixed = group.first { chords[$0].stemFixed }.map { chords[$0].stemUp }
            let stemUp = fixed ?? stemDirectionUp(positions: positions)
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

    // MARK: 声部

    /// 音符を声部（最大2つ）に分けた結果。
    public struct VoiceAssignment: Sendable {
        /// 声部ごとの音符（空の声部は含めない。1つ目は必ずある）。
        public var voices: [[Note]]
        /// 2つの声部に収まらなかった（3つ以上の長さが重なった）。収まらない音は2つ目の声部に入れてある。
        public var overflows: Bool
    }

    /// 1つの声部の記譜。
    public struct NotatedVoice: Sendable {
        public var index: Int
        public var chords: [NotatedChord]
        public var beamGroups: [[Int]]
        public var tuplets: [[Int]]
    }

    public static let maxVoices = 2

    /// 音符を声部に分ける。同じ位置・同じ長さの音は1つの和音にまとめ、前から順に空いている声部へ入れる。
    /// 同じ位置で長さが違えば、長い方を先の声部に。タイの続きは、つながる元と同じ声部を優先する。
    public static func assignVoices(_ notes: [Note]) -> VoiceAssignment {
        struct Group { var start: Tick; var duration: Tick; var notes: [Note] }
        let groups = Dictionary(grouping: notes) { [$0.start, $0.duration] }
            .map { Group(start: $0.key[0], duration: $0.key[1], notes: $0.value) }
            .sorted { ($0.start, -$0.duration) < ($1.start, -$1.duration) }

        var voices: [[Note]] = Array(repeating: [], count: maxVoices)
        var voiceEnds: [Tick] = Array(repeating: .min, count: maxVoices)
        var overflows = false
        for group in groups {
            let preferred = (0..<maxVoices).first { voice in
                voices[voice].contains { previous in
                    previous.tiesToNext && previous.end == group.start && group.notes.contains { $0.pitch != nil && $0.pitch == previous.pitch }
                }
            }
            let order = (preferred.map { [$0] } ?? []) + Array(0..<maxVoices)
            let voice: Int
            if let free = order.first(where: { voiceEnds[$0] <= group.start }) {
                voice = free
            } else {
                overflows = true
                voice = maxVoices - 1
            }
            voices[voice] += group.notes
            voiceEnds[voice] = max(voiceEnds[voice], group.start + group.duration)
        }
        return VoiceAssignment(voices: voices.enumerated().filter { $0.offset == 0 || !$0.element.isEmpty }.map(\.element),
                               overflows: overflows)
    }

    /// トラックの音符を声部ごとに記譜する。臨時記号は声部をまたいで数える。
    /// 両方の声部に音符がある小節では、高い方の声部の符幹を上、低い方を下にそろえる。
    /// 同じ位置で2つの声部の符頭が2度以内でぶつかるときは、符幹が下向きの方を右へずらす。
    public static func voices(for notes: [Note], clef: Clef, key: Key, timeSignature: TimeSignature) -> [NotatedVoice] {
        let assignment = assignVoices(notes)
        let table = accidentals(for: notes, key: key, timeSignature: timeSignature)
        var voiceChords = assignment.voices.map {
            chords(for: $0, clef: clef, key: key, timeSignature: timeSignature, accidentals: table)
        }
        for index in voiceChords.indices {
            for chordIndex in voiceChords[index].indices { voiceChords[index][chordIndex].voice = index }
        }

        if voiceChords.count == 2 {
            // 両方の声部に音符がある小節：平均の高さで上下を決める
            let bar = { (tick: Tick) in timeSignature.bar(containing: tick) }
            let bars = Set(voiceChords[0].filter { !$0.isRest }.map { bar($0.start) })
                .intersection(voiceChords[1].filter { !$0.isRest }.map { bar($0.start) })
            for shared in bars {
                let average = voiceChords.map { chords -> Double in
                    let pitches = chords.filter { bar($0.start) == shared }.flatMap { $0.heads.map(\.pitch) }
                    return Double(pitches.reduce(0, +)) / Double(max(pitches.count, 1))
                }
                let upper = average[1] > average[0] ? 1 : 0
                for voice in 0..<2 {
                    for index in voiceChords[voice].indices where bar(voiceChords[voice][index].start) == shared {
                        voiceChords[voice][index].stemUp = voice == upper
                        voiceChords[voice][index].stemFixed = true
                        for head in voiceChords[voice][index].heads.indices { voiceChords[voice][index].heads[head].isDisplaced = false }
                        displaceSeconds(&voiceChords[voice][index].heads, stemUp: voice == upper)
                    }
                }
            }
        }

        var result = voiceChords.enumerated().map { index, chords -> NotatedVoice in
            var chords = chords
            let beams = beamGroups(&chords, timeSignature: timeSignature)
            return NotatedVoice(index: index, chords: chords, beamGroups: beams, tuplets: tupletGroups(chords))
        }

        if result.count == 2 {
            // 同じ位置でぶつかる符頭：符幹が下向きの声部を右へ
            let starts = Dictionary(result[0].chords.enumerated().map { ($0.element.start, $0.offset) }, uniquingKeysWith: { a, _ in a })
            for index in result[1].chords.indices {
                let other = result[1].chords[index]
                guard let mine = starts[other.start], !other.isRest, !result[0].chords[mine].isRest else { continue }
                let collides = result[0].chords[mine].heads.contains { a in other.heads.contains { abs(a.staffPosition - $0.staffPosition) <= 1 } }
                guard collides else { continue }
                if result[1].chords[index].stemUp {
                    result[0].chords[mine].shift = 1
                } else {
                    result[1].chords[index].shift = 1
                }
            }
        }
        return result
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
