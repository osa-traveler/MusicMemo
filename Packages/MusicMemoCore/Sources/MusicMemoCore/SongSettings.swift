import Foundation

/// 曲の設定（キー・拍子・テンポ・小節数）の変更。曲の他の部分（音符・コード・セクション・再生範囲）もあわせて直す。
public enum SongSettings {
    public static let tempoRange = 40...240
    public static let barCountRange = 1...999
    /// 選べる拍子（連桁を拍ごとにまとめるので、x/4 だけ）。
    public static let timeSignatures = [
        TimeSignature(beats: 2, beatUnit: 4),
        TimeSignature(beats: 3, beatUnit: 4),
        TimeSignature(beats: 4, beatUnit: 4),
    ]

    // MARK: キー

    /// 主音から主音への移調の半音数。近い方向（-5…+6）にする。
    public static func transposition(from old: Key, to new: Key) -> Int {
        let up = Pitch.mod12(new.tonic - old.tonic)
        return up > 6 ? up - 12 : up
    }

    /// キーを変える。transpose が true なら、音符とコードを主音の差だけ移調する（近い方向）。
    /// false なら音の高さはそのままで、調号と綴りだけが変わる。
    public static func setKey(_ key: Key, transpose: Bool, in sketch: inout Sketch) {
        let semitones = transposition(from: sketch.key, to: key)
        sketch.key = key
        guard transpose, semitones != 0 else { return }
        for index in sketch.tracks.indices {
            transposeNotes(&sketch.tracks[index].notes, by: semitones)
        }
        for index in sketch.chords.indices {
            var chord = sketch.chords[index].chord
            chord.root = Pitch.mod12(chord.root + semitones)
            chord.bass = chord.bass.map { Pitch.mod12($0 + semitones) }
            chord.prefersFlats = key.prefersFlats
            sketch.chords[index].chord = chord
        }
    }

    /// 音符を移調する。MIDI の範囲（0…127）を出る音はオクターブずらして収める。
    static func transposeNotes(_ notes: inout [Note], by semitones: Int) {
        for index in notes.indices {
            guard var pitch = notes[index].pitch.map({ $0 + semitones }) else { continue }
            while pitch > 127 { pitch -= 12 }
            while pitch < 0 { pitch += 12 }
            notes[index].pitch = pitch
        }
    }

    // MARK: 拍子

    /// 拍子を変える。音符とコードの時刻はそのままで、小節線だけ引き直す（小節線をまたぐ音はタイで分ける）。
    /// 小節数は曲の長さが収まるよう増減し、セクションの境目は一番近い小節線に寄せる。
    public static func setTimeSignature(_ time: TimeSignature, in sketch: inout Sketch) {
        let old = sketch.timeSignature
        guard time != old else { return }
        let oldTotal = sketch.totalTicks
        sketch.timeSignature = time
        sketch.barCount = max(Int((Double(oldTotal) / Double(time.ticksPerBar)).rounded(.up)), 1)

        for index in sketch.tracks.indices {
            sketch.tracks[index].notes = rebarred(sketch.tracks[index].notes, timeSignature: time)
        }

        // セクション：境目（開始・終わりの時刻）を一番近い小節線に寄せる。曲の終わりは新しい最後の小節に合わせる
        let barCount = sketch.barCount
        let boundaryBar = { (tick: Tick) -> Int in
            tick >= oldTotal ? barCount + 1 : Int((Double(tick) / Double(time.ticksPerBar)).rounded()) + 1
        }
        sketch.sections = sketch.sections.compactMap { section in
            let start = boundaryBar(old.startTick(ofBar: section.startBar))
            let end = boundaryBar(old.startTick(ofBar: section.startBar + section.barCount))
            guard end > start, start <= barCount else { return nil }
            var moved = section
            moved.startBar = start
            moved.barCount = min(end, barCount + 1) - start
            return moved
        }
        clampPlayRange(in: &sketch)
    }

    /// 新しい小節線で音符を分け直す。タイでつながった音は1つにまとめてから分けるので、古い小節線での切れ目は残らない。
    static func rebarred(_ notes: [Note], timeSignature: TimeSignature) -> [Note] {
        var result: [Note] = []
        var done = Set<Note.ID>()
        for note in notes where !done.contains(note.id) {
            if note.isRest {
                done.insert(note.id)
                result += NoteEditing.split(note.start..<note.end, timeSignature: timeSignature).enumerated().map { offset, range in
                    Note.rest(id: offset == 0 ? note.id : UUID(), start: range.lowerBound, duration: range.count)
                }
                continue
            }
            let chain = NoteEditing.tiedChain(containing: note.id, in: notes)
            done.formUnion(chain.map(\.id))
            let merged = Note(id: chain[0].id, start: chain[0].start, duration: chain[chain.count - 1].end - chain[0].start,
                              pitch: chain[0].pitch)
            result += NoteEditing.cut(merged, at: [], timeSignature: timeSignature)
        }
        NoteEditing.sort(&result)
        return result
    }

    // MARK: テンポ

    public static func setTempo(_ tempo: Double, in sketch: inout Sketch) {
        sketch.tempo = min(max(tempo, Double(tempoRange.lowerBound)), Double(tempoRange.upperBound))
    }

    // MARK: 小節数

    /// 小節数を減らしたときに消える音符の数（休符とタイの続きは数えない）。
    public static func notesRemoved(byBarCount count: Int, in sketch: Sketch) -> Int {
        let end = count * sketch.timeSignature.ticksPerBar
        return sketch.tracks.reduce(0) { total, track in
            total + track.notes.filter { note in
                !note.isRest && note.start >= end
                    && !track.notes.contains { $0.tiesToNext && $0.pitch == note.pitch && $0.end == note.start }
            }.count
        }
    }

    /// 小節数を変える。
    /// - 減らすと、終わりより後ろの音符とコードは消え、終わりをまたぐ音符は終わりで切る。セクションは末尾で切り、範囲外のものは消す
    /// - 増やすと、最後のセクションが曲の終わりまで続いていたら、それを延ばす
    public static func setBarCount(_ count: Int, in sketch: inout Sketch) {
        let count = min(max(count, barCountRange.lowerBound), barCountRange.upperBound)
        let oldCount = sketch.barCount
        guard count != oldCount else { return }
        sketch.barCount = count
        let end = sketch.totalTicks

        if count < oldCount {
            for index in sketch.tracks.indices {
                NoteEditing.clear(&sketch.tracks[index].notes, from: end, to: .max)
                NoteEditing.removeDanglingTies(&sketch.tracks[index].notes)
            }
            sketch.chords.removeAll { $0.start >= end }
            sketch.sections = sketch.sections.compactMap { section in
                guard section.startBar <= count else { return nil }
                var clipped = section
                clipped.barCount = min(section.barCount, count - section.startBar + 1)
                return clipped
            }
        } else if let lastIndex = sketch.sections.indices.max(by: { sketch.sections[$0].startBar < sketch.sections[$1].startBar }),
                  sketch.sections[lastIndex].bars.upperBound == oldCount {
            sketch.sections[lastIndex].barCount = count - sketch.sections[lastIndex].startBar + 1
        }
        clampPlayRange(in: &sketch)
    }

    /// 再生範囲を曲の中に収める。収まらなければ曲全体にする。
    static func clampPlayRange(in sketch: inout Sketch) {
        let total = sketch.totalTicks
        let lower = min(sketch.playRange.lowerBound, total)
        let upper = min(sketch.playRange.upperBound, total)
        sketch.playRange = lower < upper ? lower..<upper : 0..<total
    }
}
