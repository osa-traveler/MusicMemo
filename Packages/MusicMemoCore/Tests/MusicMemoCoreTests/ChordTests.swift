import Testing
@testable import MusicMemoCore

struct ChordTests {
    @Test(arguments: [
        ("C", [0, 4, 7]),
        ("Am", [9, 0, 4]),
        ("Dm7", [2, 5, 9, 0]),
        ("G7", [7, 11, 2, 5]),
        ("Am7", [9, 0, 4, 7]),
        ("C/E", [0, 4, 7]),
        ("G/B", [7, 11, 2]),
        ("F/G", [5, 9, 0, 7]),
        ("Bbmaj7", [10, 2, 5, 9]),
        ("F#m7b5", [6, 9, 0, 4]),
    ])
    func pitchClasses(symbol: String, expected: [PitchClass]) throws {
        let chord = try #require(Chord(symbol))
        #expect(chord.pitchClasses == expected)
    }

    @Test func slashChordBass() throws {
        let chord = try #require(Chord("C/E"))
        #expect(chord.root == 0)
        #expect(chord.quality == .major)
        #expect(chord.bass == 4)
    }

    @Test(arguments: ["C", "Am", "Dm7", "G7", "C/E", "G/B", "Bbmaj7", "Ebm7/Db", "F#dim7", "Csus4"])
    func symbolRoundTrip(symbol: String) throws {
        #expect(try #require(Chord(symbol)).symbol == symbol)
    }

    @Test func aliases() {
        #expect(Chord("CM7")?.symbol == "Cmaj7")
        #expect(Chord("C△7")?.symbol == "Cmaj7")
        #expect(Chord("A-7")?.symbol == "Am7")
        #expect(Chord("B♭")?.symbol == "Bb")
    }

    @Test(arguments: ["", "H", "Cxyz", "C/", "C/E/G", "/E"])
    func invalid(symbol: String) {
        #expect(Chord(symbol) == nil)
    }
}
