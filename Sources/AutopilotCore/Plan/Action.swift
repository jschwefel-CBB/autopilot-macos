import Foundation

/// v1 action vocabulary. Lean by design.
public enum Action: String, Codable, Sendable {
    case launch, terminate
    case click, doubleClick, rightClick
    case type, keyPress, setValue, scroll
    case waitFor, screenshot, assert
    case wait   // explicit, discouraged fixed delay
}

/// Per-action arguments. Only the fields relevant to a given action are used.
public struct ActionArgs: Codable, Equatable, Sendable {
    public var text: String?          // type / setValue
    public var keys: String?          // keyPress, e.g. "cmd+s"
    public var deltaX: Int?           // scroll
    public var deltaY: Int?           // scroll
    public var seconds: Double?       // wait
    public var path: String?          // screenshot output path
    public var present: Bool?         // waitFor: true=appears, false=disappears
    public init() {}
}
