/// 音名の綴り（幹音＋変化記号）。
public struct SpelledPitch: Hashable, Sendable {
    /// 幹音（C=0, D=1 … B=6）。
    public var letter: Int
    /// 変化（♯=+1, ♭=-1）。
    public var alter: Int
    public var octave: Int

    public init(letter: Int, alter: Int, octave: Int) {
        self.letter = letter
        self.alter = alter
        self.octave = octave
    }

    /// C0 から数えた幹音の段数。五線上の位置の計算に使う。
    public var diatonicStep: Int { octave * 7 + letter }

    static let letterPitchClasses = [0, 2, 4, 5, 7, 9, 11]

    /// 調に合わせて綴る。調の音階音は調号どおり、それ以外は調の向き（♯系／♭系）に合わせる。
    public init(_ note: MIDINote, in key: Key) {
        let signature = KeySignature(key)
        let pc = Pitch.pitchClass(of: note)
        let candidates: [(letter: Int, alter: Int)] = (0..<7).compactMap { letter in
            let diff = Pitch.mod12(pc - Self.letterPitchClasses[letter])
            let alter = diff > 6 ? diff - 12 : diff
            return abs(alter) <= 1 ? (letter, alter) : nil
        }
        let chosen = candidates.first { signature.alter(forLetter: $0.letter) == $0.alter }
            ?? candidates.first { $0.alter == 0 }
            ?? candidates.first { key.prefersFlats ? $0.alter < 0 : $0.alter > 0 }
            ?? candidates[0]
        let octave = (note - Self.letterPitchClasses[chosen.letter] - chosen.alter) / 12 - 1
        self.init(letter: chosen.letter, alter: chosen.alter, octave: octave)
    }
}

/// 調号。fifths が正なら♯の数、負なら♭の数。
public struct KeySignature: Hashable, Sendable {
    public var fifths: Int

    /// ♯が付く順（F C G D A E B）と♭が付く順（B E A D G C F）の幹音。
    static let sharpOrder = [3, 0, 4, 1, 5, 2, 6]
    static let flatOrder = [6, 2, 5, 1, 4, 0, 3]

    public init(fifths: Int) {
        self.fifths = fifths
    }

    public init(_ key: Key) {
        let majorTonic = key.mode == .major ? key.tonic : Pitch.mod12(key.tonic + 3)
        // 長調の主音 → 五度圏上の位置（-5…+6）
        let table: [PitchClass: Int] = [0: 0, 7: 1, 2: 2, 9: 3, 4: 4, 11: 5, 6: 6, 5: -1, 10: -2, 3: -3, 8: -4, 1: -5]
        self.init(fifths: table[majorTonic] ?? 0)
    }

    /// 調号の記号を付ける幹音（付ける順）。
    public var letters: [Int] {
        fifths >= 0 ? Array(Self.sharpOrder.prefix(fifths)) : Array(Self.flatOrder.prefix(-fifths))
    }

    public var accidentalAlter: Int { fifths >= 0 ? 1 : -1 }

    public func alter(forLetter letter: Int) -> Int {
        letters.contains(letter) ? accidentalAlter : 0
    }

    /// 調号の各記号の五線上の位置（第1線 = 0、1段 = 線と間の1つ分）。
    public func staffPositions(for clef: Clef) -> [Int] {
        // ト音記号での位置。ヘ音記号は2段下がる。
        let treble = fifths >= 0 ? [8, 5, 9, 6, 3, 7, 4] : [4, 7, 3, 6, 2, 5, 1]
        let shift = clef == .bass ? -2 : 0
        return treble.prefix(abs(fifths)).map { $0 + shift }
    }
}

extension Clef {
    /// 第1線（一番下の線）の音の段数。ト音記号は E4、ヘ音記号は G2。
    var bottomLineStep: Int {
        switch self {
        case .treble: 4 * 7 + 2
        case .bass: 2 * 7 + 4
        }
    }

    /// 綴った音の五線上の位置（第1線 = 0、第5線 = 8。負は下、8超は上）。
    public func staffPosition(of pitch: SpelledPitch) -> Int {
        pitch.diatonicStep - bottomLineStep
    }
}
