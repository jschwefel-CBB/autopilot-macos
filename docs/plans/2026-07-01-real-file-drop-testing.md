# Real Cross-Process File Drop for AutoPilot (macOS) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Light up the already-in-schema `drag` + `toFiles` path so it performs a REAL cross-process macOS file drop — the destination's real AppKit handlers (`draggingEntered:` / `performDragOperation:`) fire with a real drag pasteboard carrying both `public.file-url` and `NSFilenamesPboardType` — lifting the "not supported via synthesized events" stub.

**Architecture:** AutoPilot's macOS backend becomes the drag SOURCE inline (the binary already runs non-sandboxed + Accessibility-trusted, so `beginDraggingSession` works with no helper app). A new `FileDragSource` owns a borderless source window, seeds a real `mouseDown:` NSEvent from a synthetic CGEvent, starts an `NSDraggingSession`, then steers the cursor to the drop point with CGEvents. `autopilot-core` gains one `AppDriver` method (`performFileDrag`) and routes `.drag`+`toFiles` to it instead of erroring. `MacOSDriver` is the sole conformer.

**Tech Stack:** Swift 6 (SwiftPM), AppKit (`NSDraggingSession`, `NSPasteboard`, `NSWindow`), CoreGraphics (`CGEvent` / `.cghidEventTap`), XCTest, XCUITest (medit consumer).

**Reference design spec:** `autopilot-macos/docs/specs/2026-07-01-real-file-drop-testing-design.md` (transient — delete after this plan lands).

## Global Constraints

- **Schema stays `"1.1"`** — no new action, no schema bump. Reuse `drag` + `ActionArgs.toFiles`.
- **`autopilot-core` is library-only, platform-agnostic** — ZERO macOS/AppKit APIs in core. All AppKit lives in `autopilot-macos`.
- **Sole `AppDriver` conformer is `MacOSDriver`.** iOS mirrors the schema (no core dependency yet); Android is Kotlin. Adding a protocol method touches NEITHER — no iOS/Android tasks.
- **macOS binary must remain non-sandboxed + Accessibility-trusted** (already true; required for both `CGEventPost` and `beginDraggingSession`-as-source). Do NOT add an App Sandbox entitlement.
- Pasteboard MUST carry BOTH `public.file-url` AND `NSFilenamesPboardType` (covers single- AND multi-file drops — the exact axis of the shipped medit bug).
- Match the existing `EventSynthesizer` idiom: `CGEvent(...)` posted to `.cghidEventTap`, with `settle()`-style ms gaps between phases (no fixed long sleeps).
- GUI tests run against a REAL display, never headless; poll + skip-when-headless, no fixed sleeps.
- medit drop tests run against the NON-sandboxed Debug build (`medit-debug.entitlements`); Release stays sandboxed.
- New driver method signature uses core's `Point` type (from `Sources/AutopilotCore/Driver/Geometry.swift`), mirroring the existing `func performDrag(from: Point, to: Point)`.
- Git author is `jschwefel@coldboreballisticsllc.com` (already the configured identity — never override with `git -c`).
- Do NOT attempt to make Finder the source — out of scope, unautomatable.

---

## Task 1: macOS proof-of-concept spike — real drop fires on hardware

De-risks the one link that cannot be validated headless: whether an `NSDraggingSession` seeded from a synthetic-CGEvent-triggered `mouseDown:` produces a real cross-process drop. Build the minimum to prove it before wiring anything else. This task is a throwaway spike; its code is deleted at the end (only the *finding* carries forward into Task 2).

**Files:**
- Create: `autopilot-macos/spike/FileDropSpike/main.swift` (throwaway executable)
- Create: `autopilot-macos/spike/FileDropSpike/DropWindow.swift` (throwaway destination window that logs received pasteboard types)
- Test: manual run on real hardware (this is a spike, not an automated test)

**Interfaces:**
- Consumes: nothing (standalone).
- Produces: a documented finding (in the task report) — does the seed-event pattern work as-is, and the exact working sequence of CGEvent posts. Task 2 depends on this finding, not on this code.

- [ ] **Step 1: Create a throwaway destination window that logs drops**

Create `autopilot-macos/spike/FileDropSpike/DropWindow.swift`:

