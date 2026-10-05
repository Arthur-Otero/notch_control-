import Testing
import NotchControlCore

@Test func helperRestartBacksOffAndKeepsTryingWhileITermIsAbsent() {
    #expect(ReconnectPolicy.delay(afterFailures: 1) == 2)
    #expect(ReconnectPolicy.delay(afterFailures: 2) == 4)
    #expect(ReconnectPolicy.delay(afterFailures: 3) == 6)
    // The app can be opened long before iTerm2: the wait stays bounded but the attempts never stop.
    #expect(ReconnectPolicy.delay(afterFailures: 15) == ReconnectPolicy.maximumDelay)
    #expect(ReconnectPolicy.delay(afterFailures: 10_000) == ReconnectPolicy.maximumDelay)
}

@Test func helperRestartDelayIgnoresInvalidFailureCounts() {
    #expect(ReconnectPolicy.delay(afterFailures: 0) == 2)
    #expect(ReconnectPolicy.delay(afterFailures: -5) == 2)
}
