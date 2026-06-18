import Testing
import Foundation
@testable import AutopilotCore

@Suite struct AssertionEvaluatorTests {
    let e = AssertionEngine()

    @Test func equals() { #expect(e.evaluate(op: .equals, actual: "2 lines", expected: "2 lines")) }
    @Test func notEquals() { #expect(e.evaluate(op: .notEquals, actual: "a", expected: "b")) }
    @Test func contains() { #expect(e.evaluate(op: .contains, actual: "hello world", expected: "world")) }
    @Test func matchesRegex() { #expect(e.evaluate(op: .matches, actual: "count: 7", expected: #"count: \d+"#)) }
    @Test func greaterThan() { #expect(e.evaluate(op: .greaterThan, actual: "10", expected: "3")) }
    @Test func lessThan() { #expect(e.evaluate(op: .lessThan, actual: "2", expected: "9")) }
    @Test func greaterThanNonNumericIsFalse() { #expect(!e.evaluate(op: .greaterThan, actual: "x", expected: "3")) }
    @Test func equalsFails() { #expect(!e.evaluate(op: .equals, actual: "1 line", expected: "2 lines")) }
}

@Suite struct AssertionPollingTests {
    let e = AssertionEngine()

    @Test func succeedsImmediatelyWhenAlreadyMatching() {
        let clock = FakeClock()
        var reads = 0
        let outcome = e.pollEvaluate(op: .equals, expected: "ready",
                                     timeoutMs: 1000, intervalMs: 100,
                                     clock: clock) { reads += 1; return "ready" }
        #expect(outcome.matched)
        #expect(outcome.actual == "ready")
        #expect(reads == 1)
    }

    @Test func retriesUntilValuePropagates() {
        // Value is empty for the first two reads, then becomes correct —
        // exactly the "AX value hadn't propagated yet" race from the field report.
        let clock = FakeClock()
        var reads = 0
        let outcome = e.pollEvaluate(op: .contains, expected: "beta",
                                     timeoutMs: 1000, intervalMs: 100,
                                     clock: clock) {
            reads += 1
            return reads >= 3 ? "beta" : ""
        }
        #expect(outcome.matched)
        #expect(outcome.actual == "beta")
        #expect(reads == 3)
    }

    @Test func failsAtTimeoutWithLastActual() {
        let clock = FakeClock()
        let outcome = e.pollEvaluate(op: .equals, expected: "never",
                                     timeoutMs: 300, intervalMs: 100,
                                     clock: clock) { "stuck" }
        #expect(!outcome.matched)
        #expect(outcome.actual == "stuck")   // reports the last observed value
    }
}