```swift
import AppKit

/// A borderless window whose content view accepts file drops and logs which
/// pasteboard types it actually received. Used only by the spike to CONFIRM a
/// real cross-process drop delivered public.file-url / NSFilenamesPboardType.
final class DropView: NSView {
    var onDrop: (([NSPasteboard.PasteboardType], [String]) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, NSPasteboard.PasteboardType("NSFilenamesPboardType")])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        let pb = s.draggingPasteboard
        let types = pb.types ?? []
        let urls = (pb.readObjects(forClasses: [NSURL.self]) as? [URL])?.map(\.path) ?? []
        onDrop?(types, urls)
        return true
    }
}

func makeDropWindow(at frame: NSRect, onDrop: @escaping ([NSPasteboard.PasteboardType], [String]) -> Void) -> NSWindow {
    let w = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
    let v = DropView(frame: NSRect(origin: .zero, size: frame.size))
    v.onDrop = onDrop
    w.contentView = v
    w.level = .floating
    w.backgroundColor = .systemBlue
    w.makeKeyAndOrderFront(nil)
    return w
}
```

- [ ] **Step 2: Create the spike source + driver in `main.swift`**

Create `autopilot-macos/spike/FileDropSpike/main.swift`. It: (a) opens the destination window at a known frame; (b) opens a tiny borderless SOURCE window; (c) posts a synthetic CGEvent mouse-down onto the source window; (d) from the resulting real `mouseDown:` NSEvent, calls `beginDraggingSession` with a file URL declaring BOTH pasteboard types; (e) posts CGEvent moves to the destination center, then a mouse-up; (f) prints whether `performDragOperation:` fired and with which types.

```swift
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.regular)

// A temp file to drag.
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("spike-drop.txt")
try? "hello".write(to: tmp, atomically: true, encoding: .utf8)

let destFrame = NSRect(x: 600, y: 400, width: 300, height: 200)
var gotDrop = false
let destWindow = makeDropWindow(at: destFrame) { types, urls in
    gotDrop = true
    print("DROP RECEIVED types=\(types.map(\.rawValue)) urls=\(urls)")
    print(types.contains(.fileURL) ? "  ✅ public.file-url present" : "  ❌ public.file-url MISSING")
    let filenames = NSPasteboard.PasteboardType("NSFilenamesPboardType")
    print(types.contains(filenames) ? "  ✅ NSFilenamesPboardType present" : "  ❌ NSFilenamesPboardType MISSING")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { app.terminate(nil) }
}

// Source view that starts the drag on mouseDown.
final class SourceView: NSView, NSDraggingSource {
    var fileURL: URL!
    func draggingSession(_ s: NSDraggingSession, sourceOperationMaskFor ctx: NSDraggingContext) -> NSDragOperation {
        ctx == .outsideApplication ? .copy : []
    }
    override func mouseDown(with event: NSEvent) {
        let item = NSPasteboardItem()
        // Declare BOTH types (single + multi-file destinations both fire).
        item.setString(fileURL.absoluteString, forType: .fileURL)
        item.setPropertyList([fileURL.path], forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))
        let di = NSDraggingItem(pasteboardWriter: item)
        di.setDraggingFrame(NSRect(x: 0, y: 0, width: 32, height: 32), contents: NSImage(size: NSSize(width: 32, height: 32)))
        beginDraggingSession(with: [di], event: event, source: self)
    }
}

let srcFrame = NSRect(x: 200, y: 400, width: 40, height: 40)
let srcWindow = NSWindow(contentRect: srcFrame, styleMask: [.borderless], backing: .buffered, defer: false)
let src = SourceView(frame: NSRect(origin: .zero, size: srcFrame.size))
src.fileURL = tmp
srcWindow.contentView = src
srcWindow.level = .floating
srcWindow.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)

// Kick off the synthetic gesture after the run loop is up.
DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
    // Screen coords: AppKit window origin is bottom-left; CGEvent is top-left. Convert.
    let screenH = NSScreen.main!.frame.height
    func toCG(_ p: NSPoint) -> CGPoint { CGPoint(x: p.x, y: screenH - p.y) }
    let srcCenter = toCG(NSPoint(x: srcFrame.midX, y: srcFrame.midY))
    let dstCenter = toCG(NSPoint(x: destFrame.midX, y: destFrame.midY))

    func post(_ type: CGEventType, _ p: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?
            .post(tap: .cghidEventTap); usleep(20_000)
    }
    post(.mouseMoved, srcCenter)
    post(.leftMouseDown, srcCenter)          // triggers SourceView.mouseDown -> beginDraggingSession
    let n = 15
    for i in 1...n {
        let t = Double(i) / Double(n)
        post(.leftMouseDragged, CGPoint(x: srcCenter.x + (dstCenter.x - srcCenter.x) * t,
                                        y: srcCenter.y + (dstCenter.y - srcCenter.y) * t))
    }
    post(.leftMouseUp, dstCenter)

    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
        if !gotDrop { print("❌ NO DROP RECEIVED — seed-event pattern needs adjustment"); app.terminate(nil) }
    }
}
app.run()
```

