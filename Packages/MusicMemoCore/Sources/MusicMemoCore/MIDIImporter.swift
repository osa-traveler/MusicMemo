import Foundation

/// 変換の設定。
public struct MIDIImportOptions: Sendable {
    public enum Grid: String, Sendable {
        /// 16分と8分3連の格子のうち、拍ごとに近い方へそろえる。
        case sixteenthAndTriplet
        /// 16分の格子だけ。
        case sixteenth
    }

    public var grid: Grid
    /// 調を指定する（nil なら MIDI の調号、無ければ C major）。
    public var key: Key?

    public init(grid: Grid = .sixteenthAndTriplet, key: Key? = nil) {
        self.grid = grid
        self.key = key
    }
}

/// 変換の結果。
public struct MIDIImportResult: Sendable {
    public var file: SketchFile
    /// 変換の内容（曲の設定、トラックの対応）。
    public var report: [String]
    /// 読み込めなかったもの・変えたもの。
    public var warnings: [String]
}

/// MIDI（SMF）を MusicMemo の曲（.musicmemo）にする。
///
/// - MIDI のトラックごと（1つのトラックに複数のチャンネルがあればチャンネルごと）に MusicMemo のトラックにする
/// - 10ch（ドラム）は、どのトラックにあっても1本のドラムのトラックにまとめ、最後に置く（長さは同じ声部で次に叩くまで。タイは使わない）
/// - 音の位置と長さは、拍ごとに 16分か8分3連の格子へそろえる（クオンタイズ）
/// - 小節線をまたぐ音や1つの記号で書けない長さは、分けてタイでつなぐ
/// - 2つの声部に収まらない小節は、重なる音を境目で分けてタイでつなぎ、和音にする
public enum MIDIImporter {
    static let beat = Timing.ticksPerQuarter              // 480
    static let straightStep = Timing.ticksPerSixteenth    // 120
    static let tripletStep = Timing.ticksPerQuarter / 3   // 160

    /// 3連符で読む拍の判定：3連の格子へのずれの合計が、16分の格子へのずれの合計のこの割合より小さいとき。
    static let tripletPreference = 0.6

    /// 16分系（付点を含む）の1つの記号で書ける長さ（長い順）。
    static let straightLengths: [Tick] = Set(NoteValue.allCases.flatMap { [NoteDuration($0).ticks, NoteDuration($0, dotted: true).ticks] })
        .sorted(by: >)
    /// 3連の拍の中で使う長さ（4分、4分3連、8分3連）。
    static let tripletLengths: [Tick] = [beat, tripletStep * 2, tripletStep]

    // MARK: 変換

    public static func convert(_ data: Data, title: String, options: MIDIImportOptions = MIDIImportOptions()) throws -> MIDIImportResult {
        try convert(SMFReader.read(data), title: title, options: options)
    }

