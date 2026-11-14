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

    // MARK: 選んだ音の移動・削除

    /// タイでつながった一続きの音（同じ音高）。休符はそれ1つだけ。開始順。
    public static func tiedChain(containing id: Note.ID, in notes: [Note]) -> [Note] {
        guard let note = notes.first(where: { $0.id == id }) else { return [] }
        guard let pitch = note.pitch else { return [note] }
        var chain = [note]
        // 前へ：同じ音高で、ちょうどこの音で終わり、タイでつないでいる音
        while let previous = notes.first(where: { $0.end == chain[0].start && $0.pitch == pitch && $0.tiesToNext }) {
            chain.insert(previous, at: 0)
        }
        // 後ろへ
        while chain[chain.count - 1].tiesToNext,
              let next = notes.first(where: { $0.start == chain[chain.count - 1].end && $0.pitch == pitch }) {
            chain.append(next)
        }
        return chain
    }

    /// 選んだ音を消す。消した音へ向かっていたタイは外す。跡は空白のまま（休符で埋めない）。
    public static func delete(ids: Set<Note.ID>, in track: inout Track) {
        track.notes.removeAll { ids.contains($0.id) }
        removeDanglingTies(&track.notes)
    }

    /// 選んだ音（タイでつながった一続き、または休符1つ）を ticks だけずらし、音高を pitch にする（休符は音高を無視）。
    /// - 移動先は上書き方式：同じ位置・同じ長さの音とは和音になり、それ以外の重なる音は消すか手前で切り詰める。
    /// - 小節線をまたぐ長さは分けてタイでつなぐ。前後の音とのタイは外れる。曲の範囲からははみ出さない。
    /// - Returns: 動かした後の音の ID（開始順）。動かなければ元の ID。
    @discardableResult
    public static func move(
        ids: Set<Note.ID>,
        by ticks: Tick,
        to pitch: MIDINote?,
        in track: inout Track,
        timeSignature: TimeSignature,
        totalTicks: Tick
    ) -> [Note.ID] {
        let moving = track.notes.filter { ids.contains($0.id) }
        guard let start = moving.map(\.start).min(), let end = moving.map(\.end).max() else { return [] }
        let length = end - start
        let originalPitch = moving[0].pitch
        let newPitch = originalPitch == nil ? nil : min(max(pitch ?? originalPitch!, 0), 127)
        let newStart = min(max(start + ticks, 0), max(totalTicks - length, 0))
        guard newStart != start || newPitch != originalPitch else { return moving.map(\.id) }

        delete(ids: ids, in: &track)
        let range = newStart..<(newStart + length)
        let segments = split(range, timeSignature: timeSignature)
        var placed: [Note] = []
        if let newPitch {
            // 同じ位置・同じ長さで鳴っている別の音高の音は残して和音にする
            let joinsChord = { (note: Note) in
                note.pitch != nil && note.pitch != newPitch
                    && segments.contains { $0.lowerBound == note.start && $0.count == note.duration }
            }
            let kept = track.notes.filter(joinsChord)
            track.notes.removeAll(where: joinsChord)
            clear(&track.notes, from: range.lowerBound, to: range.upperBound)
            track.notes += kept
            for (index, segment) in segments.enumerated() {
                placed.append(Note(start: segment.lowerBound, duration: segment.count, pitch: newPitch,
                                   tiesToNext: index < segments.count - 1))
            }
            // 手前の同じ音高の音からのタイは外す
            for index in track.notes.indices where track.notes[index].end == newStart && track.notes[index].pitch == newPitch {
                track.notes[index].tiesToNext = false
            }
        } else {
            clear(&track.notes, from: range.lowerBound, to: range.upperBound)
            placed = segments.map { Note.rest(start: $0.lowerBound, duration: $0.count) }
        }
        track.notes += placed
        removeDanglingTies(&track.notes)
        sort(&track.notes)
        return placed.map(\.id)
    }

    /// つなぐ先（ちょうど終わる位置で始まる同じ音高の音）が無いタイを外す。
    static func removeDanglingTies(_ notes: inout [Note]) {
        let starts = Set(notes.compactMap { note in note.pitch.map { [note.start, $0] } })
        for index in notes.indices where notes[index].tiesToNext {
            if let pitch = notes[index].pitch, starts.contains([notes[index].end, pitch]) { continue }
            notes[index].tiesToNext = false
        }
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
