import Foundation

/// セクションの追加・分割・名前と長さの変更・複製・結合・削除。
/// 長さの変更・複製・削除は、曲の途中の小節を足す・消す（後ろの音符・コード・セクションはずれる）。
public enum SectionEditing {
    /// 名前の候補（ポップオーバーのボタン、新しいセクションの名前）。
    public static let suggestedNames = ["イントロ", "Aメロ", "Bメロ", "サビ", "Cメロ", "間奏", "アウトロ"]
    /// 曲の最後に足すときの小節数。
    public static let defaultBarCount = 8

    /// 新しいセクションの名前。曲の頭ならイントロ以外の候補から、まだ使っていない名前を順に選ぶ。
    public static func nextName(in sketch: Sketch) -> String {
        let used = Set(sketch.sections.map(\.name))
        return suggestedNames.dropFirst().first { !used.contains($0) } ?? "セクション\(sketch.sections.count + 1)"
    }

    /// 開始小節の順に並べたセクション。
    static func sorted(_ sketch: Sketch) -> [SongSection] {
        sketch.sections.sorted { $0.startBar < $1.startBar }
    }

    // MARK: 追加・分割

    /// 曲の最後に小節を足して、そこを新しいセクションにする。足したセクションを返す（小節数の上限を超えるなら nil）。
    @discardableResult
    public static func appendSection(name: String? = nil, barCount: Int = defaultBarCount, in sketch: inout Sketch) -> SongSection? {
        guard barCount > 0, sketch.barCount + barCount <= SongSettings.barCountRange.upperBound else { return nil }
        let section = SongSection(name: name ?? nextName(in: sketch), startBar: sketch.barCount + 1, barCount: barCount)
        BarEditing.insertBars(barCount, before: sketch.barCount + 1, in: &sketch)
        sketch.sections.append(section)
        sketch.sections = sorted(sketch)
        return section
    }

    /// bar 小節目から後ろを新しいセクションに分ける。bar を含むセクションがあればその後ろ半分を、
    /// 無ければ bar から次のセクションの手前（無ければ曲の終わり）までを新しいセクションにする。
    /// bar がセクションの頭なら分けない（nil）。
    @discardableResult
    public static func splitSection(at bar: Int, name: String? = nil, in sketch: inout Sketch) -> SongSection? {
        guard (1...sketch.barCount).contains(bar), !sketch.sections.contains(where: { $0.startBar == bar }) else { return nil }
        let newName = name ?? nextName(in: sketch)
        if let index = sketch.sections.firstIndex(where: { $0.bars.contains(bar) }) {
            let old = sketch.sections[index]
            sketch.sections[index].barCount = bar - old.startBar
            let section = SongSection(name: newName, startBar: bar, barCount: old.bars.upperBound - bar + 1)
            sketch.sections.insert(section, at: index + 1)
            sketch.sections = sorted(sketch)
            return section
        }
        let nextStart = sorted(sketch).first { $0.startBar > bar }?.startBar ?? sketch.barCount + 1
        let section = SongSection(name: newName, startBar: bar, barCount: nextStart - bar)
        sketch.sections.append(section)
        sketch.sections = sorted(sketch)
        return section
    }

    public static func canSplit(at bar: Int, in sketch: Sketch) -> Bool {
        (1...sketch.barCount).contains(bar) && !sketch.sections.contains { $0.startBar == bar }
    }

    // MARK: 名前・長さ

