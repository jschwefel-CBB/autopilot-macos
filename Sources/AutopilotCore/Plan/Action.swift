import Foundation

/// v1 action vocabulary. Lean by design.
public enum Action: String, Codable, Sendable {
    case launch, terminate
    case click, doubleClick, rightClick
    case press          // AX press action (buttons, menu items) — robust vs coordinate click
    case menu           // walk the menu bar: ["View", "Rainbow Brackets"]
    case type, keyPress, setValue, scroll
    case drag           // drag from a source element/point to a destination
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
    public var menuPath: [String]?    // menu: ["View", "Rainbow Brackets"]
    public var to: Selector?          // drag: destination element
    public var toFiles: [String]?     // drag: file paths to drag onto the target (DnD)
    public var commit: Bool?          // type: press Return after typing to fire end-editing
    public var clear: Bool?           // type: select-all + delete before typing
    public init() {}
}
