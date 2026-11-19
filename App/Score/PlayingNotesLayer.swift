import MusicMemoCore
import SwiftUI

/// 再生中に、再生位置で鳴っている音符の符頭を赤（再生位置の色）で上から描く。五線（StaffRowView）の上に重ねる。
/// 再生位置は毎フレーム変わるので、ここで読む。描き直すのは、鳴っている音符の組み合わせが変わったときだけ（PlayingHeads）。
struct PlayingNotesLayer: View {
    let store: SketchStore
    let track: Track
    let key: Key
    let layout: ScoreLayout
    let rowHeight: CGFloat
    /// ミュート・ソロで、このトラックが鳴っているか。
    let isAudible: Bool

    var body: some View {
        PlayingHeads(groups: groups, layout: layout, rowHeight: rowHeight)
            .equatable()
            .allowsHitTesting(false)
    }

    /// 鳴っている符頭（記譜した和音と、その中の鳴っている音高）。
    private var groups: [PlayingHeads.Group] {
        guard isAudible, let tick = store.playheadTick else { return [] }
        let sounding = Self.soundingNotes(track.notes, at: tick, timeSignature: layout.timeSignature)
        guard !sounding.isEmpty else { return [] }
        let chords = StaffRowView.notation(of: track, key: key, timeSignature: layout.timeSignature).chords
        return chords.compactMap { chord in
            let pitches = Set(sounding.filter { $0.start == chord.start && $0.end == chord.end }.compactMap(\.pitch))
            let heads = pitches.intersection(chord.heads.map(\.pitch))
            return heads.isEmpty ? nil : PlayingHeads.Group(chord: chord, pitches: heads)
        }
    }

    /// tick で鳴っている音符（休符は除く）。音符は開始位置の順に並び、小節線をまたがない（またぐ音はタイで分けてある）ので、
    /// tick の小節の頭より後ろで始まる音符だけを見る。
    static func soundingNotes(_ notes: [Note], at tick: Tick, timeSignature: TimeSignature) -> [Note] {
        // tick より後ろで始まる最初の音符
        var low = 0, high = notes.count
        while low < high {
            let mid = (low + high) / 2
            if notes[mid].start <= tick { low = mid + 1 } else { high = mid }
        }
        let barStart = timeSignature.startTick(ofBar: timeSignature.bar(containing: tick))
        var result: [Note] = []
        var index = low - 1
        while index >= 0, notes[index].start >= barStart {
            let note = notes[index]
            if note.pitch != nil, note.end > tick { result.append(note) }
            index -= 1
        }
        return result
    }
}

/// 鳴っている符頭を描く。鳴っている音符が変わったときだけ描き直す。描く範囲は符頭のまわりだけ（行の幅全体の絵にしない）。
private struct PlayingHeads: View, Equatable {
    struct Group: Hashable {
        var chord: NotatedChord
        var pitches: Set<MIDINote>
    }

    let groups: [Group]
    let layout: ScoreLayout
    let rowHeight: CGFloat

    var body: some View {
        if let first = groups.first {
            let xs = groups.map { layout.x(tick: $0.chord.start) }
            // 符頭の幅・ずらした符頭・選んだ印の円の分だけ広く
            let margin = 40 * layout.zoom
            let minX = (xs.min() ?? layout.x(tick: first.chord.start)) - margin
            let maxX = (xs.max() ?? minX) + margin
            Canvas { context, size in
                var context = context
                context.translateBy(x: -minX, y: 0)
                let drawing = NoteDrawing(layout: layout, bottomLineY: layout.bottomLineY(rowHeight: size.height), color: Palette.playhead)
                for group in groups {
                    drawing.drawSelected(group.chord, pitches: group.pitches, in: context)
                }
            }
            .frame(width: maxX - minX, height: rowHeight)
            .offset(x: minX)
        }
    }
}
