import Foundation

/// An 8-bit RGB color sampled from the screen. Neutral replacement for the
/// macOS-only PixelColor.RGB at the driver boundary.
public struct RGBColor: Equatable, Sendable {
    public var r: Int
    public var g: Int
    public var b: Int
    public init(r: Int, g: Int, b: Int) { self.r = r; self.g = g; self.b = b }
}

/// A launched/attached app, identified by pid + display name. Neutral
/// replacement for the macOS-only LaunchedApp at the driver boundary.
public struct LaunchedHandle: Sendable {
    public let pid: Int32
    public let appName: String
    public init(pid: Int32, appName: String) { self.pid = pid; self.appName = appName }
}

/// A flattened element-tree snapshot: each node is a [attribute: value] dict,
/// `truncated` true if the walk hit its node cap before finishing.
public struct TreeSnapshot: Sendable {
    public let nodes: [[String: String]]
    public let truncated: Bool
    public init(nodes: [[String: String]], truncated: Bool) {
        self.nodes = nodes; self.truncated = truncated
    }
}

/// Everything PlanRunner needs from a platform. A backend (macOS AX, iOS
/// XCUITest, Android via Appium) implements this; core orchestration depends
/// only on this protocol and never on any platform API.
public protocol AppDriver {
    // Lifecycle
    func launch(_ target: TargetApp) throws -> LaunchedHandle
    func attach(_ target: TargetApp) throws -> LaunchedHandle
    func attach(pid: Int32) throws -> LaunchedHandle
    func terminate(_ app: LaunchedHandle)
    func activate(_ app: LaunchedHandle, timeoutMs: Int, intervalMs: Int) -> Bool

    // Permissions
    func hasAccessibility() -> Bool
    func hasScreenRecording() -> Bool
    func accessibilityInstructions() -> String
    func screenRecordingInstructions() -> String

    // Resolution
    func resolve(_ selector: Selector, app: LaunchedHandle,
                 timeoutMs: Int, intervalMs: Int, baseDir: URL?) throws -> ResolvedElement
    func waitForPresence(_ selector: Selector, present: Bool, app: LaunchedHandle,
                         timeoutMs: Int, intervalMs: Int) -> Bool
    func matchCount(_ selector: Selector, app: LaunchedHandle) -> Int
    func findAll(_ selector: Selector, app: LaunchedHandle) -> [String]

    // Actions
    func perform(action: Action, args: ActionArgs?, on element: ResolvedElement?) throws
    func point(for element: ResolvedElement) -> Point?
    /// Drag from one screen point to another (file-less; coordinate drag only).
    /// The runner resolves both endpoints to points, then calls this.
    func performDrag(from: Point, to: Point) throws
    /// Select a menu-bar path (e.g. ["File", "Save As…"]) on the app.
    func selectMenuPath(_ path: [String], app: LaunchedHandle) throws

    // Property read (assertions)
    func readProperty(_ property: AssertProperty, of element: any ElementHandle) -> String?

    // Visual capture
    func captureElementScreenshot(_ element: any ElementHandle, to path: String,
                                  padding: Int, metadata: [String: String]) -> String?
    func captureMainDisplay(to path: String, metadata: [String: String]) -> Bool
    func captureRegion(_ rect: Rect, to path: String, metadata: [String: String]) -> Bool
    func samplePixel(at point: Point) -> RGBColor?
    func sampleRegion(_ rect: Rect) -> [RGBColor]
    /// Load a PNG into a flat row-major pixel array (for snapshot diffing).
    func loadPNG(_ path: String) -> [RGBColor]?

    // Inspection
    func dumpTree(app: LaunchedHandle) -> TreeSnapshot
    func suggestSelectors(app: LaunchedHandle) -> [SelectorSuggester.Suggestion]
}
