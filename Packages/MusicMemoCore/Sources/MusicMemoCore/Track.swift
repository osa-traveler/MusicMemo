import Foundation

public enum Clef: String, Codable, Sendable {
    case treble
    case bass
}

public enum TrackRole: String, CaseIterable, Codable, Sendable {
    case melody
    case chords
    case bass
    case pad
    case other

    /// トラック情報列に出す名前。
    public var displayName: String {
        switch self {
        case .melody: "メロディ"
        case .chords: "コード"
        case .bass: "ベース"
        case .pad: "パッド"
        case .other: "その他"
        }
    }
}

/// トラック色（SPEC のトラック色6色）。実際の色はアプリ側で割り当てる。
public enum TrackColor: String, CaseIterable, Codable, Sendable {
    case blue
    case orange
    case green
    case purple
    case ochre
    case gray
}

public struct Track: Identifiable, Hashable, Codable, Sendable {
    public static let volumeRange = 0...100
    public static let panRange = -64...63
    /// 新しいトラックの音色（GM 0 = Acoustic Grand Piano）。
    public static let defaultProgram = 0

    public var id: UUID
    /// 楽器名（Piano, E.Piano …）。
    public var name: String
    public var role: TrackRole
    public var clef: Clef
    public var color: TrackColor
    public var volume: Int
    public var pan: Int
    public var isMuted: Bool
    public var isSoloed: Bool
    /// GMプログラム番号（0始まり）。
    public var program: Int
    public var notes: [Note]

    public init(
        id: UUID = UUID(),
        name: String,
        role: TrackRole,
        clef: Clef = .treble,
        color: TrackColor,
        volume: Int = 80,
        pan: Int = 0,
        isMuted: Bool = false,
        isSoloed: Bool = false,
        program: Int = Track.defaultProgram,
        notes: [Note] = []
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.clef = clef
        self.color = color
        self.volume = volume.clamped(to: Self.volumeRange)
        self.pan = pan.clamped(to: Self.panRange)
        self.isMuted = isMuted
        self.isSoloed = isSoloed
        self.program = program
        self.notes = notes
    }

    /// コードトラックは五線の上にコードネームを表示する。
    public var showsChordSymbols: Bool { role == .chords }

    /// パンの表示（「C」「L16」「R20」）。
    public var panLabel: String { Self.panLabel(pan) }

    public static func panLabel(_ pan: Int) -> String {
        switch pan {
        case 0: "C"
        case ..<0: "L\(-pan)"
        default: "R\(pan)"
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
