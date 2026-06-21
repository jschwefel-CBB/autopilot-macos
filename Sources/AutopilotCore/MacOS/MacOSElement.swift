import Foundation
import ApplicationServices

/// macOS element handle: wraps a live AXUIElement behind the neutral
/// ElementHandle protocol. AnyObject (final class) so it satisfies the
/// AnyObject-constrained protocol and can be downcast by MacOSDriver.
public final class MacOSElement: ElementHandle {
    public let ax: AXUIElement
    public init(_ ax: AXUIElement) { self.ax = ax }
}
