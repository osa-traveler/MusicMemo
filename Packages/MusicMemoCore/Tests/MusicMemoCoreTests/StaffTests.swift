import Testing
@testable import MusicMemoCore

struct StaffTests {
    @Test func spellingInCMajor() {
        #expect(SpelledPitch(60, in: .cMajor) == SpelledPitch(letter: 0, alter: 0, octave: 4))   // C4
        #expect(SpelledPitch(61, in: .cMajor) == SpelledPitch(letter: 1, alter: -1, octave: 4))  // Db4
        #expect(SpelledPitch(71, in: .cMajor) == SpelledPitch(letter: 6, alter: 0, octave: 4))   // B4
        #expect(SpelledPitch(72, in: .cMajor) == SpelledPitch(letter: 0, alter: 0, octave: 5))   // C5
    }

    @Test func chromaticSpellingByDegree() {
        // C major：♭III ♭VI ♭VII は♭、♯IV は♯
        #expect(SpelledPitch(63, in: .cMajor) == SpelledPitch(letter: 2, alter: -1, octave: 4))  // Eb4
        #expect(SpelledPitch(66, in: .cMajor) == SpelledPitch(letter: 3, alter: 1, octave: 4))   // F#4
        #expect(SpelledPitch(68, in: .cMajor) == SpelledPitch(letter: 5, alter: -1, octave: 4))  // Ab4
        #expect(SpelledPitch(70, in: .cMajor) == SpelledPitch(letter: 6, alter: -1, octave: 4))  // Bb4
        // A minor：導音は G#、♯VI は F#
        let aMinor = Key(tonic: 9, mode: .minor)
        #expect(SpelledPitch(68, in: aMinor) == SpelledPitch(letter: 4, alter: 1, octave: 4))    // G#4
        #expect(SpelledPitch(66, in: aMinor) == SpelledPitch(letter: 3, alter: 1, octave: 4))    // F#4
        #expect(SpelledPitch(70, in: aMinor) == SpelledPitch(letter: 6, alter: -1, octave: 4))   // Bb4（♭II）
        // D major：♭VII は幹音の C
        #expect(SpelledPitch(72, in: Key(tonic: 2, mode: .major)) == SpelledPitch(letter: 0, alter: 0, octave: 5))
    }

    @Test func spellingFollowsKey() {
        let fMajor = Key(tonic: 5, mode: .major)
        #expect(SpelledPitch(70, in: fMajor) == SpelledPitch(letter: 6, alter: -1, octave: 4))   // Bb4
        #expect(SpelledPitch(61, in: fMajor) == SpelledPitch(letter: 1, alter: -1, octave: 4))   // Db4
        let fSharpMajor = Key(tonic: 6, mode: .major)  // ♯6
        #expect(SpelledPitch(65, in: fSharpMajor) == SpelledPitch(letter: 2, alter: 1, octave: 4))   // E#4
        let dFlatMajor = Key(tonic: 1, mode: .major)  // ♭5
        #expect(SpelledPitch(59, in: dFlatMajor) == SpelledPitch(letter: 6, alter: 0, octave: 3))    // B3（音階外は幹音優先）
    }

    @Test func spellingOctaveBoundary() {
        #expect(SpelledPitch(59, in: .cMajor).octave == 3)
        #expect(SpelledPitch(60, in: .cMajor).octave == 4)
        // 調が変わってもオクターブ番号は C を境に切り替わる
        #expect(SpelledPitch(71, in: Key(tonic: 6, mode: .major)).octave == 4)
    }

    @Test func staffPositions() {
        #expect(Clef.treble.staffPosition(of: SpelledPitch(64, in: .cMajor)) == 0)   // E4 = 第1線
        #expect(Clef.treble.staffPosition(of: SpelledPitch(77, in: .cMajor)) == 8)   // F5 = 第5線
        #expect(Clef.treble.staffPosition(of: SpelledPitch(60, in: .cMajor)) == -2)  // C4 = 下第1線
        #expect(Clef.bass.staffPosition(of: SpelledPitch(43, in: .cMajor)) == 0)     // G2 = 第1線
        #expect(Clef.bass.staffPosition(of: SpelledPitch(57, in: .cMajor)) == 8)     // A3 = 第5線
        #expect(Clef.bass.staffPosition(of: SpelledPitch(60, in: .cMajor)) == 10)    // C4 = 上第1線
    }

    @Test func keySignatures() {
        #expect(KeySignature(.cMajor).fifths == 0)
        #expect(KeySignature(Key(tonic: 7, mode: .major)).fifths == 1)    // G
        #expect(KeySignature(Key(tonic: 3, mode: .major)).fifths == -3)   // Eb
        #expect(KeySignature(Key(tonic: 4, mode: .minor)).fifths == 1)    // Em
        #expect(KeySignature(Key(tonic: 2, mode: .minor)).fifths == -1)   // Dm
    }

    @Test func keySignaturePositions() {
        let d = KeySignature(fifths: 2)
        #expect(d.letters == [3, 0])                          // F# C#
        #expect(d.staffPositions(for: .treble) == [8, 5])     // F5, C5
        #expect(d.staffPositions(for: .bass) == [6, 3])       // F3, C3
        let bb = KeySignature(fifths: -2)
        #expect(bb.letters == [6, 2])                         // Bb Eb
        #expect(bb.staffPositions(for: .treble) == [4, 7])    // B4, E5
    }

    @Test func pitchAtStaffPositionFollowsKey() {
        // ト音記号：第1線 E4、第3線 B4、加線の下 C4
        #expect(Clef.treble.pitch(atStaffPosition: 0, in: .cMajor) == 64)
        #expect(Clef.treble.pitch(atStaffPosition: -2, in: .cMajor) == 60)
        // ヘ音記号：第1線 G2
        #expect(Clef.bass.pitch(atStaffPosition: 0, in: .cMajor) == 43)
        // G major の第5線（F5）は F♯5、D major の C は C♯
        #expect(Clef.treble.pitch(atStaffPosition: 8, in: Key(tonic: 7, mode: .major)) == 78)
        #expect(Clef.treble.pitch(atStaffPosition: -2, in: Key(tonic: 2, mode: .major)) == 61)
        // F major の B は B♭
        #expect(Clef.treble.pitch(atStaffPosition: 4, in: Key(tonic: 5, mode: .major)) == 70)
    }
}