    public static func convert(_ smf: SMFFile, title: String, options: MIDIImportOptions = MIDIImportOptions()) -> MIDIImportResult {
        var report: [String] = []
        var warnings: [String] = []
        let scale = { (tick: Int) -> Tick in Int((Double(tick) * Double(beat) / Double(smf.ticksPerQuarter)).rounded()) }

        // 曲全体のメタイベント（どのトラックにあっても拾う）
        let metas: [(tick: Tick, type: Int, data: [UInt8])] = smf.tracks.flatMap { track in
            track.events.compactMap { event -> (Tick, Int, [UInt8])? in
                if case let .meta(type, data) = event.kind { return (scale(event.tick), type, data) }
                return nil
            }
        }.sorted { $0.tick < $1.tick }

        let timeSignature = readTimeSignature(metas, warnings: &warnings)
        let tempo = readTempo(metas, warnings: &warnings)
        let key = options.key ?? readKey(metas, warnings: &warnings) ?? .cMajor
        let barTicks = timeSignature.ticksPerBar

        // トラック（MIDI のトラック × チャンネル）
        var (sources, drums) = collectSources(smf, scale: scale, warnings: &warnings)
        if sources.count > TrackEditing.maximumCount {
            let dropped = sources[TrackEditing.maximumCount...].map(\.name)
            warnings.append("トラックは \(TrackEditing.maximumCount) 本までなので、後ろの \(dropped.count) 本（\(dropped.joined(separator: "、"))）は読み込みませんでした")
            sources = Array(sources.prefix(TrackEditing.maximumCount))
        }

        // 曲の長さ（小節数）。音符の終わりと、セクション名（マーカー）の小節が収まる長さ
        let maxBars = SongSettings.barCountRange.upperBound
        let lastEnd = (sources.flatMap(\.notes) + (drums?.notes ?? [])).map(\.end).max() ?? 0
        let lastMarkerBar = metas.filter { $0.type == 0x06 }.map { Int((Double($0.tick) / Double(barTicks)).rounded()) + 1 }.max() ?? 1
        var barCount = max(Int((Double(lastEnd) / Double(barTicks)).rounded(.up)), lastMarkerBar, 1)
        if barCount > maxBars {
            warnings.append("曲が \(barCount) 小節あり、上限の \(maxBars) 小節より後ろは読み込みませんでした")
            barCount = maxBars
        }
        let totalTicks = barCount * barTicks

        // 音符（クオンタイズ → 整理 → 小節線と記号の長さで分ける → 声部の整理）
        var tracks: [Track] = []
        var stats: [TrackStats] = []
        for source in sources {
            let quantized = quantize(source.notes, allowTriplets: options.grid == .sixteenthAndTriplet)
            var cleaned = clean(quantized.notes).filter { $0.start < totalTicks }
            for index in cleaned.indices { cleaned[index].end = min(cleaned[index].end, totalTicks) }
            var notes = cleaned.flatMap { notesFor($0, barTicks: barTicks, tripletBeats: quantized.tripletBeats) }
            let joinedBars = fitVoices(&notes, barTicks: barTicks, tripletBeats: quantized.tripletBeats)
            notes.sort { ($0.start, $0.pitch ?? -1) < ($1.start, $1.pitch ?? -1) }

            let shape = TrackShape(cleaned)
            tracks.append(Track(
                name: source.name, role: .other, clef: shape.median < 55 ? .bass : .treble, color: .gray,
                volume: source.volume, pan: source.pan, program: source.program, notes: notes
            ))
            stats.append(TrackStats(source: source, shape: shape, tripletBeats: quantized.tripletBeats.count, joinedBars: joinedBars))
        }
        assignRoles(&tracks, stats: stats)

        // ドラム（最後に置く）
        if let drums {
            let quantized = quantize(drums.notes, allowTriplets: options.grid == .sixteenthAndTriplet)
            let notes = drumNotes(quantized.notes.filter { $0.start < totalTicks }, barTicks: barTicks,
                                  tripletBeats: quantized.tripletBeats, totalTicks: totalTicks)
            tracks.append(Track(
                name: drums.name, role: .drums, clef: .percussion, color: .gray,
                volume: drums.volume, pan: drums.pan, program: drums.program, notes: notes
            ))
            stats.append(TrackStats(source: drums, shape: TrackShape(quantized.notes), tripletBeats: quantized.tripletBeats.count, joinedBars: 0))
        }

        let sections = readSections(metas, barTicks: barTicks, barCount: barCount)
        let sketch = Sketch(
            title: title, key: key, timeSignature: timeSignature, tempo: tempo, barCount: barCount,
            sections: sections, tracks: tracks
        )
        let editor = EditorState(editPosition: 0, selectedTrackID: tracks.first?.id, duration: NoteDuration(.quarter))

        report.append("\(key.description) · \(timeSignature.beats)/\(timeSignature.beatUnit) · ♩=\(tempoText(tempo)) · \(barCount)小節 · \(tracks.count)トラック")
        report.append("セクション：" + sections.map { "\($0.name)（\($0.startBar)〜）" }.joined(separator: "、"))
        for (index, (track, stat)) in zip(tracks, stats).enumerated() {
            let clefName = switch track.clef {
            case .treble: "ト音記号"
            case .bass: "ヘ音記号"
            case .percussion: "ドラム譜"
            }
            var line = "\(index + 1). \(track.name)：\(track.role.displayName)・\(clefName)・\(track.isDrums ? "キット" : "GM") \(track.program)"
                + "・ch\(stat.source.channel + 1)・音符 \(stat.source.notes.count)"
            if stat.tripletBeats > 0 { line += "・3連符で読んだ拍 \(stat.tripletBeats)" }
            if stat.joinedBars > 0 { line += "・和音にまとめた小節 \(stat.joinedBars)" }
            report.append(line)
        }
        if tracks.isEmpty { warnings.append("音符のあるトラックがありませんでした") }

        return MIDIImportResult(file: SketchFile(sketch: sketch, editor: editor), report: report, warnings: warnings)
    }

