import Foundation

/// An opaque, backend-defined handle to a resolved UI element. Core never
/// inspects it; only the owning driver downcasts it back to its concrete type.
/// AnyObject so a backend can hold a reference type (e.g. an AXUIElement box).
public protocol ElementHandle: AnyObject, Sendable {}

/// The result of resolving a selector: either a real element handle, or a bare
/// screen point produced by the vision (template-match) fallback when no element
/// handle is available.
public enum ResolvedElement {
    case element(any ElementHandle)
    case point(Point)
}
