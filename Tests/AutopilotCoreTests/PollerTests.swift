import Testing
import Foundation
@testable import AutopilotCore

/// Deterministic fake clock: advances only when sleep() is called.
final class FakeClock: Clock, @unchecked Sendable {
    private var t: TimeInterval = 0
    func now() -> TimeInterval { t }
    func sleep(_ seconds: TimeInterval) { t += seconds }
}

@Suite struct PollerTests {
    @Test func returnsImmediatelyWhenConditionTrue() throws {
        let clock = FakeClock()
        let poller = Poller(clock: clock)
        var calls = 0
        let ok = poller.waitUntil(timeoutMs: 1000, intervalMs: 100) {
            calls += 1; return true
        }
        #expect(ok)
        #expect(calls == 1)
    }

    @Test func pollsUntilConditionBecomesTrue() throws {
        let clock = FakeClock()
        let poller = Poller(clock: clock)
        var calls = 0
        let ok = poller.waitUntil(timeoutMs: 1000, intervalMs: 100) {
            calls += 1; return calls >= 3
        }
        #expect(ok)
        #expect(calls == 3)
    }

    @Test func timesOutWhenNeverTrue() throws {
        let clock = FakeClock()
        let poller = Poller(clock: clock)
        var calls = 0
        let ok = poller.waitUntil(timeoutMs: 500, intervalMs: 100) {
            calls += 1; return false
        }
        #expect(!ok)
        // 500ms / 100ms interval => ~6 attempts (t=0,100,200,300,400,500)
        #expect(calls >= 5 && calls <= 7)
    }
}