- [ ] **Step 3: Build and run the spike on real hardware**

Run (from a Terminal with Accessibility permission, on a machine with a real display — NOT headless CI):

```bash
cd autopilot-macos/spike
swiftc FileDropSpike/DropWindow.swift FileDropSpike/main.swift -o /tmp/filedrop-spike && /tmp/filedrop-spike
```

Expected on success:
```
DROP RECEIVED types=[...] urls=[/.../spike-drop.txt]
  ✅ public.file-url present
  ✅ NSFilenamesPboardType present
```

- [ ] **Step 4: Record the finding, then delete the spike**

In the task report, record: did the drop fire? Did BOTH types arrive? What was the working CGEvent sequence + timing? If the drop did NOT fire, record what was tried and STOP — escalate (the seed-event pattern needs research before Task 2). If it fired, delete the spike so it doesn't linger:

```bash
rm -rf autopilot-macos/spike
```

Do NOT commit the spike. This task's deliverable is the FINDING (carried in the report), not code.

---

## Task 2: `FileDragSource` + `MacOSDriver.performFileDrag` (macOS)

Turn the proven spike mechanism into a real, reusable driver capability with an automated GUI integration test. This is the load-bearing implementation task.

**Files:**
- Create: `autopilot-macos/Sources/MacOSDriver/Actions/FileDragSource.swift`
- Modify: `autopilot-macos/Sources/MacOSDriver/MacOSDriver.swift` (add `performFileDrag`, after `performDrag` at ~line 118)
- Test: `autopilot-macos/Tests/MacOSDriverTests/FileDragSourceTests.swift`

**Interfaces:**
- Consumes: the working CGEvent sequence + seed-event pattern from Task 1's finding; core's `Point` type; `Action`/`ActionArgs` (already imported by `MacOSDriver`).
- Produces:
  - `enum FileDragSource { static func drop(files: [String], at point: CGPoint) throws }` — top-level convenience the driver calls.
  - `MacOSDriver.performFileDrag(files: [String], to: Point) throws` — the `AppDriver` conformance (protocol method added in Task 3; this task adds the concrete impl and a TODO-free body; the protocol requirement lands in Task 3 and both compile together — see Task 3 note).

- [ ] **Step 1: Write the failing test**

