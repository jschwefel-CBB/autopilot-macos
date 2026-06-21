import Testing
import Foundation
@testable import AutopilotCore

/// A pure-Swift fake proves the AppDriver protocol carries no platform types —
/// if this compiles and runs with zero platform imports, the seam is clean.
final class FakeElement: ElementHandle { let id: String; init(_ id: String) { self.id = id } }

struct FakeDriver: AppDriver {
    var nodes: [[String: String]] = []
    func launch(_ target: TargetApp) throws -> LaunchedHandle { LaunchedHandle(pid: 1, appName: "Fake") }
    func attach(_ target: TargetApp) throws -> LaunchedHandle { LaunchedHandle(pid: 1, appName: "Fake") }
    func attach(pid: Int32) throws -> LaunchedHandle { LaunchedHandle(pid: pid, appName: "Fake") }
    func terminate(_ app: LaunchedHandle) {}
    func activate(_ app: LaunchedHandle, timeoutMs: Int, intervalMs: Int) -> Bool { true }
    func hasAccessibility() -> Bool { true }
    func hasScreenRecording() -> Bool { true }
    func accessibilityInstructions() -> String { "grant ax" }
    func screenRecordingInstructions() -> String { "grant sr" }
    func resolve(_ selector: AutopilotCore.Selector, app: LaunchedHandle, timeoutMs: Int, intervalMs: Int, baseDir: URL?) throws -> ResolvedElement {
        if nodes.contains(where: { AXResolverMatchShim.matches($0, selector) }) { return .element(FakeElement("x")) }
        throw TargetingError.notFound(selector: "{}")
    }
    func waitForPresence(_ selector: AutopilotCore.Selector, present: Bool, app: LaunchedHandle, timeoutMs: Int, intervalMs: Int) -> Bool { present }
    func matchCount(_ selector: AutopilotCore.Selector, app: LaunchedHandle) -> Int { nodes.count }
    func findAll(_ selector: AutopilotCore.Selector, app: LaunchedHandle) -> [String] { [] }
    func perform(action: Action, args: ActionArgs?, on element: ResolvedElement?) throws {}
    func point(for element: ResolvedElement) -> Point? { if case .point(let p) = element { return p }; return Point(x: 0, y: 0) }
    func performDrag(from: Point, to: Point) throws {}
    func selectMenuPath(_ path: [String], app: LaunchedHandle) throws {}
    func readProperty(_ property: AssertProperty, of element: any ElementHandle) -> String? { "fake" }
    func captureElementScreenshot(_ element: any ElementHandle, to path: String, padding: Int, metadata: [String: String]) -> String? { nil }
    func captureMainDisplay(to path: String, metadata: [String: String]) -> Bool { true }
    func captureRegion(_ rect: Rect, to path: String, metadata: [String: String]) -> Bool { true }
    func samplePixel(at point: Point) -> RGBColor? { RGBColor(r: 0, g: 0, b: 0) }
    func sampleRegion(_ rect: Rect) -> [RGBColor] { [] }
    func loadPNG(_ path: String) -> [RGBColor]? { nil }
    func dumpTree(app: LaunchedHandle) -> TreeSnapshot { TreeSnapshot(nodes: nodes, truncated: false) }
    func suggestSelectors(app: LaunchedHandle) -> [SelectorSuggester.Suggestion] { [] }
}

/// Shim so the test can reuse the pure matcher without importing it under a new name.
enum AXResolverMatchShim { static func matches(_ n: [String: String], _ s: AutopilotCore.Selector) -> Bool { AXResolver.matches(node: n, selector: s) } }

@Suite struct FakeDriverTests {
    @Test func fakeResolvesKnownNode() throws {
        let d = FakeDriver(nodes: [["role": "AXButton", "identifier": "ok"]])
        let app = try d.launch(TargetApp(bundleId: "x"))
        let re = try d.resolve(Selector(identifier: "ok"), app: app, timeoutMs: 100, intervalMs: 10, baseDir: nil)
        guard case .element = re else { Issue.record("expected element"); return }
    }
    @Test func fakeThrowsOnMissing() throws {
        let d = FakeDriver(nodes: [])
        let app = try d.launch(TargetApp(bundleId: "x"))
        #expect(throws: (any Error).self) {
            try d.resolve(Selector(identifier: "nope"), app: app, timeoutMs: 100, intervalMs: 10, baseDir: nil)
        }
    }
}
