import Testing
@testable import MusicMemoCore

struct TimeTests {
    let time = TimeSignature.common

    @Test func quarterIsDivisibleForTriplets() {
        #expect(Timing.ticksPerSixteenth % 3 == 0)
    }

    @Test func barLength() {
        #expect(time.ticksPerBar == 1920)
        #expect(time.startTick(ofBar: 1) == 0)
        #expect(time.startTick(ofBar: 7) == 1920 * 6)
        #expect(time.bar(containing: 1920 * 6 - 1) == 6)
        #expect(time.bar(containing: 1920 * 6) == 7)
    }

    @Test func positionDescription() {
        let tick = time.tick(of: BarPosition(bar: 7, beat: 1, sixteenth: 1))
        #expect(time.position(of: tick).description == "7.1.1")
        #expect(time.position(of: time.startTick(ofBar: 6)).barBeatDescription == "6.1")
        #expect(time.position(of: tick + 480 + 240).description == "7.2.3")
    }

    @Test(arguments: [0, 1, 119, 120, 479, 480, 1919, 1920, 12345, 30719])
    func roundTrip(tick: Tick) {
        #expect(time.tick(of: time.position(of: tick)) == tick)
    }

    @Test func compoundMeter() {
        let sixEight = TimeSignature(beats: 6, beatUnit: 8)
        #expect(sixEight.ticksPerBeat == 240)
        #expect(sixEight.ticksPerBar == 1440)
        #expect(sixEight.position(of: 240 * 5 + 120).description == "1.6.2")
    }
}