Create `autopilot-macos/Tests/MacOSDriverTests/FileDragSourceTests.swift`. The test stands up an in-process destination window (like the spike's `DropView`) that records received pasteboard types + URLs, drives `FileDragSource.drop` onto its center, and asserts a real drop with BOTH types. It MUST skip when headless (no active display) per the GUI-test convention.

```swift
import XCTest
import AppKit
@testable import MacOSDriver

final class FileDragSourceTests: XCTestCase {
    /// Real GUI drop — requires an active display + Accessibility. Skip headless.
    func testDropDeliversBothPasteboardTypes() throws {
        try XCTSkipUnless(NSScreen.main != nil, "no display — GUI drop test skipped headless")
        try XCTSkipUnless(AXIsProcessTrusted(), "no Accessibility permission — skipped")

        // A temp file to drop.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("fds-test.txt")
        try "x".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // In-process destination that records what it received.
        var receivedTypes: [NSPasteboard.PasteboardType] = []
        var receivedURLs: [String] = []
        let frame = NSRect(x: 500, y: 300, width: 300, height: 200)
        let win = TestDropWindow.make(at: frame) { types, urls in
            receivedTypes = types; receivedURLs = urls
        }
        defer { win.close() }

        let screenH = NSScreen.main!.frame.height
        let center = CGPoint(x: frame.midX, y: screenH - frame.midY)  // AppKit->CG flip

        try FileDragSource.drop(files: [tmp.path], at: center)

        // Poll for the drop (GUI is async) — NOT a fixed sleep.
        let deadline = Date().addingTimeInterval(5)
        while receivedTypes.isEmpty && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }

        XCTAssertTrue(receivedTypes.contains(.fileURL), "public.file-url missing")
        XCTAssertTrue(receivedTypes.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType")), "NSFilenamesPboardType missing")
        XCTAssertEqual(receivedURLs, [tmp.path])
    }
}
```

Also add the `TestDropWindow` helper (in the same test file) mirroring the spike's `DropView` (a `.borderless` window whose content view registers both dragged types and reports them via a callback).

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --package-path autopilot-macos --filter FileDragSourceTests`
Expected: FAIL — `FileDragSource` / `FileDragSource.drop` does not exist (compile error), or (once stubbed) the drop never arrives.

- [ ] **Step 3: Implement `FileDragSource`**

Create `autopilot-macos/Sources/MacOSDriver/Actions/FileDragSource.swift`. Use the exact working sequence Task 1 proved. Key points: borderless source window; synthetic CGEvent mouse-down onto the source to get a real `mouseDown:`; `beginDraggingSession` writing BOTH `.fileURL` and `NSFilenamesPboardType`; CGEvent steer to `point`; `mouseUp`; match `EventSynthesizer`'s `.cghidEventTap` + short `settle()` gaps. Do not rely on a `mouseUp:` callback (the drag loop consumes it) — detect completion via the dragging session end / a bounded poll.

```swift
import AppKit
import CoreGraphics

/// Performs a REAL cross-process file drop: AutoPilot itself is the drag SOURCE
/// (via NSDraggingSession), so the destination app's real AppKit drag handlers
/// fire with public.file-url + NSFilenamesPboardType. Synthetic CGEvents only
/// STEER the OS-tracked cursor to the drop point; the payload is real.
///
/// Requires non-sandboxed + Accessibility (already true for this binary — it
/// posts CGEvents for click/drag/scroll).
public enum FileDragSource {

    /// Drop `files` onto screen `point` (CoreGraphics/top-left coords, same space
    /// EventSynthesizer uses). Throws if the file list is empty or a file is missing.
    public static func drop(files: [String], at point: CGPoint) throws {
        guard !files.isEmpty else { throw FileDragError.noFiles }
        let urls = try files.map { p -> URL in
            guard FileManager.default.fileExists(atPath: p) else { throw FileDragError.missingFile(p) }
            return URL(fileURLWithPath: p)
        }
        // Everything AppKit here must be on the main thread.
        if Thread.isMainThread { try runDrop(urls: urls, to: point) }
        else { try DispatchQueue.main.sync { try runDrop(urls: urls, to: point) } }
    }

    private static func runDrop(urls: [URL], to point: CGPoint) throws {
        let source = DragSourceWindow(urls: urls)
        source.show()                                   // borderless source window
        defer { source.close() }

        // Seed: synthetic mouse-down on the SOURCE window -> real mouseDown: ->
        // SourceView starts the NSDraggingSession from that real event.
        let s = source.centerInCGSpace
        post(.mouseMoved, s); post(.leftMouseDown, s)   // triggers beginDraggingSession

        // Steer to the destination, then release.
        let n = 15
        for i in 1...n {
            let t = Double(i) / Double(n)
            post(.leftMouseDragged, CGPoint(x: s.x + (point.x - s.x) * t,
                                            y: s.y + (point.y - s.y) * t))
        }
        post(.leftMouseUp, point)

        // Give the destination's drop handler time to run (bounded poll, not a fixed sleep).
        let deadline = Date().addingTimeInterval(3)
        while !source.sessionEnded && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
    }

    private static func post(_ type: CGEventType, _ p: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        usleep(15_000)   // settle — same idiom as EventSynthesizer
    }
}

enum FileDragError: Error, CustomStringConvertible {
    case noFiles, missingFile(String)
    var description: String {
        switch self {
        case .noFiles: return "file drag: no files provided"
        case .missingFile(let p): return "file drag: file does not exist: \(p)"
        }
    }
}

/// Borderless off-screen-ish source window that owns the NSDraggingSession.
private final class DragSourceWindow: NSObject, NSDraggingSource {
    private let window: NSWindow
    private let urls: [URL]
    var sessionEnded = false

    init(urls: [URL]) {
        self.urls = urls
        let frame = NSRect(x: 0, y: 0, width: 40, height: 40)
        window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        let v = SourceView()
        v.owner = self
        window.contentView = v
        window.alphaValue = 0.01           // effectively invisible but real
        window.level = .floating
    }

    func show() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    func close() { window.close() }

    var centerInCGSpace: CGPoint {
        let f = window.frame
        let screenH = NSScreen.main?.frame.height ?? f.maxY
        return CGPoint(x: f.midX, y: screenH - f.midY)
    }

    func beginSession(from event: NSEvent, in view: NSView) {
        let items = urls.map { url -> NSDraggingItem in
            let pbItem = NSPasteboardItem()
            pbItem.setString(url.absoluteString, forType: .fileURL)
            // Property-list array of POSIX paths — what a multi-file Finder drag advertises.
            pbItem.setPropertyList(urls.map(\.path), forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))
            let di = NSDraggingItem(pasteboardWriter: pbItem)
            di.setDraggingFrame(NSRect(x: 0, y: 0, width: 32, height: 32),
                                contents: NSImage(size: NSSize(width: 32, height: 32)))
            return di
        }
        // Note: NSFilenamesPboardType as a plist array only needs to be written once,
        // but writing per-item is harmless; if the destination reads only the first
        // item's plist it still sees all paths. (Keep the full array on each item.)
        view.beginDraggingSession(with: items, event: event, source: self)
    }

    // NSDraggingSource
    func draggingSession(_ s: NSDraggingSession, sourceOperationMaskFor ctx: NSDraggingContext) -> NSDragOperation {
        ctx == .outsideApplication ? .copy : []
    }
    func draggingSession(_ s: NSDraggingSession, endedAt pt: NSPoint, operation: NSDragOperation) {
        sessionEnded = true
    }
}