    /// 名前を変える。前後の空白を除き、空なら変えない。
    public static func rename(_ id: SongSection.ID, to name: String, in sketch: inout Sketch) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = sketch.sections.firstIndex(where: { $0.id == id }) else { return }
        sketch.sections[index].name = trimmed
    }

    /// 長さを変えたときに消える音符の数（縮めるときだけ。休符は数えない）。
    public static func notesRemoved(byResizing id: SongSection.ID, to barCount: Int, in sketch: Sketch) -> Int {
        guard let section = sketch.sections.first(where: { $0.id == id }), barCount < section.barCount else { return 0 }
        return notes(inBars: (section.startBar + barCount)...section.bars.upperBound, in: sketch)
    }

    /// 長さを変える。伸ばすとセクションの終わりに空の小節を足し、縮めるとセクションの終わりの小節を消す。後ろはずれる。
    public static func resize(_ id: SongSection.ID, to barCount: Int, in sketch: inout Sketch) {
        guard barCount >= 1, let section = sketch.sections.first(where: { $0.id == id }) else { return }
        let difference = barCount - section.barCount
        if difference > 0 {
            guard sketch.barCount + difference <= SongSettings.barCountRange.upperBound else { return }
            BarEditing.insertBars(difference, before: section.bars.upperBound + 1, in: &sketch)
            if let index = sketch.sections.firstIndex(where: { $0.id == id }) {
                sketch.sections[index].barCount = barCount
            }
        } else if difference < 0 {
            BarEditing.deleteBars((section.bars.upperBound + difference + 1)...section.bars.upperBound, in: &sketch)
        }
    }

    // MARK: 複製・結合・削除

    public static func canDuplicate(_ id: SongSection.ID, in sketch: Sketch) -> Bool {
        guard let section = sketch.sections.first(where: { $0.id == id }) else { return false }
        return sketch.barCount + section.barCount <= SongSettings.barCountRange.upperBound
    }

    /// セクションの中身（音符・コード）を写して、すぐ後ろに同じ名前のセクションとして差し込む。
    @discardableResult
    public static func duplicate(_ id: SongSection.ID, in sketch: inout Sketch) -> SongSection? {
        guard canDuplicate(id, in: sketch), let section = sketch.sections.first(where: { $0.id == id }) else { return nil }
        let copy = SongSection(name: section.name, startBar: section.bars.upperBound + 1, barCount: section.barCount)
        BarEditing.copyBars(section.bars, before: copy.startBar, in: &sketch)
        sketch.sections.append(copy)
        sketch.sections = sorted(sketch)
        return copy
    }

    /// すぐ前のセクション（終わりがこのセクションの頭に接しているもの）。
    public static func previous(of id: SongSection.ID, in sketch: Sketch) -> SongSection? {
        guard let section = sketch.sections.first(where: { $0.id == id }) else { return nil }
        return sketch.sections.first { $0.bars.upperBound + 1 == section.startBar }
    }

    /// 前のセクションとつなげる（区切りをなくす。小節と中身はそのまま）。
    public static func mergeWithPrevious(_ id: SongSection.ID, in sketch: inout Sketch) {
        guard let section = sketch.sections.first(where: { $0.id == id }),
              let previous = previous(of: id, in: sketch),
              let index = sketch.sections.firstIndex(where: { $0.id == previous.id }) else { return }
        sketch.sections[index].barCount += section.barCount
        sketch.sections.removeAll { $0.id == id }
    }

    /// 消せるか（曲の小節をすべて消すことになるなら消せない）。
    public static func canDelete(_ id: SongSection.ID, in sketch: Sketch) -> Bool {
        guard let section = sketch.sections.first(where: { $0.id == id }) else { return false }
        return section.barCount < sketch.barCount
    }

    /// セクションを消したときに消える音符の数。
    public static func notesRemoved(byDeleting id: SongSection.ID, in sketch: Sketch) -> Int {
        guard let section = sketch.sections.first(where: { $0.id == id }) else { return 0 }
        return notes(inBars: section.bars, in: sketch)
    }

    /// セクションを小節ごと消して、後ろを詰める。
    public static func delete(_ id: SongSection.ID, in sketch: inout Sketch) {
        guard canDelete(id, in: sketch), let section = sketch.sections.first(where: { $0.id == id }) else { return }
        BarEditing.deleteBars(section.bars, in: &sketch)
        sketch.sections.removeAll { $0.id == id }
    }

    /// 小節の範囲で始まる音符の数（休符とタイの続きは数えない）。
    static func notes(inBars bars: ClosedRange<Int>, in sketch: Sketch) -> Int {
        let start = sketch.timeSignature.startTick(ofBar: bars.lowerBound)
        let end = sketch.timeSignature.startTick(ofBar: bars.upperBound + 1)
        return sketch.tracks.reduce(0) { total, track in
            total + track.notes.filter { note in
                !note.isRest && note.start >= start && note.start < end
                    && !track.notes.contains { $0.tiesToNext && $0.pitch == note.pitch && $0.end == note.start && $0.start >= start }
            }.count
        }
    }
}