    static func tempoText(_ tempo: Double) -> String {
        tempo.rounded() == tempo ? String(Int(tempo)) : String(format: "%.1f", tempo)
    }

    // MARK: 曲の設定

    static func readTimeSignature(_ metas: [(tick: Tick, type: Int, data: [UInt8])], warnings: inout [String]) -> TimeSignature {
        let signatures = metas.filter { $0.type == 0x58 && $0.data.count >= 2 }
            .map { (tick: $0.tick, beats: Int($0.data[0]), unit: 1 << Int($0.data[1])) }
        guard let first = signatures.first else { return .common }
        if Set(signatures.map { [$0.beats, $0.unit] }).count > 1 {
            warnings.append("途中で拍子が変わっています（\(signatures.count - 1) か所）。最初の拍子のまま読み込みました（小節線がずれることがあります）")
        }
        let original = TimeSignature(beats: first.beats, beatUnit: first.unit)
        if SongSettings.timeSignatures.contains(original) { return original }
        // MusicMemo で選べるのは 2/4・3/4・4/4。小節の長さが同じならそれに置き換える（6/8 → 3/4 など）
        if let same = SongSettings.timeSignatures.first(where: { $0.ticksPerBar == original.ticksPerBar }) {
            warnings.append("\(first.beats)/\(first.unit) は \(same.beats)/\(same.beatUnit) として読み込みました（小節の長さは同じ）")
            return same
        }
        warnings.append("\(first.beats)/\(first.unit) は MusicMemo で選べないので 4/4 として読み込みました（小節線がずれます）")
        return .common
    }

    static func readTempo(_ metas: [(tick: Tick, type: Int, data: [UInt8])], warnings: inout [String]) -> Double {
        let tempos = metas.filter { $0.type == 0x51 && $0.data.count >= 3 }.map { meta -> Double in
            let microseconds = Int(meta.data[0]) << 16 | Int(meta.data[1]) << 8 | Int(meta.data[2])
            return (60_000_000 / Double(max(microseconds, 1)) * 10).rounded() / 10
        }
        guard let first = tempos.first else { return 120 }
        let changes = zip(tempos, tempos.dropFirst()).filter { $0 != $1 }.count
        if changes > 0 {
            warnings.append("途中でテンポが変わっています（\(changes) か所）。最初の ♩=\(tempoText(first)) にしました")
        }
        let range = SongSettings.tempoRange
        let clamped = min(max(first, Double(range.lowerBound)), Double(range.upperBound))
        if clamped != first {
            warnings.append("♩=\(tempoText(first)) は範囲（\(range.lowerBound)〜\(range.upperBound)）の外なので ♩=\(tempoText(clamped)) にしました")
        }
        return clamped
    }

    static func readKey(_ metas: [(tick: Tick, type: Int, data: [UInt8])], warnings: inout [String]) -> Key? {
        let keys = metas.filter { $0.type == 0x59 && $0.data.count >= 2 }.map { meta -> Key in
            let fifths = Int(Int8(bitPattern: meta.data[0]))
            let majorTonic = ((fifths * 7) % 12 + 12) % 12
            return meta.data[1] == 1 ? Key(tonic: majorTonic + 9, mode: .minor) : Key(tonic: majorTonic, mode: .major)
        }
        if Set(keys).count > 1 {
            warnings.append("途中で調が変わっています。最初の調（\(keys[0].description)）にしました")
        }
        return keys.first
    }