private final class SourceView: NSView {
    weak var owner: DragSourceWindow?
    override func mouseDown(with event: NSEvent) {
        owner?.beginSession(from: event, in: self)   // real mouseDown: -> real session
    }
}
```

- [ ] **Step 4: Add `performFileDrag` to `MacOSDriver`**

In `autopilot-macos/Sources/MacOSDriver/MacOSDriver.swift`, add right after `performDrag` (ends ~line 118):

```swift
    public func performFileDrag(files: [String], to: Point) throws {
        // AutoPilot is the drag SOURCE (real NSDraggingSession); CGEvents only steer
        // the cursor to the drop point. Real cross-process drop — destination's real
        // AppKit handlers fire with public.file-url + NSFilenamesPboardType.
        try FileDragSource.drop(files: files, at: CGPoint(x: to.x, y: to.y))
    }
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --package-path autopilot-macos --filter FileDragSourceTests`
Expected: PASS on a machine with a real display + Accessibility; SKIPPED (not failed) if headless.

- [ ] **Step 6: Commit**

```bash
cd autopilot-macos
git add Sources/MacOSDriver/Actions/FileDragSource.swift \
        Sources/MacOSDriver/MacOSDriver.swift \
        Tests/MacOSDriverTests/FileDragSourceTests.swift
git commit -m "feat(macos): real cross-process file drop via NSDraggingSession

FileDragSource makes AutoPilot the drag SOURCE, so a destination app's real
AppKit handlers fire with public.file-url + NSFilenamesPboardType. CGEvents
only steer the cursor. MacOSDriver.performFileDrag wires it in.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: core — add `performFileDrag` to `AppDriver`, route `.drag`+`toFiles`

Add the protocol method and replace the runtime stub so a `drag` step with `toFiles` performs the drop instead of erroring. `MacOSDriver` (Task 2) already has the concrete impl, so both compile together.

