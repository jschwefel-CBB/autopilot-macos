import Foundation

public enum TargetingError: Error, CustomStringConvertible {
    case notFound(selector: String)
    case ambiguous(selector: String, count: Int, matches: [String])
    case timedOut(selector: String, timeoutMs: Int)

    public var description: String {
        switch self {
        case .notFound(let s): return "No element matched selector: \(s)"
        case .ambiguous(let s, let n, let matches):
            let listed = matches.enumerated()
                .map { "  [\($0.offset)] \($0.element)" }
                .joined(separator: "\n")
            let more = n > matches.count ? "\n  … and \(n - matches.count) more" : ""
            return "Selector matched \(n) elements (expected 1): \(s)\n" + listed + more
                + "\nDisambiguate with an `identifier`, or a more specific role/title/value."
        case .timedOut(let s, let ms): return "Timed out after \(ms)ms waiting for: \(s)"
        }
    }
}