    /// マーカー（セクション名）からセクションを作る。マーカーの位置は一番近い小節線に寄せる。
    /// マーカーが無ければ、曲全体を1つのセクション（新しい曲のひな形と同じ「Aメロ」）にする。
    static func readSections(_ metas: [(tick: Tick, type: Int, data: [UInt8])], barTicks: Tick, barCount: Int) -> [SongSection] {
        var starts: [(bar: Int, name: String)] = []
        for meta in metas where meta.type == 0x06 {
            let name = SMFReader.text(meta.data)
            let bar = min(max(Int((Double(meta.tick) / Double(barTicks)).rounded()) + 1, 1), barCount)
            guard !name.isEmpty, !starts.contains(where: { $0.bar == bar }) else { continue }
            starts.append((bar, name))
        }
        starts.sort { $0.bar < $1.bar }
        guard !starts.isEmpty else { return [SongSection(name: "Aメロ", startBar: 1, barCount: barCount)] }
        return starts.enumerated().map { index, start in
            let next = index + 1 < starts.count ? starts[index + 1].bar : barCount + 1
            return SongSection(name: start.name, startBar: start.bar, barCount: next - start.bar)
        }
    }

    // MARK: トラック

    struct RawNote: Equatable {
        var start: Tick
        var end: Tick
        var pitch: MIDINote
    }

    struct Source {
        var name: String
        var channel: Int
        var program: Int
        var volume: Int
        var pan: Int
        var notes: [RawNote]
    }

    /// MIDI のトラックごと（チャンネルが複数あればチャンネルごと）に音符を集める。10ch は除く。
    static func collectSources(_ smf: SMFFile, scale: (Int) -> Tick, warnings: inout [String]) -> (sources: [Source], drums: Source?) {
        var sources: [Source] = []
        var drumNotes: [RawNote] = []
        // 音色・音量・パンがほかのトラック（指揮者トラックなど）にあるときのために、チャンネルごとの最初の値も覚える
        var channelProgram: [Int: Int] = [:], channelVolume: [Int: Int] = [:], channelPan: [Int: Int] = [:]
        for track in smf.tracks {
            for event in track.events {
                switch event.kind {
                case let .programChange(channel, program): if channelProgram[channel] == nil { channelProgram[channel] = program }
                case let .controlChange(channel, 7, value): if channelVolume[channel] == nil { channelVolume[channel] = value }
                case let .controlChange(channel, 10, value): if channelPan[channel] == nil { channelPan[channel] = value }
                default: break
                }
            }
        }

        for track in smf.tracks {
            var trackName = ""
            var instrumentName = ""
            var notes: [Int: [RawNote]] = [:]
            var open: [[Int]: [(start: Tick, order: Int)]] = [:]   // [チャンネル, 音高] → 鳴っている音（古い順）
            var program: [Int: Int] = [:], volume: [Int: Int] = [:], pan: [Int: Int] = [:]
            var lastTick = 0
            for (order, event) in track.events.enumerated() {
                let tick = scale(event.tick)
                lastTick = max(lastTick, tick)
                switch event.kind {
                case let .meta(0x03, data) where trackName.isEmpty: trackName = SMFReader.text(data)
                case let .meta(0x04, data) where instrumentName.isEmpty: instrumentName = SMFReader.text(data)
                case let .programChange(channel, value): if program[channel] == nil { program[channel] = value }
                case let .controlChange(channel, 7, value): if volume[channel] == nil { volume[channel] = value }
                case let .controlChange(channel, 10, value): if pan[channel] == nil { pan[channel] = value }
                case let .noteOn(channel, pitch, _):
                    // ドラムは叩いた位置だけを使う（長さはあとで決める）
                    if channel == 9 { drumNotes.append(RawNote(start: tick, end: tick + 1, pitch: pitch)); continue }
                    open[[channel, pitch], default: []].append((tick, order))
                case let .noteOff(channel, pitch):
                    guard channel != 9, var stack = open[[channel, pitch]], !stack.isEmpty else { continue }
                    let started = stack.removeFirst()
                    open[[channel, pitch]] = stack
                    notes[channel, default: []].append(RawNote(start: started.start, end: tick, pitch: pitch))
                default: break
                }
            }
            // 止める音の無いまま終わった音は、トラックの最後まで伸ばす
            for (key, stack) in open {
                for started in stack where lastTick > started.start {
                    notes[key[0], default: []].append(RawNote(start: started.start, end: lastTick, pitch: key[1]))
                }
            }

            let channels = notes.keys.sorted()
            for channel in channels {
                let programNumber = program[channel] ?? channelProgram[channel] ?? Track.defaultProgram
                let gmName = GMInstruments.names.indices.contains(programNumber) ? GMInstruments.names[programNumber] : "Track"
                // フォーマット0のように1つのトラックに複数のチャンネルがあれば、トラック名は曲名のことが多いので音色名を使う
                let ownName = trackName.isEmpty ? instrumentName : trackName
                let name = channels.count > 1 || ownName.isEmpty ? gmName : ownName
                let volumeValue = volume[channel] ?? channelVolume[channel]
                let panValue = pan[channel] ?? channelPan[channel]
                sources.append(Source(
                    name: name,
                    channel: channel,
                    program: programNumber,
                    volume: volumeValue.map { Int((Double($0) * 100 / 127).rounded()) } ?? 80,
                    pan: panValue.map { $0 - 64 } ?? 0,
                    notes: notes[channel, default: []].sorted { ($0.start, $0.pitch) < ($1.start, $1.pitch) }
                ))
            }
        }
        var drums: Source?
        if !drumNotes.isEmpty {
            drums = Source(
                name: "Drums", channel: 9, program: channelProgram[9] ?? 0,
                volume: channelVolume[9].map { Int((Double($0) * 100 / 127).rounded()) } ?? 80,
                pan: channelPan[9].map { $0 - 64 } ?? 0,
                notes: drumNotes.sorted { ($0.start, $0.pitch) < ($1.start, $1.pitch) }
            )
        }
        // 同じ名前のトラックには番号を付けて見分ける
        let counts = Dictionary(grouping: sources.map(\.name)) { $0 }.mapValues(\.count)
        var seen: [String: Int] = [:]
        for index in sources.indices where counts[sources[index].name, default: 0] > 1 {
            seen[sources[index].name, default: 0] += 1
            sources[index].name += " \(seen[sources[index].name]!)"
        }
        return (sources, drums)
    }

