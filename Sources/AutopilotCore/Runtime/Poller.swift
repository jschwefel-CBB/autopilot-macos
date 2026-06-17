import Foundation

/// Polls a condition until it returns true or the timeout elapses.
/// Time is driven by the injected Clock, so tests are deterministic.
public struct Poller {
    let clock: Clock
    public init(clock: Clock = SystemClock()) { self.clock = clock }

    /// Returns true if `condition` became true within the timeout.
    @discardableResult
    public func waitUntil(timeoutMs: Int, intervalMs: Int,
                          condition: () -> Bool) -> Bool {
        let start = clock.now()
        let timeout = TimeInterval(timeoutMs) / 1000.0
        let interval = TimeInterval(intervalMs) / 1000.0
        while true {
            if condition() { return true }
            if clock.now() - start >= timeout { return false }
            clock.sleep(interval)
        }
    }
}
