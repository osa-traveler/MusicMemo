import Foundation
import Testing
@testable import MusicMemoCore

/// 4/4（1小節 = 1920 tick）で試す。
struct SectionEditingTests {
    let bar = 1920

    /// A 1–2、B 3–4 の4小節。各小節の頭に音符、1・3小節目の頭にコード。
    func song() -> Sketch {
        var sketch = Sketch(
            title: "T", barCount: 4,
            sections: [SongSection(name: "A", startBar: 1, barCount: 2), SongSection(name: "B", startBar: 3, barCount: 2)],
            chords: [ChordEvent(start: 0, chord: Chord("C")!), ChordEvent(start: 3840, chord: Chord("G")!)],
            tracks: [Track(name: "T", role: .melody, color: .blue,
                           notes: (0..<4).map { Note(start: $0 * 1920, duration: 480, pitch: 60 + $0) })]
        )
        sketch.playRange = 1920..<5760  // 2–3小節目
        return sketch
    }

    func layout(_ sketch: Sketch) -> [String] {
        sketch.sections.map { "\($0.name)\($0.startBar)+\($0.barCount)" }
    }

    func notes(_ sketch: Sketch) -> [[Int]] {
        sketch.tracks[0].notes.map { [$0.start / bar, $0.pitch ?? -1] }
    }

    func chords(_ sketch: Sketch) -> [String] {
        sketch.chords.map { "\($0.chord.symbol)@\($0.start / bar + 1)" }
    }

    // MARK: 小節の挿入・削除

    @Test func insertShiftsEverythingAfter() {
        var sketch = song()
        BarEditing.insertBars(2, before: 3, in: &sketch)
        #expect(sketch.barCount == 6)
        #expect(notes(sketch) == [[0, 60], [1, 61], [4, 62], [5, 63]])
        #expect(chords(sketch) == ["C@1", "G@5"])
        #expect(layout(sketch) == ["A1+2", "B5+2"])
        #expect(sketch.playRange == 1920..<9600)
    }

    @Test func insertInsideSectionGrowsIt() {
        var sketch = song()
        BarEditing.insertBars(1, before: 2, in: &sketch)
        #expect(layout(sketch) == ["A1+3", "B4+2"])
    }

    @Test func insertDropsTieIntoInsertedBars() {
        var sketch = song()
        sketch.tracks[0].notes = [Note(start: 1440, duration: 480, pitch: 60, tiesToNext: true), Note(start: 1920, duration: 480, pitch: 60)]
        BarEditing.insertBars(1, before: 2, in: &sketch)
        #expect(sketch.tracks[0].notes.map(\.tiesToNext) == [false, false])
    }

    @Test func deleteClosesGapAndKeepsSoundingChord() {
        var sketch = song()
        // 3小節目に F を足す → 3小節目を消すと、4小節目で鳴っていた F を詰めた位置（3小節目）に残す
        sketch.chords.append(ChordEvent(start: 3840 + 960, chord: Chord("F")!))
        BarEditing.deleteBars(3...3, in: &sketch)
        #expect(sketch.barCount == 3)
        #expect(notes(sketch) == [[0, 60], [1, 61], [2, 63]])
        #expect(chords(sketch) == ["C@1", "F@3"])
        #expect(layout(sketch) == ["A1+2", "B3+1"])
        #expect(sketch.playRange == 1920..<3840)
    }

    @Test func deleteAcrossSections() {
        var sketch = song()
        BarEditing.deleteBars(2...3, in: &sketch)
        #expect(layout(sketch) == ["A1+1", "B2+1"])
        #expect(notes(sketch) == [[0, 60], [1, 63]])
        #expect(chords(sketch) == ["C@1", "G@2"])
    }

    @Test func deleteRemovesTieIntoDeletedBars() {
        var sketch = song()
        sketch.tracks[0].notes = [Note(start: 1440, duration: 480, pitch: 60, tiesToNext: true), Note(start: 1920, duration: 480, pitch: 60),
                                  Note(start: 3840, duration: 480, pitch: 60)]
        BarEditing.deleteBars(2...2, in: &sketch)
        // 消した小節の頭へ続いていたタイは外れる（詰めて来た同じ高さの音とつながらない）
        #expect(sketch.tracks[0].notes.map { [$0.start, $0.tiesToNext ? 1 : 0] } == [[1440, 0], [1920, 0]])
    }

    @Test func cannotDeleteAllBars() {
        var sketch = song()
        BarEditing.deleteBars(1...4, in: &sketch)
        #expect(sketch.barCount == 4)
    }