    // MARK: クオンタイズ

    /// 拍（4分音符）ごとに格子を選び、音の頭と終わりをそろえる。
    /// - Returns: そろえた音と、3連の格子で読んだ拍（曲頭から数えた拍の番号）。
    static func quantize(_ notes: [RawNote], allowTriplets: Bool) -> (notes: [RawNote], tripletBeats: Set<Int>) {
        var tripletBeats = Set<Int>()
        if allowTriplets {
            let onsetsByBeat = Dictionary(grouping: notes.map(\.start)) { $0 / beat }
            for (index, onsets) in onsetsByBeat {
                let locals = onsets.map { $0 - index * beat }
                let straightError = locals.map { distance($0, step: straightStep) }.reduce(0, +)
                let tripletError = locals.map { distance($0, step: tripletStep) }.reduce(0, +)
                let hasOffbeatTriplet = locals.contains { [1, 2].contains(Int((Double($0) / Double(tripletStep)).rounded())) }
                if hasOffbeatTriplet, Double(tripletError) < Double(straightError) * tripletPreference {
                    tripletBeats.insert(index)
                }
            }
        }
        let step = { (tick: Tick) in tripletBeats.contains(tick / beat) ? tripletStep : straightStep }
        let snap = { (tick: Tick) -> Tick in
            let index = tick / beat
            let local = tick - index * beat
            let unit = step(tick)
            return index * beat + Int((Double(local) / Double(unit)).rounded()) * unit
        }
        let result = notes.map { note -> RawNote in
            let start = snap(max(note.start, 0))
            var end = snap(max(note.end, 0))
            if end <= start { end = start + step(start) }
            return RawNote(start: start, end: end, pitch: note.pitch)
        }
        return (result, tripletBeats)
    }

    private static func distance(_ local: Tick, step: Tick) -> Int {
        abs(local - Int((Double(local) / Double(step)).rounded()) * step)
    }

