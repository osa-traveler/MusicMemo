/// 調。
public struct Key: Hashable, Codable, Sendable {
    public enum Mode: String, Codable, Sendable {
        case major
        case minor
    }

    public var tonic: PitchClass
    public var mode: Mode

    public init(tonic: PitchClass, mode: Mode) {
        self.tonic = Pitch.mod12(tonic)
        self.mode = mode
    }

    public static let cMajor = Key(tonic: 0, mode: .major)

    /// 調号がフラット系か（F, Bb, Eb … / Dm, Gm …）。
    public var prefersFlats: Bool {
        let majorTonic = mode == .major ? tonic : Pitch.mod12(tonic + 3)
        return [5, 10, 3, 8, 1].contains(majorTonic)
    }

    /// 「C major」形式。
    public var description: String {
        Pitch.name(of: tonic, preferFlats: prefersFlats) + " " + mode.rawValue
    }
}
