import Foundation
import ApplicationServices

public struct Permissions {
    public init() {}

    /// Is the running process trusted for Accessibility control?
    public func hasAccessibility() -> Bool { AXIsProcessTrusted() }

    /// Human-readable instructions for granting AX permission.
    public func accessibilityInstructions() -> String {
        """
        Accessibility permission required.
        Grant it in: System Settings > Privacy & Security > Accessibility,
        then enable the binary running autopilot (or your terminal app).
        """
    }
}
