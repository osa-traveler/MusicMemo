import Testing
@testable import MusicMemoCore

struct NotationTests {
    let time = TimeSignature.common

    @Test(arguments: [
        (1920, NoteDuration(.whole)),
        (1440, NoteDuration(.half, dotted: true)),
        (960, NoteDuration(.half)),
        (720, NoteDuration(.quarter, dotted: true)),
        (480, NoteDuration(.quarter)),
        (320, NoteDuration(.quarter, triplet: true)),
        (240, NoteDuration(.eighth)),
        (160, NoteDuration(.eighth, triplet: true)),
        (120, NoteDuration(.sixteenth)),
        (600, NoteDuration(.quarter)),  // 1つで書けない長さは超えない最大
    ])
    func valueFromTicks(ticks: Tick, expected: NoteDuration) {
        #expect(NoteDuration(ticks: ticks) == expected)
    }

    @Test func groupsChordsAndSortsHeads() {
        let notes = [
            Note(start: 0, duration: 1920, pitch: 72),
            Note(start: 0, duration: 1920, pitch: 64),
            Note(start: 0, duration: 1920, pitch: 67),
        ]
        let chords = Notation.chords(for: notes, clef: .treble, key: .cMajor, timeSignature: time)
        #expect(chords.count == 1)
        #expect(chords[0].heads.map(\.staffPosition) == [0, 2, 5])  // E4 G4 C5
        #expect(chords[0].value == NoteDuration(.whole))
    }

    @Test func stemDirection() {
        #expect(Notation.stemDirectionUp(positions: [0]) == true)      // E4 → 上向き
        #expect(Notation.stemDirectionUp(positions: [4]) == false)     // B4（真ん中の線）→ 下向き
        #expect(Notation.stemDirectionUp(positions: [6]) == false)     // D5 → 下向き
        #expect(Notation.stemDirectionUp(positions: [-1, 7]) == true)  // 下の方が遠い
    }

    @Test func accidentalsLastUntilBarLine() {
        let notes = [
            Note(start: 0, duration: 480, pitch: 66),     // F#4 → ♯
            Note(start: 480, duration: 480, pitch: 66),   // F#4 → 省略
            Note(start: 960, duration: 480, pitch: 65),   // F4 → ナチュラル
            Note(start: 1920, duration: 480, pitch: 66),  // 次の小節の F#4 → ♯
        ]
        let chords = Notation.chords(for: notes, clef: .treble, key: .cMajor, timeSignature: time)
        #expect(chords.map { $0.heads[0].accidental } == [1, nil, 0, 1])
    }

    @Test func keySignatureSuppressesAccidentals() {
        let gMajor = Key(tonic: 7, mode: .major)
        let notes = [
            Note(start: 0, duration: 480, pitch: 66),    // F#4 → 調号どおり
            Note(start: 480, duration: 480, pitch: 65),  // F4 → ナチュラル
        ]
        let chords = Notation.chords(for: notes, clef: .treble, key: gMajor, timeSignature: time)
        #expect(chords.map { $0.heads[0].accidental } == [nil, 0])
    }

    @Test func secondsAreDisplaced() {
        let notes = [64, 65, 67].map { Note(start: 0, duration: 480, pitch: $0) }  // E4 F4 G4
        let chord = Notation.chords(for: notes, clef: .treble, key: .cMajor, timeSignature: time)[0]
        #expect(chord.stemUp)
        #expect(chord.heads.map(\.isDisplaced) == [false, true, false])
    }

    @Test func ledgerLines() {
        let notes = [Note(start: 0, duration: 480, pitch: 57), Note(start: 480, duration: 480, pitch: 84)]  // A3, C6
        let chords = Notation.chords(for: notes, clef: .treble, key: .cMajor, timeSignature: time)
        #expect(chords[0].ledgerLinePositions == [-2, -4])
        #expect(chords[1].ledgerLinePositions == [10, 12])
    }

    @Test func rests() {
        let chords = Notation.chords(for: [.rest(start: 0, duration: 480)], clef: .treble, key: .cMajor, timeSignature: time)
        #expect(chords[0].isRest)
        #expect(chords[0].value == NoteDuration(.quarter))
    }

    @Test func sampleMelody() {
        let sketch = SampleData.sketch03()
        let chords = Notation.chords(for: sketch.tracks[0].notes, clef: .treble, key: sketch.key, timeSignature: sketch.timeSignature)
        #expect(chords.map { $0.heads[0].staffPosition } == [0, 2, 7, 6, 5, 3])  // E4 G4 E5 D5 C5 A4
        #expect(chords.map(\.stemUp) == [true, true, false, false, false, true])
    }
}
