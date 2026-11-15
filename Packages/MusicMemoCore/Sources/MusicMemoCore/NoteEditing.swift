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
    @discardableResult
    public static func move(
        ids: Set<Note.ID>,
        by ticks: Tick,
        to pitch: MIDINote?,
        in track: inout Track,
        timeSignature: TimeSignature,
        totalTicks: Tick
    ) -> [Note.ID] {
        move(ids: ids, by: ticks, pitch: { original in pitch ?? original }, in: &track,
             timeSignature: timeSignature, totalTicks: totalTicks)
    }

    /// 選んだ音（タイでつながった一続きや休符をいくつでも）をまとめて ticks だけずらし、音高を pitch で変える（休符は横にだけ動く）。
    /// - 選んだ音どうしの並びは保つ（選んだ音どうしは消し合わない）。曲の端では、まとまり全体で止まる。
    /// - 移動先で別の高さの音と重なったら、どちらも切らずに重ねる（譜面では2つの声部に分けて描く）。同じ位置・同じ長さなら和音。
    ///   重ねると声部が2つに収まらないときだけ、重なる音どうしを境目で分けてタイでつなぎ、和音にする。
    /// - 同じ高さの音と休符は上書き（消すか手前で切り詰める）。
    /// - 小節線をまたぐ長さは分けてタイでつなぐ。前後の音とのタイは外れる。
    /// - Returns: 動かした後の音の ID（開始順）。動かなければ元の ID。
    @discardableResult
    public static func move(
        ids: Set<Note.ID>,
        by ticks: Tick,
        pitch transform: (MIDINote) -> MIDINote,
        in track: inout Track,
        timeSignature: TimeSignature,
        totalTicks: Tick
    ) -> [Note.ID] {
        let moving = track.notes.filter { ids.contains($0.id) }
        guard let groupStart = moving.map(\.start).min(), let groupEnd = moving.map(\.end).max() else { return [] }
        let delta = min(max(ticks, -groupStart), max(totalTicks - groupEnd, -groupStart))

        // 選んだ音を、タイでつながった一続きごとに分ける
        var chains: [[Note]] = []
        var seen = Set<Note.ID>()
        for note in moving where !seen.contains(note.id) {
            let chain = tiedChain(containing: note.id, in: moving)
            seen.formUnion(chain.map(\.id))
            chains.append(chain)
        }
        let moves = chains.map { chain -> (range: Range<Tick>, pitch: MIDINote?) in
            let pitch = chain[0].pitch.map { min(max(transform($0), 0), 127) }
            return ((chain[0].start + delta)..<(chain[chain.count - 1].end + delta), pitch)
        }
        let unchanged = delta == 0 && zip(chains, moves).allSatisfy { $0.0[0].pitch == $0.1.pitch }
        guard !unchanged else { return moving.map(\.id) }

        var layered = track
        let placed = placeLayered(ids: ids, moving: moving, moves: moves, in: &layered, timeSignature: timeSignature)
        if !Notation.assignVoices(layered.notes).overflows {
            track = layered
            return placed
        }
        return placeJoined(ids: ids, moving: moving, moves: moves, in: &track, timeSignature: timeSignature)
    }

    /// 移動の下ごしらえ：選んだ音を消し、移動先で同じ高さの音・休符を上書きし、手前の音からのタイを外す。
    /// - Returns: 元の位置で重なっていた音と、移動先（タイの一続きは1つの長い音として。同じ位置・同じ高さには重ねない）。
    private static func prepareMove(
        ids: Set<Note.ID>, moving: [Note], moves: [(range: Range<Tick>, pitch: MIDINote?)], in track: inout Track
    ) -> (vacated: Set<Note.ID>, targets: [Note]) {
        // 元の位置で重なっていた音（和音のために分けてタイでつないでいた音）。跡に残るので、あとで切れ端をまとめ直す
        let vacated = Set(track.notes.filter { note in
            !ids.contains(note.id) && !note.isRest && moving.contains { $0.start < note.end && note.start < $0.end }
        }.map(\.id))
        delete(ids: ids, in: &track)

        // 動かした音（タイの一続きは1つの長い音として扱い、最後に分ける）。同じ位置・同じ高さには重ねない
        var occupied = Set<[Int]>()
        let targets = moves
            .map { Note(start: $0.range.lowerBound, duration: $0.range.count, pitch: $0.pitch) }
            .filter { occupied.insert([$0.start, $0.pitch ?? -1]).inserted }
        let targetNotes = targets.filter { !$0.isRest }

        // 移動先と重なる音（1）：同じ高さの音・休符とは重ねられないので、消すか手前で切り詰める（上書き）
        track.notes = track.notes.compactMap { note in
            let overwriting = targets.filter {
                $0.start < note.end && note.start < $0.end && ($0.isRest || note.isRest || $0.pitch == note.pitch)
            }
            guard let firstStart = overwriting.map(\.start).min() else { return note }
            guard note.start < firstStart else { return nil }
            var trimmed = note
            trimmed.duration = firstStart - note.start
            trimmed.tiesToNext = false
            return trimmed
        }
        // 前の音から動かした音へのタイは外す
        for index in track.notes.indices where track.notes[index].tiesToNext {
            if let pitch = track.notes[index].pitch, targetNotes.contains(where: { $0.pitch == pitch && $0.start == track.notes[index].end }) {
                track.notes[index].tiesToNext = false
            }
        }

        return (vacated, targets)
    }

    /// 重ねて置く：移動先で別の高さの音と重なっても、どちらも切らない（譜面では2つの声部に分けて描く）。
    /// 元の位置や移動先で重なる音のタイの切れ端は、1つにまとめてから小節線で分け直す。
    private static func placeLayered(
        ids: Set<Note.ID>, moving: [Note], moves: [(range: Range<Tick>, pitch: MIDINote?)],
        in track: inout Track, timeSignature: TimeSignature
    ) -> [Note.ID] {
        let (vacated, targets) = prepareMove(ids: ids, moving: moving, moves: moves, in: &track)
        let targetNotes = targets.filter { !$0.isRest }
        var merged: [Note] = []
        var mergedIDs = Set<Note.ID>()
        for note in track.notes where !note.isRest && !mergedIDs.contains(note.id)
            && (vacated.contains(note.id) || targetNotes.contains { $0.start < note.end && note.start < $0.end }) {
            let chain = tiedChain(containing: note.id, in: track.notes)
            mergedIDs.formUnion(chain.map(\.id))
            merged.append(Note(id: chain[0].id, start: chain[0].start, duration: chain[chain.count - 1].end - chain[0].start,
                               pitch: chain[0].pitch))
        }
        track.notes.removeAll { mergedIDs.contains($0.id) }
        track.notes += merged.flatMap { cut($0, at: [], timeSignature: timeSignature) }
        let placed = targets.flatMap { target in
            target.isRest
                ? split(target.start..<target.end, timeSignature: timeSignature).map { Note.rest(start: $0.lowerBound, duration: $0.count) }
                : cut(target, at: [], timeSignature: timeSignature)
        }
        track.notes += placed
        removeDanglingTies(&track.notes)
        sort(&track.notes)
        return placed.map(\.id)
    }

    /// 和音にして置く：重なる音どうしを互いの境目で分けてタイでつなぎ、同じ声部の和音にする。
    /// 重ねて置くと声部が2つに収まらないとき（3つ以上の長さが重なるとき）に使う。
    private static func placeJoined(
        ids: Set<Note.ID>, moving: [Note], moves: [(range: Range<Tick>, pitch: MIDINote?)],
        in track: inout Track, timeSignature: TimeSignature
    ) -> [Note.ID] {
        let (vacated, targets) = prepareMove(ids: ids, moving: moving, moves: moves, in: &track)
        let targetNotes = targets.filter { !$0.isRest }
        // 移動先と重なる音（2）：別の高さの音とは和音にする。開始位置や長さが違えば、互いの境目で分けてタイでつなぐ
        // （例：全音符の途中へ動かすと、全音符は2つに分かれてタイでつながる）。
        // 関わる音（重なる音と、それに重なる音、元の位置で重なっていた音）は、タイの一続きを1つにまとめてから分け直すので、
        // 何度動かしても切れ端が増えない
        var involved = Set<Note.ID>()
        var frontier = track.notes.filter { note in
            !note.isRest && (vacated.contains(note.id) || targetNotes.contains { $0.start < note.end && note.start < $0.end })
        }
        while let note = frontier.popLast() {
            guard !involved.contains(note.id) else { continue }
            for member in tiedChain(containing: note.id, in: track.notes) where !involved.contains(member.id) {
                involved.insert(member.id)
                frontier += track.notes.filter { other in
                    !other.isRest && !involved.contains(other.id) && other.start < member.end && member.start < other.end
                }
            }
        }
        var merged: [Note] = []
        var mergedIDs = Set<Note.ID>()
        for note in track.notes where involved.contains(note.id) && !mergedIDs.contains(note.id) {
            let chain = tiedChain(containing: note.id, in: track.notes)
            mergedIDs.formUnion(chain.map(\.id))
            merged.append(Note(id: chain[0].id, start: chain[0].start, duration: chain[chain.count - 1].end - chain[0].start,
                               pitch: chain[0].pitch))
        }
        let boundaries = Set((merged + targetNotes).flatMap { [$0.start, $0.end] })
        track.notes.removeAll { involved.contains($0.id) }
        track.notes += merged.flatMap { cut($0, at: boundaries, timeSignature: timeSignature) }

        var placed: [Note] = []
        for target in targets {
            if target.isRest {
                placed += split(target.start..<target.end, timeSignature: timeSignature).map { Note.rest(start: $0.lowerBound, duration: $0.count) }
            } else {
                placed += cut(target, at: boundaries, timeSignature: timeSignature)
            }
        }
        track.notes += placed
        removeDanglingTies(&track.notes)
        sort(&track.notes)
        return placed.map(\.id)
    }

    /// 音符を、内側にある境目と小節線で分け、タイでつなぐ（最初の部分は元の ID、最後の部分は元のタイを引き継ぐ）。
    static func cut(_ note: Note, at boundaries: Set<Tick>, timeSignature: TimeSignature) -> [Note] {
        let points = [note.start] + boundaries.filter { $0 > note.start && $0 < note.end }.sorted() + [note.end]
        var pieces: [Note] = []
        for index in 0..<(points.count - 1) {
            for segment in split(points[index]..<points[index + 1], timeSignature: timeSignature) {
                pieces.append(Note(start: segment.lowerBound, duration: segment.count, pitch: note.pitch, tiesToNext: true))
            }
        }
        guard pieces.count > 1 else { return [pieces.first ?? note].map { var single = $0; single.id = note.id; single.tiesToNext = note.tiesToNext; return single } }
        pieces[0].id = note.id
        pieces[pieces.count - 1].tiesToNext = note.tiesToNext
        return pieces
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
