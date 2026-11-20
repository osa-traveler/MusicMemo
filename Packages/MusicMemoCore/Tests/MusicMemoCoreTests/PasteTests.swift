import Foundation
import Testing
@testable import MusicMemoCore

/// 貼り付け（NoteEditing.paste）：重ねて貼る、タイの一続き、小節線、曲の終わり、声部、ドラム。
struct PasteTests {
    private let time = TimeSignature.common
    private func shape(_ notes: [Note]) -> [[Int]] {
        notes.map { [$0.start, $0.duration, $0.pitch ?? -1, $0.tiesToNext ? 1 : 0] }.sorted { $0.lexicographicallyPrecedes($1) }
    }

    @Test func pastesCopyWithNewIDsAtOffset() {
        let phrase = [Note(start: 0, duration: 480, pitch: 60), Note(start: 480, duration: 480, pitch: 64)]
        var track = Track(name: "P", role: .melody, color: .blue, notes: phrase)
        let ids = NoteEditing.paste(phrase, offset: 1920, in: &track, timeSignature: time, totalTicks: 1920 * 4)
        #expect(shape(track.notes) == [[0, 480, 60, 0], [480, 480, 64, 0], [1920, 480, 60, 0], [2400, 480, 64, 0]])
        #expect(ids.count == 2)
        #expect(Set(ids).isDisjoint(with: phrase.map(\.id)))
    }

    @Test func layersOverDifferentPitchesAndOverwritesSamePitch() {
        // 貼る先に全音符の E（別の高さ → 残して重ねる）と、2拍目に C（同じ高さ → 上書き）
        var track = Track(name: "P", role: .melody, color: .blue, notes: [
            Note(start: 1920, duration: 1920, pitch: 64), Note(start: 2400, duration: 480, pitch: 60),
        ])
        NoteEditing.paste([Note(start: 0, duration: 960, pitch: 60)], offset: 1920, in: &track, timeSignature: time, totalTicks: 1920 * 4)
        #expect(shape(track.notes) == [[1920, 960, 60, 0], [1920, 1920, 64, 0]])
        #expect(!Notation.assignVoices(track.notes).overflows)
    }

    @Test func tiedChainsAreSplitAtNewBarlines() {
        // 3拍目からの2分＋タイ＋2分（小節をまたぐ）を、1拍ずらして貼る → 4拍目から 4分＋タイ＋2分＋タイ＋4分
        let chain = [Note(start: 960, duration: 960, pitch: 67, tiesToNext: true), Note(start: 1920, duration: 960, pitch: 67)]
        var track = Track(name: "P", role: .melody, color: .blue)
        NoteEditing.paste(chain, offset: 480, in: &track, timeSignature: time, totalTicks: 1920 * 4)
        #expect(shape(track.notes) == [[1440, 480, 67, 1], [1920, 1440, 67, 0]])
    }

    @Test func clipsAtTheEndOfTheSong() {
        var track = Track(name: "P", role: .melody, color: .blue)
        let ids = NoteEditing.paste([Note(start: 0, duration: 960, pitch: 60), Note(start: 960, duration: 960, pitch: 62)],
                                    offset: 1920 + 1440, in: &track, timeSignature: time, totalTicks: 1920 * 2)
        #expect(shape(track.notes) == [[3360, 480, 60, 0]])
        #expect(ids.count == 1)
    }

    @Test func joinsIntoChordsWhenVoicesOverflow() {
        // 全音符と2分音符が重なる所へ4分を貼る → 3つの長さが重なるので和音にまとめる
        var track = Track(name: "P", role: .melody, color: .blue, notes: [
            Note(start: 0, duration: 1920, pitch: 48), Note(start: 0, duration: 960, pitch: 60),
        ])
        NoteEditing.paste([Note(start: 0, duration: 480, pitch: 72)], offset: 0, in: &track, timeSignature: time, totalTicks: 1920)
        #expect(!Notation.assignVoices(track.notes).overflows)
        #expect(track.notes.filter { $0.pitch == 72 }.count == 1)
    }

    @Test func drumsAreLayeredWithoutJoining() {
        var drums = Track(name: "D", role: .drums, clef: .percussion, color: .gray, notes: [
            Note(start: 0, duration: 960, pitch: 36), Note(start: 0, duration: 240, pitch: 42),
        ])
        NoteEditing.paste([Note(start: 0, duration: 480, pitch: 38)], offset: 0, in: &drums, timeSignature: time, totalTicks: 1920)
        #expect(drums.notes.allSatisfy { !$0.tiesToNext })
        #expect(drums.notes.count == 3)
    }
}
