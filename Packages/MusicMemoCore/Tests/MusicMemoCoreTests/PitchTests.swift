import Testing
@testable import MusicMemoCore

struct PitchTests {
    @Test func noteNames() {
        #expect(Pitch.noteName(60) == "C4")
        #expect(Pitch.noteName(83) == "B5")
        #expect(Pitch.noteName(61, preferFlats: true) == "Db4")
        #expect(Pitch.noteName(11) == "B-1")
    }

    @Test func parsePitchClass() {
        #expect(Pitch.pitchClass(named: "C") == 0)
        #expect(Pitch.pitchClass(named: "F#") == 6)
        #expect(Pitch.pitchClass(named: "B♭") == 10)
        #expect(Pitch.pitchClass(named: "Cb") == 11)
        #expect(Pitch.pitchClass(named: "H") == nil)
    }

    @Test func keyDescription() {
        #expect(Key.cMajor.description == "C major")
        #expect(Key(tonic: 10, mode: .major).description == "Bb major")
        #expect(Key(tonic: 9, mode: .minor).description == "A minor")
    }
}