**Files:**
- Modify: `autopilot-core/Sources/AutopilotCore/Driver/AppDriver.swift` (add method after `performDrag`, line 60)
- Modify: `autopilot-core/Sources/AutopilotCore/Runner/PlanRunner.swift` (replace stub at lines 251–271)
- Test: `autopilot-core/Tests/AutopilotCoreTests/FileDragRoutingTests.swift`

**Interfaces:**
- Consumes: `MacOSDriver.performFileDrag(files:to:)` from Task 2 (the sole conformer).
- Produces: `AppDriver.performFileDrag(files: [String], to: Point) throws` — the protocol requirement; and the `PlanRunner` `.drag` case now routes `toFiles` to it.

- [ ] **Step 1: Write the failing test**

Create `autopilot-core/Tests/AutopilotCoreTests/FileDragRoutingTests.swift`. Use a fake `AppDriver` that records `performFileDrag` calls, run a one-step `drag` + `toFiles` plan, and assert the driver was called with the files (and that no error result was returned). The fake resolves `target` to a point.

```swift
import XCTest
@testable import AutopilotCore

final class FileDragRoutingTests: XCTestCase {
    func testDragWithToFilesRoutesToPerformFileDrag() throws {
        let driver = RecordingDriver()   // records performFileDrag(files:to:)
        let plan = try makeSingleStepDragPlan(target: sel(identifier: "Editor"),
                                              toFiles: ["/tmp/a.txt", "/tmp/b.txt"])
        let report = try PlanRunner(driver: driver).run(plan, options: .init())

        XCTAssertEqual(driver.fileDragCalls.count, 1)
        XCTAssertEqual(driver.fileDragCalls.first?.files, ["/tmp/a.txt", "/tmp/b.txt"])
        XCTAssertEqual(report.steps.first?.result, .pass)   // was .error before this change
    }
}
```

Add the `RecordingDriver` conforming to `AppDriver` (record `performFileDrag`; resolve `target` to a fixed `Point`; no-op the rest), and the `makeSingleStepDragPlan` / `sel` helpers, following the shape of existing core driver-fake tests in `autopilot-core/Tests/AutopilotCoreTests/`. (Reuse an existing fake driver if one already exists there — check first; extend it with `performFileDrag` rather than duplicating.)

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --package-path autopilot-core --filter FileDragRoutingTests`
Expected: FAIL — `AppDriver` has no `performFileDrag` (fake won't compile) OR the step returns `.error` from the stub.

- [ ] **Step 3: Add the protocol requirement**

In `autopilot-core/Sources/AutopilotCore/Driver/AppDriver.swift`, add after `performDrag` (line 60):

```swift
    /// Perform a REAL cross-process file drop: drag `files` onto screen `point`.
    /// The runner resolves the drop target to a point, then calls this. Platform
    /// backends that cannot originate a drag session should throw. Currently only
    /// MacOSDriver implements it (iOS mirrors the schema; Android is Kotlin).
    func performFileDrag(files: [String], to: Point) throws
```

- [ ] **Step 4: Replace the stub in `PlanRunner`**

In `autopilot-core/Sources/AutopilotCore/Runner/PlanRunner.swift`, replace the `.drag` case body (lines 251–271) so `toFiles` routes to the new method:

```swift
        case .drag:
            let ref = try driver.resolve(step.target!, app: app,
                                         timeoutMs: timeoutMs, intervalMs: intervalMs,
                                         baseDir: options.planBaseDir)
            if let files = step.args?.toFiles {
                // Real cross-process file drop onto the target element's point.
                guard let at = driver.point(for: ref) else {
                    throw PlanError.decode("drag (toFiles) needs a resolvable target point")
                }
                try driver.performFileDrag(files: files, to: at)
                return StepResult(id: step.id, result: .pass, durationMs: 0)
            }
            guard let dest = step.args?.to else { throw PlanError.decode("drag needs args.to or args.toFiles") }
            let destRef = try driver.resolve(dest, app: app,
                                             timeoutMs: timeoutMs, intervalMs: intervalMs,
                                             baseDir: options.planBaseDir)
            guard let from = driver.point(for: ref), let to = driver.point(for: destRef) else {
                throw PlanError.decode("drag needs resolvable source and destination points")
            }
            try driver.performDrag(from: from, to: to)
            return StepResult(id: step.id, result: .pass, durationMs: 0)
