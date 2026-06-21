import Testing
import CoreGraphics
import ApplicationServices
@testable import AutopilotCore

@Suite struct MacOSDriverTests {
    @Test func elementWrapsAX() {
        // A bogus AXUIElement for type plumbing only (not messaged).
        let appEl = AXUIElementCreateApplication(getpid())
        let wrapped = MacOSElement(appEl)
        #expect(wrapped is ElementHandle)
    }
    @Test func driverConformsAndReportsPermissions() {
        let d = MacOSDriver()
        // These call the real probes; on a dev/CI box with AX granted they're true,
        // but we only assert the calls return a Bool (the conformance compiles + runs).
        _ = d.hasAccessibility()
        _ = d.hasScreenRecording()
        #expect(!d.accessibilityInstructions().isEmpty)
        #expect(!d.screenRecordingInstructions().isEmpty)
    }
    @Test func neutralToCGConversionsRoundTrip() {
        #expect(MacOSDriver.cgPoint(Point(x: 3, y: 4)) == CGPoint(x: 3, y: 4))
        #expect(MacOSDriver.cgRect(Rect(x: 1, y: 2, width: 5, height: 6)) == CGRect(x: 1, y: 2, width: 5, height: 6))
        #expect(MacOSDriver.point(CGPoint(x: 7, y: 8)) == Point(x: 7, y: 8))
    }
}
