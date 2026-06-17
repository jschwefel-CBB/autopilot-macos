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