    @Test func copyBarsResumesFollowingChord() {
        var sketch = song()
        // 3小節目（G）を2小節目の前へ写す
        BarEditing.copyBars(3...3, before: 2, in: &sketch)
        #expect(sketch.barCount == 5)
        #expect(notes(sketch) == [[0, 60], [1, 62], [2, 61], [3, 62], [4, 63]])
        // 写した G のあと、元の2小節目は C の続きだったので C を置き直す
        #expect(chords(sketch) == ["C@1", "G@2", "C@3", "G@4"])
        #expect(Set(sketch.tracks[0].notes.map(\.id)).count == 5)
    }

    // MARK: セクション

    @Test func appendAddsBarsAndSection() {
        var sketch = song()
        let section = SectionEditing.appendSection(in: &sketch)
        #expect(section?.name == "Aメロ")  // A・B は候補に無い名前。候補はイントロの次から、使っていない名前
        #expect(sketch.barCount == 12)
        #expect(layout(sketch).last == "Aメロ5+8")
    }

    @Test func nextNameSkipsUsedNames() {
        var sketch = song()
        sketch.sections[0].name = "Aメロ"
        sketch.sections[1].name = "Bメロ"
        #expect(SectionEditing.nextName(in: sketch) == "サビ")
    }

    @Test func splitInsideSectionAndInGap() {
        var sketch = song()
        sketch.sections[1].barCount = 4
        sketch.barCount = 6
        #expect(SectionEditing.splitSection(at: 3, in: &sketch) == nil)  // セクションの頭では分けない
        SectionEditing.splitSection(at: 5, name: "C", in: &sketch)
        #expect(layout(sketch) == ["A1+2", "B3+2", "C5+2"])

        var gap = song()
        gap.sections = [SongSection(name: "A", startBar: 3, barCount: 2)]
        SectionEditing.splitSection(at: 1, name: "Intro", in: &gap)
        #expect(layout(gap) == ["Intro1+2", "A3+2"])
    }

    @Test func resizeGrowsAndShrinksInPlace() {
        var sketch = song()
        let a = sketch.sections[0].id
        SectionEditing.resize(a, to: 4, in: &sketch)
        #expect(layout(sketch) == ["A1+4", "B5+2"])
        #expect(notes(sketch) == [[0, 60], [1, 61], [4, 62], [5, 63]])
        #expect(sketch.barCount == 6)

        #expect(SectionEditing.notesRemoved(byResizing: a, to: 1, in: sketch) == 1)  // 2小節目の音
        SectionEditing.resize(a, to: 1, in: &sketch)
        #expect(layout(sketch) == ["A1+1", "B2+2"])
        #expect(notes(sketch) == [[0, 60], [1, 62], [2, 63]])
    }

    @Test func duplicateCopiesContentAfterSection() {
        var sketch = song()
        SectionEditing.duplicate(sketch.sections[1].id, in: &sketch)
        #expect(layout(sketch) == ["A1+2", "B3+2", "B5+2"])
        #expect(notes(sketch) == [[0, 60], [1, 61], [2, 62], [3, 63], [4, 62], [5, 63]])
        #expect(chords(sketch) == ["C@1", "G@3", "G@5"])
    }

    @Test func mergeKeepsBars() {
        var sketch = song()
        SectionEditing.mergeWithPrevious(sketch.sections[1].id, in: &sketch)
        #expect(layout(sketch) == ["A1+4"])
        #expect(sketch.barCount == 4)
        #expect(SectionEditing.previous(of: sketch.sections[0].id, in: sketch) == nil)
    }

    @Test func deleteSectionRemovesBars() {
        var sketch = song()
        let a = sketch.sections[0].id
        #expect(SectionEditing.notesRemoved(byDeleting: a, in: sketch) == 2)
        SectionEditing.delete(a, in: &sketch)
        #expect(layout(sketch) == ["B1+2"])
        #expect(notes(sketch) == [[0, 62], [1, 63]])
        // 1小節目に C が無くなるので、消した範囲で鳴っていた C は残らず、G から
        #expect(chords(sketch) == ["G@1"])
        #expect(!SectionEditing.canDelete(sketch.sections[0].id, in: sketch))
    }

    @Test func renameTrims() {
        var sketch = song()
        SectionEditing.rename(sketch.sections[0].id, to: "  サビ ", in: &sketch)
        SectionEditing.rename(sketch.sections[1].id, to: "  ", in: &sketch)
        #expect(sketch.sections.map(\.name) == ["サビ", "B"])
    }
}
