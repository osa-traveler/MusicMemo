import Testing
@testable import MusicMemoCore

@Test func quarterIsDivisibleForTriplets() {
    #expect(Timing.ticksPerQuarter % 3 == 0)
    #expect(Timing.ticksPerQuarter / 4 % 3 == 0)
}
