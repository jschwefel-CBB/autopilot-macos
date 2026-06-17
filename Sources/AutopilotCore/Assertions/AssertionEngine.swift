import Foundation
import ApplicationServices

public struct AssertionEngine {
    public init() {}

    /// Pure comparison. `exists`/`notExists` are handled by the runner (element presence),
    /// not here. Numeric ops parse both sides as Double; non-numeric => false.
    public func evaluate(op: AssertOp, actual: String, expected: String) -> Bool {
        switch op {
        case .equals: return actual == expected
        case .notEquals: return actual != expected
        case .contains: return actual.contains(expected)
        case .matches:
            guard let re = try? NSRegularExpression(pattern: expected) else { return false }
            let range = NSRange(actual.startIndex..., in: actual)
            return re.firstMatch(in: actual, range: range) != nil
        case .greaterThan:
            guard let a = Double(actual), let b = Double(expected) else { return false }
            return a > b
        case .lessThan:
            guard let a = Double(actual), let b = Double(expected) else { return false }
            return a < b
        case .exists, .notExists:
            return false // presence handled by runner
        }
    }

    /// Read the requested property of an AX element as a string.
    public func readProperty(_ property: AssertProperty, from element: AXUIElement) -> String? {
        switch property {
        case .value: return AXTree.string(element, kAXValueAttribute as String)
        case .title: return AXTree.string(element, kAXTitleAttribute as String)
        case .enabled: return AXTree.bool(element, kAXEnabledAttribute as String).map { $0 ? "true" : "false" }
        case .focused: return AXTree.bool(element, kAXFocusedAttribute as String).map { $0 ? "true" : "false" }
        case .position:
            guard let f = AXTree.frame(element) else { return nil }
            return "\(Int(f.minX)),\(Int(f.minY))"
        case .size:
            guard let f = AXTree.frame(element) else { return nil }
            return "\(Int(f.width)),\(Int(f.height))"
        case .exists: return "true"
        }
    }
}
