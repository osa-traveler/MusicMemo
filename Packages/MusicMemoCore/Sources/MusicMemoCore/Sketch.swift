import Foundation

/// 曲。アプリで扱う1つのスケッチ。
public struct Sketch: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var key: Key
    public var timeSignature: TimeSignature
    /// テンポ（4分音符/分）。
    public var tempo: Double
    public var barCount: Int
    public var sections: [SongSection]
    /// 開始位置順に並べる。
    public var chords: [ChordEvent]
    public var tracks: [Track]
    /// 再生範囲（ワークエリア）。
    public var playRange: Range<Tick>
    public var isLooping: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        key: Key = .cMajor,
        timeSignature: TimeSignature = .common,
        tempo: Double = 120,
        barCount: Int,
        sections: [SongSection] = [],
        chords: [ChordEvent] = [],
        tracks: [Track] = [],
        playRange: Range<Tick>? = nil,
        isLooping: Bool = false
    ) {
        self.id = id
        self.title = title
        self.key = key
        self.timeSignature = timeSignature
        self.tempo = tempo
        self.barCount = barCount
        self.sections = sections
        self.chords = chords.sorted { $0.start < $1.start }
        self.tracks = tracks
        self.playRange = playRange ?? 0..<(barCount * timeSignature.ticksPerBar)
        self.isLooping = isLooping
    }

    public var totalTicks: Tick { barCount * timeSignature.ticksPerBar }

    /// tick の位置で鳴っているコード（次のコードまで持続する）。
    public func chord(at tick: Tick) -> ChordEvent? {
        chords.last { $0.start <= tick }
    }

    /// 小節内で始まるコード。
    public func chords(inBar bar: Int) -> [ChordEvent] {
        let start = timeSignature.startTick(ofBar: bar)
        let end = start + timeSignature.ticksPerBar
        return chords.filter { $0.start >= start && $0.start < end }
    }

    public func section(containingBar bar: Int) -> SongSection? {
        sections.first { $0.bars.contains(bar) }
    }
}

/// セクション（Aメロ、サビ…）。小節番号は1始まり。
public struct SongSection: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var startBar: Int
    public var barCount: Int

    public init(id: UUID = UUID(), name: String, startBar: Int, barCount: Int) {
        self.id = id
        self.name = name
        self.startBar = startBar
        self.barCount = barCount
    }

    public var bars: ClosedRange<Int> { startBar...(startBar + barCount - 1) }
}

/// コード進行の1つのコード。
public struct ChordEvent: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var start: Tick
    public var chord: Chord

    public init(id: UUID = UUID(), start: Tick, chord: Chord) {
        self.id = id
        self.start = start
        self.chord = chord
    }
}