    /// そろえたあとの整理。
    /// 1. 同じ位置・同じ高さの音は1つに（長い方）
    /// 2. 同じ位置で始まる音の終わりが16分以内の差なら、一番長い音にそろえる（和音の離し方のばらつき）
    /// 3. 同じ高さの音が重なったら、前の音を後の音の頭で切る
    /// 4. 次に始まる音へ16分以内だけ食い込んでいたら、その頭で切る（レガートの重なり。声部が増えないように）
    static func clean(_ notes: [RawNote]) -> [RawNote] {
        var unique: [[Int]: RawNote] = [:]
        for note in notes {
            let key = [note.start, note.pitch]
            if let existing = unique[key], existing.end >= note.end { continue }
            unique[key] = note
        }
        var result = unique.values.sorted { ($0.start, $0.pitch) < ($1.start, $1.pitch) }

        let byStart = Dictionary(grouping: result.indices) { result[$0].start }
        for indices in byStart.values {
            let longest = indices.map { result[$0].end }.max()!
            for index in indices where longest - result[index].end <= straightStep {
                result[index].end = longest
            }
        }

        let byPitch = Dictionary(grouping: result.indices) { result[$0].pitch }
        for indices in byPitch.values {
            let ordered = indices.sorted { result[$0].start < result[$1].start }
            for (current, next) in zip(ordered, ordered.dropFirst()) where result[next].start < result[current].end {
                result[current].end = result[next].start
            }
        }

        let starts = Array(Set(result.map(\.start))).sorted()
        for index in result.indices {
            let note = result[index]
            guard let next = starts.first(where: { $0 > note.start }), next < note.end, note.end - next <= straightStep else { continue }
            result[index].end = next
        }
        return result
    }

    // MARK: 記譜できる形に分ける

    /// 音を小節線、3連の拍の境目、1つの記号で書ける長さで分け、タイでつなぐ。
    static func notesFor(_ note: RawNote, barTicks: Tick, tripletBeats: Set<Int>) -> [Note] {
        let pieces = split(note.start..<note.end, barTicks: barTicks, tripletBeats: tripletBeats)
        return pieces.enumerated().map { index, piece in
            Note(start: piece.lowerBound, duration: piece.count, pitch: note.pitch, tiesToNext: index < pieces.count - 1)
        }
    }

    static func split(_ range: Range<Tick>, barTicks: Tick, tripletBeats: Set<Int>) -> [Range<Tick>] {
        var cuts = Set<Tick>()
        var bar = (range.lowerBound / barTicks + 1) * barTicks
        while bar < range.upperBound { cuts.insert(bar); bar += barTicks }
        for index in tripletBeats {
            for edge in [index * beat, (index + 1) * beat] where range.lowerBound < edge && edge < range.upperBound {
                cuts.insert(edge)
            }
        }
        let points = [range.lowerBound] + cuts.sorted() + [range.upperBound]
        var result: [Range<Tick>] = []
        for (start, end) in zip(points, points.dropFirst()) {
            let lengths = tripletBeats.contains(start / beat) ? tripletLengths : straightLengths
            var position = start
            while position < end {
                let length = lengths.first { $0 <= end - position } ?? (end - position)
                result.append(position..<(position + length))
                position += length
            }
        }
        return result
    }

    /// 2つの声部に収まらない小節は、その小節の音を互いの境目で分けてタイでつなぎ、和音にする。
    /// - Returns: 和音にまとめた小節の数。
    static func fitVoices(_ notes: inout [Note], barTicks: Tick, tripletBeats: Set<Int>) -> Int {
        let bars = Dictionary(grouping: notes.indices) { notes[$0].start / barTicks }
        var joined = 0
        var replaced: [Int: [Note]] = [:]
        for (_, indices) in bars {
            let barNotes = indices.map { notes[$0] }
            guard Notation.assignVoices(barNotes).overflows else { continue }
            joined += 1
            let boundaries = Set(barNotes.flatMap { [$0.start, $0.end] })
            for index in indices {
                let note = notes[index]
                let points = [note.start] + boundaries.filter { $0 > note.start && $0 < note.end }.sorted() + [note.end]
                var pieces: [Note] = []
                for (start, end) in zip(points, points.dropFirst()) {
                    for piece in split(start..<end, barTicks: barTicks, tripletBeats: tripletBeats) {
                        pieces.append(Note(start: piece.lowerBound, duration: piece.count, pitch: note.pitch, tiesToNext: true))
                    }
                }
                pieces[pieces.count - 1].tiesToNext = note.tiesToNext
                replaced[index] = pieces
            }
        }
        guard !replaced.isEmpty else { return 0 }
        notes = notes.indices.flatMap { replaced[$0] ?? [notes[$0]] }
        return joined
    }

    // MARK: ドラム

