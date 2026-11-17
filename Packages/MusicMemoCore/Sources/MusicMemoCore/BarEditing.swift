import Foundation

/// 曲の途中に小節を足す・消す・写す。後ろの音符・コード・セクション・再生範囲もずらす。
/// 音符は小節線で分けて持っている（またぐ音はタイでつないだ別の音符）ので、小節の境目で切る必要はない。
public enum BarEditing {
    /// bar 小節目の前に、空の小節を count 個足す（bar が 曲の小節数 + 1 なら末尾に足す）。
    /// bar の途中から始まっていたセクション（bar を中に含むセクション）は、その分長くなる。
    public static func insertBars(_ count: Int, before bar: Int, in sketch: inout Sketch) {
        guard count > 0, (1...(sketch.barCount + 1)).contains(bar) else { return }
        let time = sketch.timeSignature
        let point = time.startTick(ofBar: bar)
        let delta = count * time.ticksPerBar

        for index in sketch.tracks.indices {
            sketch.tracks[index].notes = sketch.tracks[index].notes.map { note in
                var moved = note
                if note.start >= point { moved.start += delta }
                return moved
            }
            // 足した小節の手前で切れたタイ（続きが後ろへずれた）を外す
            NoteEditing.removeDanglingTies(&sketch.tracks[index].notes)
        }

        // コード：足した小節は手前のコードが続く（コードは次のコードまで持続する）。後ろのコードはずらす
        for index in sketch.chords.indices where sketch.chords[index].start >= point {
            sketch.chords[index].start += delta
        }

        for index in sketch.sections.indices {
            let section = sketch.sections[index]
            if section.startBar >= bar {
                sketch.sections[index].startBar += count
            } else if section.bars.contains(bar) {
                sketch.sections[index].barCount += count
            }
        }

        sketch.barCount += count
        sketch.playRange = shift(sketch.playRange) { $0 >= point ? $0 + delta : $0 }
        SongSettings.clampPlayRange(in: &sketch)
    }

    /// 小節（bars）を消して、後ろを詰める。曲の小節をすべて消すことはできない（何もしない）。
    /// 消した小節で始まったコードが、消した範囲の後ろでも鳴っていた場合は、範囲の頭（詰めた位置）に残す。
    public static func deleteBars(_ bars: ClosedRange<Int>, in sketch: inout Sketch) {
        let bars = max(bars.lowerBound, 1)...min(bars.upperBound, sketch.barCount)
        guard !bars.isEmpty, bars.count < sketch.barCount else { return }
        let time = sketch.timeSignature
        let start = time.startTick(ofBar: bars.lowerBound)
        let end = time.startTick(ofBar: bars.upperBound + 1)
        let delta = end - start

        for index in sketch.tracks.indices {
            var notes: [Note] = []
            for var note in sketch.tracks[index].notes {
                if note.end <= start {
                    // 消す範囲へ続くタイは外す
                    if note.end == start { note.tiesToNext = false }
                    notes.append(note)
                } else if note.start >= end {
                    note.start -= delta
                    notes.append(note)
                } else if note.start < start {
                    // 範囲の手前から食い込む音（小節線で分けているので通常は無い）は手前で切る
                    note.duration = start - note.start
                    note.tiesToNext = false
                    notes.append(note)
                }
                // 範囲の中の音は消す
            }
            NoteEditing.sort(&notes)
            sketch.tracks[index].notes = notes
        }

        let soundingAtEnd = sketch.chord(at: end)
        let keepsChord = soundingAtEnd.map { $0.start >= start && $0.start < end } ?? false
        sketch.chords = sketch.chords.compactMap { event in
            var moved = event
            if event.start >= end {
                moved.start -= delta
                return moved
            }
            if event.start >= start {
                guard keepsChord, event.id == soundingAtEnd?.id else { return nil }
                moved.start = start
                return moved
            }
            return moved
        }
        sketch.chords.sort { $0.start < $1.start }

        let count = bars.count
        sketch.sections = sketch.sections.compactMap { section in
            // セクションの小節のうち、消さずに残る小節を数え直す
            let before = max(min(section.bars.upperBound, bars.lowerBound - 1) - section.startBar + 1, 0)
            let after = max(section.bars.upperBound - max(section.startBar, bars.upperBound + 1) + 1, 0)
            guard before + after > 0 else { return nil }
            var kept = section
            kept.startBar = section.startBar < bars.lowerBound ? section.startBar : max(section.startBar - count, bars.lowerBound)
            kept.barCount = before + after
            return kept
        }

        sketch.barCount -= count
        sketch.playRange = shift(sketch.playRange) { tick in
            tick < start ? tick : tick < end ? start : tick - delta
        }
        SongSettings.clampPlayRange(in: &sketch)
    }

    /// 小節（source）の音符とコードを写して、bar 小節目の前に差し込む。セクションは呼ぶ側で足す。
    /// 写した先の頭で、元の頭で鳴っていたコードが鳴るようにする。
    public static func copyBars(_ source: ClosedRange<Int>, before bar: Int, in sketch: inout Sketch) {
        guard source.lowerBound >= 1, source.upperBound <= sketch.barCount else { return }
        let time = sketch.timeSignature
        let count = source.count
        let sourceStart = time.startTick(ofBar: source.lowerBound)
        let sourceEnd = time.startTick(ofBar: source.upperBound + 1)
        let notes = sketch.tracks.map { track in track.notes.filter { $0.start >= sourceStart && $0.start < sourceEnd } }
        var chords = sketch.chords.filter { $0.start >= sourceStart && $0.start < sourceEnd }
        if !chords.contains(where: { $0.start == sourceStart }), let sounding = sketch.chord(at: sourceStart) {
            chords.insert(ChordEvent(start: sourceStart, chord: sounding.chord), at: 0)
        }

        // 差し込む位置の後ろで鳴っていたコード（差し込む位置にコードが無ければ、手前から続いていたもの）
        let point = time.startTick(ofBar: bar)
        let resumed = bar <= sketch.barCount && !sketch.chords.contains { $0.start == point } ? sketch.chord(at: point) : nil

        insertBars(count, before: bar, in: &sketch)
        let offset = point - sourceStart
        for index in sketch.tracks.indices {
            sketch.tracks[index].notes += notes[index].map { note in
                var copy = note
                copy.id = UUID()
                copy.start += offset
                // 写した範囲の外へ続くタイは外す
                if copy.end == sourceEnd + offset { copy.tiesToNext = false }
                return copy
            }
            NoteEditing.sort(&sketch.tracks[index].notes)
        }
        sketch.chords += chords.map { ChordEvent(start: $0.start + offset, chord: $0.chord) }
        // 写したコードのあとも、元の後ろの部分は元のコードで始まるようにする
        if let resumed {
            sketch.chords.append(ChordEvent(start: point + count * time.ticksPerBar, chord: resumed.chord))
        }
        sketch.chords.sort { $0.start < $1.start }
    }

    private static func shift(_ range: Range<Tick>, _ transform: (Tick) -> Tick) -> Range<Tick> {
        let lower = transform(range.lowerBound)
        let upper = transform(range.upperBound)
        return lower < upper ? lower..<upper : lower..<lower
    }
}
