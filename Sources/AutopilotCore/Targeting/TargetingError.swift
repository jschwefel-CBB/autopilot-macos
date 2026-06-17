import Foundation

public enum TargetingError: Error, CustomStringConvertible {
    case notFound(selector: String)
    case ambiguous(selector: String, count: Int)
    case timedOut(selector: String, timeoutMs: Int)

    public var description: String {
        switch self {
        case .notFound(let s): return "No element matched selector: \(s)"
        case .ambiguous(let s, let n): return "Selector matched \(n) elements (expected 1): \(s)"
        case .timedOut(let s, let ms): return "Timed out after \(ms)ms waiting for: \(s)"
        }
    }
}