    /// ドラムの音符：同じ位置・同じ楽器は1つにし、長さは同じ声部（手／足）で次に叩くまで。
    /// 小節線・3連の拍の境目を越えず、1つの記号で書ける一番長い長さにする（タイは使わない。残りは休符になる）。
    static func drumNotes(_ hits: [RawNote], barTicks: Tick, tripletBeats: Set<Int>, totalTicks: Tick) -> [Note] {
        var result: [Note] = []
        for isFoot in [false, true] {
            let voiceHits = hits.filter { DrumMap.isFoot($0.pitch) == isFoot }
            let onsets = Array(Set(voiceHits.map(\.start))).sorted()
            let pitchesByOnset = Dictionary(grouping: voiceHits, by: \.start).mapValues { Set($0.map(\.pitch)).sorted() }
            for (index, onset) in onsets.enumerated() {
                let next = index + 1 < onsets.count ? onsets[index + 1] : totalTicks
                let end = min(next, totalTicks)
                guard end > onset, let first = split(onset..<end, barTicks: barTicks, tripletBeats: tripletBeats).first else { continue }
                for pitch in pitchesByOnset[onset] ?? [] {
                    result.append(Note(start: first.lowerBound, duration: first.count, pitch: pitch))
                }
            }
        }
        return result.sorted { ($0.start, $0.pitch ?? -1) < ($1.start, $1.pitch ?? -1) }
    }

    // MARK: 役割の推定

    /// トラックの音の形（音域と同時に鳴る音の数）。
    struct TrackShape {
        /// 音高の中央値。
        var median: Int
        /// 2音以上が同時に始まる割合。
        var polyphony: Double
        /// 3音以上が同時に始まる割合。
        var chordiness: Double

        init(_ notes: [RawNote]) {
            let pitches = notes.map(\.pitch).sorted()
            median = pitches.isEmpty ? 60 : pitches[pitches.count / 2]
            let counts = Dictionary(grouping: notes) { $0.start }.values.map(\.count)
            let total = Double(max(counts.count, 1))
            polyphony = Double(counts.filter { $0 >= 2 }.count) / total
            chordiness = Double(counts.filter { $0 >= 3 }.count) / total
        }
    }

    struct TrackStats {
        var source: Source
        var shape: TrackShape
        var tripletBeats: Int
        var joinedBars: Int
    }

    /// 音色と音の形からトラックの役割を決め、役割の色を付ける。
    /// - ベース：GM のベース（32〜39）、または音域が低く（中央値が D3 より下）ほぼ単音
    /// - コード：3音以上の和音で始まる所が3割以上（GM のシンセパッド 88〜95 ならパッド）
    /// - メロディ：残りのうち、ほぼ単音で音符が十分ある（一番多いトラックの半分以上）中で一番音域の高いトラック1本。ほかは「その他」
    static func assignRoles(_ tracks: inout [Track], stats: [TrackStats]) {
        let isPadProgram = { (program: Int) in (88..<96).contains(program) }
        var melodyCandidates: [Int] = []
        for index in tracks.indices {
            let shape = stats[index].shape
            let program = tracks[index].program
            if (32..<40).contains(program) || (shape.median < 50 && shape.polyphony < 0.2) {
                tracks[index].role = .bass
            } else if shape.chordiness >= 0.3 {
                tracks[index].role = isPadProgram(program) ? .pad : .chords
            } else if isPadProgram(program) {
                tracks[index].role = .pad
            } else {
                tracks[index].role = .other
                if shape.polyphony < 0.3 { melodyCandidates.append(index) }
            }
        }
        // 音符の少ないトラック（合いの手など）は外す：候補のうち一番多いトラックの半分以上ある中から、一番音域の高いもの
        let most = melodyCandidates.map { stats[$0].source.notes.count }.max() ?? 0
        if let melody = melodyCandidates.filter({ stats[$0].source.notes.count * 2 >= most })
            .max(by: { stats[$0].shape.median < stats[$1].shape.median }) {
            tracks[melody].role = .melody
        }
        let otherColors: [TrackColor] = [.ochre, .gray, .purple]
        var otherCount = 0
        for index in tracks.indices {
            switch tracks[index].role {
            case .melody: tracks[index].color = .blue
            case .chords: tracks[index].color = .orange
            case .bass: tracks[index].color = .green
            case .pad: tracks[index].color = .purple
            case .drums: tracks[index].color = .gray
            case .other:
                tracks[index].color = otherColors[otherCount % otherColors.count]
                otherCount += 1
            }
        }
    }
}
