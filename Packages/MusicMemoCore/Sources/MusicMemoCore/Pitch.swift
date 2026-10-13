/// MIDIノート番号。C4 = 60。
public typealias MIDINote = Int

/// ピッチクラス。C = 0 … B = 11。
public typealias PitchClass = Int

public enum Pitch {
    static let sharpNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    static let flatNames = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
    static let letterPitchClasses: [Character: PitchClass] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]

    public static func pitchClass(of note: MIDINote) -> PitchClass {
        mod12(note)
    }

    /// 科学的音名のオクターブ（C4 = 60）。
    public static func octave(of note: MIDINote) -> Int {
        Int((Double(note) / 12).rounded(.down)) - 1
    }

    public static func name(of pitchClass: PitchClass, preferFlats: Bool = false) -> String {
        (preferFlats ? flatNames : sharpNames)[mod12(pitchClass)]
    }

    /// 「C4」形式。
    public static func noteName(_ note: MIDINote, preferFlats: Bool = false) -> String {
        name(of: pitchClass(of: note), preferFlats: preferFlats) + String(octave(of: note))
    }

    /// 「C」「F#」「Bb」「E♭」などの音名をピッチクラスにする。
    public static func pitchClass(named name: Substring) -> PitchClass? {
        guard let letter = name.first, let base = letterPitchClasses[letter] else { return nil }
        let rest = name.dropFirst()
        switch rest {
        case "": return base
        case "#", "♯": return mod12(base + 1)
        case "b", "♭": return mod12(base - 1)
        default: return nil
        }
    }

    static func mod12(_ n: Int) -> Int {
        ((n % 12) + 12) % 12
    }
}
