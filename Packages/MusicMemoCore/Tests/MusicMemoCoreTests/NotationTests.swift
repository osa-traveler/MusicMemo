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

struct BeamAndTupletTests {
    let time = TimeSignature.common

    func chords(_ notes: [Note]) -> [NotatedChord] {
        Notation.chords(for: notes, clef: .treble, key: .cMajor, timeSignature: time)
    }

    @Test func beamsEighthsWithinBeat() {
        // 1拍目に8分×2、2拍目に8分×2、3拍目は4分 → 2つのまとまり
        var list = chords([
            Note(start: 0, duration: 240, pitch: 64), Note(start: 240, duration: 240, pitch: 65),
            Note(start: 480, duration: 240, pitch: 67), Note(start: 720, duration: 240, pitch: 69),
            Note(start: 960, duration: 480, pitch: 71),
        ])
        #expect(Notation.beamGroups(&list, timeSignature: time) == [[0, 1], [2, 3]])
    }

    @Test func restBreaksBeam() {
        var list = chords([
            Note(start: 0, duration: 240, pitch: 64), .rest(start: 240, duration: 240),
        ])
        #expect(Notation.beamGroups(&list, timeSignature: time).isEmpty)
    }

    @Test func groupStemDirection() {
        // E4（真ん中の線から4段下）と A5（6段上）：A5 の方が遠い → まとまり全体で下向き
        var list = chords([Note(start: 0, duration: 240, pitch: 64), Note(start: 240, duration: 240, pitch: 81)])
        _ = Notation.beamGroups(&list, timeSignature: time)
        #expect(list.map(\.stemUp) == [false, false])
    }

    @Test func tiesAreCarried() {
        let list = chords([Note(start: 0, duration: 480, pitch: 64, tiesToNext: true), Note(start: 480, duration: 480, pitch: 64)])
        #expect(list[0].heads[0].tiesToNext)
        #expect(list[0].end == 480)
    }

    @Test func tripletGroups() {
        let triplet = NoteDuration(.eighth, triplet: true).ticks  // 160
        let notes = (0..<6).map { Note(start: $0 * triplet, duration: triplet, pitch: 64) }
        #expect(Notation.tupletGroups(chords(notes)) == [[0, 1, 2], [3, 4, 5]])
    }

    // MARK: 声部

    @Test func melodyIsOneVoice() {
        let notes = [Note(start: 0, duration: 480, pitch: 60), Note(start: 480, duration: 480, pitch: 62),
                     Note(start: 960, duration: 960, pitch: 64), Note(start: 960, duration: 960, pitch: 67)]
        let assignment = Notation.assignVoices(notes)
        #expect(assignment.voices.count == 1)
        #expect(!assignment.overflows)
    }

    @Test func overlappingNoteGoesToSecondVoiceAndTieStaysThere() {
        // C E 全音符、G は3拍目から2分＋（次の小節）2分のタイ。次の小節の G も2つ目の声部のまま
        let notes = [Note(start: 0, duration: 1920, pitch: 60), Note(start: 0, duration: 1920, pitch: 64),
                     Note(start: 960, duration: 960, pitch: 67, tiesToNext: true), Note(start: 1920, duration: 960, pitch: 67)]
        let assignment = Notation.assignVoices(notes)
        #expect(assignment.voices.map { $0.map(\.pitch!) } == [[60, 64], [67, 67]])
    }

    @Test func sameStartDifferentLengthSplitsVoices() {
        let notes = [Note(start: 0, duration: 480, pitch: 67), Note(start: 0, duration: 1920, pitch: 60)]
        let assignment = Notation.assignVoices(notes)
        #expect(assignment.voices.map { $0.map(\.pitch!) } == [[60], [67]])  // 長い方が先の声部
    }

    @Test func threeLayersOverflow() {
        let notes = [Note(start: 0, duration: 1920, pitch: 60), Note(start: 480, duration: 1440, pitch: 64),
                     Note(start: 960, duration: 480, pitch: 67)]
        #expect(Notation.assignVoices(notes).overflows)
    }

    @Test func voicesFixStemsByHeight() {
        // C E 全音符（下の声部）と、3拍目からの G 4分（上の声部）→ G は上向き、C E は下向き
        let notes = [Note(start: 0, duration: 1920, pitch: 60), Note(start: 0, duration: 1920, pitch: 64),
                     Note(start: 960, duration: 480, pitch: 67)]
        let voices = Notation.voices(for: notes, clef: .treble, key: .cMajor, timeSignature: .common)
        #expect(voices.count == 2)
        #expect(voices[0].chords.map(\.stemUp) == [false])
        #expect(voices[1].chords.map(\.stemUp) == [true])
        #expect(voices[0].chords[0].value == NoteDuration(.whole))
    }

    @Test func accidentalsCountAcrossVoices() {
        // 声部2の F♯（2拍目）のあと、声部1の F（3拍目）にはナチュラル
        let notes = [Note(start: 0, duration: 1920, pitch: 60), Note(start: 480, duration: 480, pitch: 66),
                     Note(start: 960, duration: 480, pitch: 65)]
        let voices = Notation.voices(for: notes, clef: .treble, key: .cMajor, timeSignature: .common)
        let heads = voices.flatMap(\.chords).flatMap { chord in chord.heads.map { (chord.start, $0) } }
        #expect(heads.first { $0.0 == 480 }?.1.accidental == 1)
        #expect(heads.first { $0.0 == 960 }?.1.accidental == 0)
    }

    @Test func collidingSecondShiftsDownStemVoice() {
        // 同じ位置で E（全音符、下の声部）と F（4分、上の声部）→ 2度でぶつかる → 下向きの声部（E）を右へ
        let notes = [Note(start: 0, duration: 1920, pitch: 64), Note(start: 0, duration: 480, pitch: 65)]
        let voices = Notation.voices(for: notes, clef: .treble, key: .cMajor, timeSignature: .common)
        #expect(voices[0].chords[0].shift == 1)
        #expect(voices[1].chords[0].shift == 0)
    }
}
