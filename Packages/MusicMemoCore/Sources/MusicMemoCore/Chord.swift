import Foundation

/// コードの質。rawValue はコードネームでの表記。
public enum ChordQuality: String, CaseIterable, Codable, Sendable {
    case major = ""
    case minor = "m"
    case dominant7 = "7"
    case major7 = "maj7"
    case minor7 = "m7"
    case diminished = "dim"
    case augmented = "aug"
    case sus4
    case sus2
    case sixth = "6"
    case minor6 = "m6"
    case ninth = "9"
    case major9 = "maj9"
    case minor9 = "m9"
    case add9
    case minor7Flat5 = "m7b5"
    case diminished7 = "dim7"
    case dominant7Sus4 = "7sus4"
    case minorMajor7 = "mMaj7"

    /// ルートからの半音数。
    public var intervals: [Int] {
        switch self {
        case .major: [0, 4, 7]
        case .minor: [0, 3, 7]
        case .dominant7: [0, 4, 7, 10]
        case .major7: [0, 4, 7, 11]
        case .minor7: [0, 3, 7, 10]
        case .diminished: [0, 3, 6]
        case .augmented: [0, 4, 8]
        case .sus4: [0, 5, 7]
        case .sus2: [0, 2, 7]
        case .sixth: [0, 4, 7, 9]
        case .minor6: [0, 3, 7, 9]
        case .ninth: [0, 4, 7, 10, 14]
        case .major9: [0, 4, 7, 11, 14]
        case .minor9: [0, 3, 7, 10, 14]
        case .add9: [0, 4, 7, 14]
        case .minor7Flat5: [0, 3, 6, 10]
        case .diminished7: [0, 3, 6, 9]
        case .dominant7Sus4: [0, 5, 7, 10]
        case .minorMajor7: [0, 3, 7, 11]
        }
    }

    /// 表記ゆれ（M7, △7, -7 など）を正規の質に寄せる。
    static let aliases: [String: ChordQuality] = [
        "M": .major, "maj": .major, "min": .minor, "-": .minor,
        "M7": .major7, "△7": .major7, "-7": .minor7,
        "°": .diminished, "°7": .diminished7, "ø": .minor7Flat5, "+": .augmented, "mM7": .minorMajor7,
    ]

    init?(symbol: String) {
        if let quality = ChordQuality(rawValue: symbol) ?? Self.aliases[symbol] {
            self = quality
        } else {
            return nil
        }
    }
}

/// コード（ルート、質、分数コードのベース音）。
public struct Chord: Hashable, Codable, Sendable {
    public var root: PitchClass
    public var quality: ChordQuality
    public var bass: PitchClass?
    /// 表示時にフラットで綴るか（入力で ♭ が使われたかを保持する）。
    public var prefersFlats: Bool

    public init(root: PitchClass, quality: ChordQuality, bass: PitchClass? = nil, prefersFlats: Bool = false) {
        self.root = Pitch.mod12(root)
        self.quality = quality
        self.bass = bass.map(Pitch.mod12)
        self.prefersFlats = prefersFlats
    }

    /// 「Dm7」「C/E」「Bbmaj7」などのコードネームを解析する。
    public init?(_ symbol: String) {
        let text = symbol.trimmingCharacters(in: .whitespaces)
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count <= 2, let head = parts.first, !head.isEmpty else { return nil }

        var rootLength = 1
        if head.count > 1, "#♯b♭".contains(head[head.index(after: head.startIndex)]) {
            rootLength = 2
        }
        let rootName = head.prefix(rootLength)
        guard let root = Pitch.pitchClass(named: rootName),
              let quality = ChordQuality(symbol: String(head.dropFirst(rootLength)))
        else { return nil }

        var bass: PitchClass?
        var bassName: Substring = ""
        if parts.count == 2 {
            bassName = parts[1]
            guard let parsed = Pitch.pitchClass(named: bassName) else { return nil }
            bass = parsed
        }
        let isFlat = { (name: Substring) in name.contains("b") || name.contains("♭") }
        self.init(root: root, quality: quality, bass: bass, prefersFlats: isFlat(rootName.dropFirst()) || isFlat(bassName.dropFirst()))
    }

    /// コードネーム表記。
    public var symbol: String {
        var text = Pitch.name(of: root, preferFlats: prefersFlats) + quality.rawValue
        if let bass {
            text += "/" + Pitch.name(of: bass, preferFlats: prefersFlats)
        }
        return text
    }

    /// 構成音のピッチクラス（ルートから順、重複なし）。分数コードのベース音が構成音に無ければ末尾に加える。
    public var pitchClasses: [PitchClass] {
        var result: [PitchClass] = []
        for interval in quality.intervals {
            let pc = Pitch.mod12(root + interval)
            if !result.contains(pc) { result.append(pc) }
        }
        if let bass, !result.contains(bass) {
            result.append(bass)
        }
        return result
    }
}
