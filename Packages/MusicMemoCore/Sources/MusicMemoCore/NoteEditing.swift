/// 音符の入力・削除（上書き方式）。トラックの音符は開始位置・音高の順に保つ。
public enum NoteEditing {
    /// 1つの記号で書ける長さ（長い順）。小節線で分けた残りをこれで組み立てる。
    static let writableLengths: [Tick] = {
        let durations = NoteValue.allCases.flatMap { value in
            [NoteDuration(value), NoteDuration(value, dotted: true), NoteDuration(value, triplet: true)]
        }
        return Set(durations.map(\.ticks)).sorted(by: >)
    }()

    /// 音符（pitches が空なら休符）を start から duration の長さで入力する。
    /// - 重なる既存の音符は消すか、手前で切り詰める（上書き）。
    /// - 小節線をまたぐ長さや1つの記号で書けない長さは分けてタイでつなぐ（休符はタイなし）。
    /// - tieFromPrevious なら、start で終わる同じ音高の音符からタイでつなぐ。
    /// - Returns: 入力した範囲（曲の終わりで切れることがある）。
    @discardableResult
    public static func enter(
        pitches: [MIDINote],
        at start: Tick,
        duration: Tick,
        tieFromPrevious: Bool = false,
        in track: inout Track,
        timeSignature: TimeSignature,
        totalTicks: Tick
    ) -> Range<Tick> {
        let end = min(start + duration, totalTicks)
        guard start < end else { return start..<start }
        clear(&track.notes, from: start, to: end)

        let segments = split(start..<end, timeSignature: timeSignature)
        let uniquePitches = Array(Set(pitches)).sorted()
        if uniquePitches.isEmpty {
            track.notes += segments.map { Note.rest(start: $0.lowerBound, duration: $0.count) }
        } else {
            for (index, segment) in segments.enumerated() {
                let isLast = index == segments.count - 1
                track.notes += uniquePitches.map {
                    Note(start: segment.lowerBound, duration: segment.count, pitch: $0, tiesToNext: !isLast)
                }
            }
            if tieFromPrevious {
                for index in track.notes.indices where track.notes[index].end == start {
                    if let pitch = track.notes[index].pitch, uniquePitches.contains(pitch) {
                        track.notes[index].tiesToNext = true
                    }
                }
            }
        }
        sort(&track.notes)
        return start..<end
    }

    /// すでに入力した音（範囲 range）に音高を重ねて和音にする。休符だった場合は音符に置き換える。
    public static func addToChord(pitch: MIDINote, range: Range<Tick>, in track: inout Track, timeSignature: TimeSignature) {
        let segmentsHaveNotes = track.notes.contains { range.contains($0.start) && $0.pitch == pitch }
        guard !segmentsHaveNotes else { return }
        track.notes.removeAll { range.contains($0.start) && $0.isRest }
        let segments = split(range, timeSignature: timeSignature)
        for (index, segment) in segments.enumerated() {
            track.notes.append(Note(start: segment.lowerBound, duration: segment.count, pitch: pitch,
                                    tiesToNext: index < segments.count - 1))
        }
        sort(&track.notes)
    }

    /// 戻って消す：position より前で始まる一番近い音符（和音ならまとめて）を消す。
    /// - Returns: 消した音符の開始位置（新しい編集位置）。消すものが無ければ nil。
    @discardableResult
    public static func deleteBefore(_ position: Tick, in track: inout Track) -> Tick? {
        guard let start = track.notes.filter({ $0.start < position }).map(\.start).max() else { return nil }
        let removed = track.notes.filter { $0.start == start }
        track.notes.removeAll { $0.start == start }
        // 消した音へ向かっていたタイを外す
        let removedPitches = Set(removed.compactMap(\.pitch))
        for index in track.notes.indices where track.notes[index].end == start {
            if let pitch = track.notes[index].pitch, removedPitches.contains(pitch) {
                track.notes[index].tiesToNext = false
            }
        }
        return start
    }

    // MARK: 内部

    /// [start, end) に重なる音符を消す。手前から食い込んでいる音符は start で切り詰める。
    static func clear(_ notes: inout [Note], from start: Tick, to end: Tick) {
        notes = notes.compactMap { note in
            if note.end <= start || note.start >= end { return note }
            if note.start < start {
                var trimmed = note
                trimmed.duration = start - note.start
                trimmed.tiesToNext = false
                return trimmed
            }
            return nil
        }
    }

    /// 範囲を小節線で分け、さらに1つの記号で書ける長さに分ける。
    static func split(_ range: Range<Tick>, timeSignature: TimeSignature) -> [Range<Tick>] {
        var result: [Range<Tick>] = []
        var position = range.lowerBound
        while position < range.upperBound {
            let barEnd = timeSignature.startTick(ofBar: timeSignature.bar(containing: position) + 1)
            let segmentEnd = min(barEnd, range.upperBound)
            var remaining = segmentEnd - position
            while remaining > 0 {
                let length = writableLengths.first { $0 <= remaining } ?? remaining
                result.append(position..<(position + length))
                position += length
                remaining -= length
            }
        }
        return result
    }

    static func sort(_ notes: inout [Note]) {
        notes.sort { ($0.start, $0.pitch ?? -1) < ($1.start, $1.pitch ?? -1) }
    }
}