```

- [ ] **Step 5: Confirm the linter doesn't spuriously warn**

Check `autopilot-core/Sources/AutopilotCore/Plan/PlanLinter.swift`: `drag` is already in `inputActions`; a `drag` + `toFiles` step (no `to`) must not emit a bogus "missing destination" warning. If a lint rule assumes `drag` always has `to`, adjust it to accept `to` OR `toFiles`. Add a one-line lint test only if you change lint logic; otherwise no change.

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --package-path autopilot-core --filter FileDragRoutingTests`
Expected: PASS.
Then run the full core suite: `swift test --package-path autopilot-core`
Expected: all pass (the removed stub had no dedicated passing test asserting the error message; if one exists, update it to assert routing instead).

- [ ] **Step 7: Commit**

```bash
cd autopilot-core
git add Sources/AutopilotCore/Driver/AppDriver.swift \
        Sources/AutopilotCore/Runner/PlanRunner.swift \
        Tests/AutopilotCoreTests/FileDragRoutingTests.swift
git commit -m "feat(core): route drag+toFiles to performFileDrag (real file drop)

Adds AppDriver.performFileDrag and replaces the 'file drag not supported'
stub in PlanRunner: a drag step with toFiles now performs a real drop via
the platform backend. Schema unchanged (1.1) — toFiles already existed.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: docs — flip AUTHORING.md's "not supported" note

Make the docs current with the shipped capability (doc-lag = release defect).

**Files:**
- Modify: `autopilot-macos/docs/AUTHORING.md` (line 136, `drag` row; add a worked example nearby)

**Interfaces:**
- Consumes: the final `drag` + `toFiles` behavior from Tasks 2–3.
- Produces: documentation only.

- [ ] **Step 1: Update the `drag` action row**

In `autopilot-macos/docs/AUTHORING.md`, replace line 136:

Old:
```
| `drag` | **yes** (source) | `to` | Drags from the source element to `to` (a destination selector). File drag-drop (`toFiles`) is **not supported** via synthetic events — use `target.launchFiles` instead. |
```

New:
```
| `drag` | **yes** (target) | `to` OR `toFiles` | With `to`: drags from the target element to a destination selector. With `toFiles`: performs a REAL cross-process **file drop** of the listed files onto the target element (AutoPilot is the drag source; the destination's real AppKit drag handlers fire with `public.file-url` + `NSFilenamesPboardType`). Single- and multi-file both work. |
```

- [ ] **Step 2: Add a worked example**

In the worked-examples area (~line 300), add:

````markdown
**Drop files onto a control (real file drag-and-drop):**

```json
{ "id": "drop-two-files", "action": "drag", "level": "happyPath",
  "target": { "identifier": "EditorTextView" },
  "args": { "toFiles": ["fixtures/a.txt", "fixtures/b.txt"] } }
```

This originates a real macOS drag session and drops both files onto the editor —
the same path a user triggers dragging from Finder. Requires Accessibility
permission and a real display (not headless).
````

- [ ] **Step 3: Commit**

```bash
cd autopilot-macos
git add docs/AUTHORING.md
git commit -m "docs: document real file drag-drop (drag + toFiles)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: medit consumer — XCUITest exercising a real drop (single + multi-file)

The first real consumer: prove medit's drop path end-to-end via a genuine cross-process drop, covering the exact axis of the shipped `.fileURL`-only bug (single vs. multi-file).

**Files:**
- Create: `medit/<UITest target>/FileDropUITests.swift` (exact path per medit's existing UITest layout — locate the existing XCUITest target first)
- Reference: the built AutoPilot binary at `~/repositories/autopilot-macos/autopilot/.build/arm64-apple-macosx/release/autopilot` OR the `FileDragSource` capability invoked via a plan — see Step 1.

**Interfaces:**
- Consumes: the `drag` + `toFiles` plan capability (Tasks 2–3) and medit's non-sandboxed Debug build (`medit-debug.entitlements`).
- Produces: a medit UI test asserting a real file drop opens the right tabs.

- [ ] **Step 1: Decide the invocation path and locate the medit UITest target**

Two ways the test can drive the drop; pick based on medit's existing harness (inspect `medit/` for an existing XCUITest target and any AutoPilot integration):
- (a) **Run an AutoPilot plan** (`drag` + `toFiles` targeting `EditorTextView`) via the AP CLI against the running Debug medit, then assert medit's state; OR
- (b) call the `FileDragSource` capability directly from the XCUITest process (add `MacOSDriver`/`AutopilotCore` as a test dependency) to steer onto medit's editor point.

Prefer (a) if medit already has AP-plan integration (matches how sidebar/open flows are tested); prefer (b) if the UITest already links AP. Record the choice in the report.

- [ ] **Step 2: Write the failing test**

Create `FileDropUITests.swift`. Launch the NON-sandboxed Debug medit with a clean state (`--reset-state`), stage two fixture files, drive a real drop of BOTH onto the editor, and assert two tabs open; then a second case dropping ONE file asserts one tab. Skip when headless.

```swift
import XCTest

final class FileDropUITests: XCTestCase {
    func testMultiFileDropOpensBothTabs() throws {
        try XCTSkipUnless(hasRealDisplay(), "GUI drop test — skipped headless")
        // 1. stage fixtures a.txt, b.txt
        // 2. launch Debug medit --reset-state; waitFor AXWindow
        // 3. compute EditorTextView drop point; drive drag+toFiles [a,b] (path per Step 1)
        // 4. assert medit shows tabs for a.txt AND b.txt (the multi-file bug axis)
    }

    func testSingleFileDropOpensOneTab() throws {
        try XCTSkipUnless(hasRealDisplay(), "GUI drop test — skipped headless")
        // same, with one file; assert exactly one tab
    }
}
```

Fill in the concrete launch + assertion using medit's existing UITest helpers (tab-title accessibility, the `sidebarRow:<file>` / tab AX ids already used in medit's suite). Kill stale medit instances first (`pkill -9 -f "medit.app/Contents/MacOS/medit"`) per the known AP-with-medit gotcha.

- [ ] **Step 3: Run to verify it fails**

Run medit's UITest scheme filtered to `FileDropUITests` (via `xcodebuild test ... -only-testing:.../FileDropUITests` — exact scheme per medit).
Expected: FAIL (assertions unfilled / drop not yet wired end-to-end).

- [ ] **Step 4: Make it pass**

Wire the chosen invocation (Step 1) and the assertions until both cases pass against Debug medit on a real display. Confirm the multi-file case genuinely opens BOTH tabs (this is the regression guard for the shipped bug).

- [ ] **Step 5: Commit**

```bash
cd medit
git add <UITest path>/FileDropUITests.swift
git commit -m "test(ui): real file-drop coverage (single + multi-file) via AutoPilot

Drives a genuine cross-process file drop onto the editor and asserts the
correct tabs open — regression guard for the .fileURL-only multi-file bug.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Final: clean up the transient spec

After all tasks land and the branch is ready to merge, delete the design spec (git history is the archive, per no-historical-docs-in-tree):

```bash
cd autopilot-macos
git rm docs/specs/2026-07-01-real-file-drop-testing-design.md
git commit -m "chore: remove transient file-drop design spec (shipped; git is the archive)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review (against the spec)

- **Spec coverage:** §5.1 mechanism → Tasks 1–2; §5.2 seed-event risk → Task 1 POC gate; §6 core changes → Task 3; §6 AUTHORING → Task 4; §6 medit consumer → Task 5; §7 verification → tests in Tasks 2/3/5; transient-spec rule → Final cleanup. iOS/Android correctly ABSENT (spec §3: not conformers). ✓
- **Placeholder scan:** medit Step 1–2 intentionally defer the exact UITest path/scheme to the implementer (medit's layout isn't in this plan's context) — flagged explicitly as "locate first," not a hidden TODO. All macOS/core code is complete and concrete. ✓
- **Type consistency:** `performFileDrag(files: [String], to: Point)` identical in AppDriver (Task 3 Step 3), MacOSDriver (Task 2 Step 4), and the PlanRunner call (Task 3 Step 4). `Point` (core) ↔ `CGPoint` (macOS) conversion is explicit at the driver boundary. `FileDragSource.drop(files:at:)` signature matches its call site. ✓
