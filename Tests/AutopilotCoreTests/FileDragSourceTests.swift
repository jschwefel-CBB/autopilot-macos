import Testing
import Foundation
import AppKit
import ApplicationServices
import AutopilotCore
@testable import MacOSDriver

/// End-to-end real file-drop tests. AutoPilot originates a genuine cross-process
/// drag session (`drag` + `toFiles`) onto a real foreground app (TestHostApp),
/// whose `dropWell` records what it received into `dropResultLabel`'s AX value.
///
/// This drives the FULL path: PlanRunner routing -> MacOSDriver.performFileDrag
/// -> FileDragSource -> real NSDraggingSession -> destination's real AppKit
/// handlers. (An in-process window cannot host this — an xctest process is not a
/// foreground GUI app; the destination must be a real bundled app.)
///
/// `.serialized`: each test drives the ONE shared system cursor with a real drag
/// and launches a foreground app — parallel runs fight over both.
@Suite(.serialized) struct FileDragSourceTests {

    private func testHostApp() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AutopilotCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // package root
            .appendingPathComponent("Fixtures/TestHostApp/.build/TestHostApp.app")
    }

    private func killExistingTestHostApps() {
        for pat in ["TestHostApp.app", "AutopilotDragSource"] {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            p.arguments = ["-9", "-f", pat]
            try? p.run(); p.waitUntilExit()
        }
        // Let the WindowServer settle (window teardown + cursor release) so a
        // prior test's drag state can't bleed into the next serialized test.
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func stageFile(_ name: String, _ contents: String) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fds-\(UUID().uuidString)-\(name)")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    /// The built AutopilotDragSource helper binary (inside its .app bundle), or
    /// nil if it hasn't been built. Tests point FileDragSource at it via the
    /// AUTOPILOT_DRAG_SOURCE env var so the drop works from the test process.
    private func dragSourceHelper() -> String? {
        let pkgRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        // Candidate build dirs (arch-specific and generic).
        let candidates = [
            pkgRoot.appendingPathComponent(".build/arm64-apple-macosx/debug/AutopilotDragSource.app/Contents/MacOS/AutopilotDragSource"),
            pkgRoot.appendingPathComponent(".build/debug/AutopilotDragSource.app/Contents/MacOS/AutopilotDragSource"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }?.path
    }

    /// Drop `files` onto TestHostApp's dropWell and return the resulting
    /// `dropResultLabel` AX value ("drop:<n>:<url|->+<names|->:<name1,name2>").
    private func runDropPlan(files: [String]) throws -> Report {
        let binary = testHostApp()
        let artifacts = FileManager.default.temporaryDirectory
            .appendingPathComponent("autopilot-drop-\(UUID().uuidString)")
        let expectedCount = files.count
        let names = files.map { ($0 as NSString).lastPathComponent }.sorted().joined(separator: ",")
        _ = names   // (assertion is on the label below; kept for clarity)
        let plan = Plan(
            schemaVersion: "1.1",
            name: "host: file drop",
            target: TargetApp(path: binary.path),
            defaults: PlanDefaults(timeoutMs: 5000, retryIntervalMs: 100),
            steps: [
                Step(id: "wait-window", action: .waitFor, level: .happyPath,
                     target: Selector(role: "AXWindow"),
                     args: { var a = ActionArgs(); a.present = true; return a }()),
                // The real file drop onto the drop well.
                Step(id: "drop", action: .drag, level: .happyPath,
                     target: Selector(identifier: "dropWell"),
                     args: { var a = ActionArgs(); a.toFiles = files; return a }()),
                // Assert the well received exactly the expected number of files,
                // and that BOTH pasteboard types arrived.
                Step(id: "assert-count", action: .assert, level: .happyPath,
                     target: Selector(identifier: "dropResultLabel"),
                     assert: Assertion(property: .value, op: .contains, expected: "drop:\(expectedCount):")),
                Step(id: "assert-url", action: .assert, level: .happyPath,
                     target: Selector(identifier: "dropResultLabel"),
                     assert: Assertion(property: .value, op: .contains, expected: "url+names")),
                Step(id: "quit", action: .terminate, level: .happyPath),
            ]
        )
        return try PlanRunner(driver: MacOSDriver()).run(plan, options: RunOptions(artifactsDir: artifacts))
    }

    /// Common preconditions for the live-GUI drop tests. Returns false (skip) when
    /// the environment can't support a real drop, and points FileDragSource at the
    /// built helper.
    private func prepareOrSkip() -> Bool {
        guard AXIsProcessTrusted() else { return false }   // skip headless / no-AX
        guard NSScreen.main != nil else { return false }
        guard FileManager.default.fileExists(atPath: testHostApp().path) else {
            Issue.record("TestHostApp.app not built. Run: Fixtures/TestHostApp/make-app.sh"); return false
        }
        guard let helper = dragSourceHelper() else {
            Issue.record("AutopilotDragSource.app not built. Run: Fixtures/make-drag-source-app.sh"); return false
        }
        setenv("AUTOPILOT_DRAG_SOURCE", helper, 1)
        return true
    }

    @Test func multiFileDropDeliversBothTypesAndAllFiles() throws {
        guard prepareOrSkip() else { return }
        killExistingTestHostApps(); defer { killExistingTestHostApps() }

        let a = try stageFile("a.txt", "a")
        let b = try stageFile("b.txt", "b")
        defer { try? FileManager.default.removeItem(atPath: a); try? FileManager.default.removeItem(atPath: b) }

        let report = try runDropPlan(files: [a, b])
        #expect(report.result == .pass, "report: \(Reporter().humanSummary(report))")
    }

    @Test func singleFileDropDeliversOneFile() throws {
        guard prepareOrSkip() else { return }
        killExistingTestHostApps(); defer { killExistingTestHostApps() }

        let a = try stageFile("single.txt", "x")
        defer { try? FileManager.default.removeItem(atPath: a) }

        let report = try runDropPlan(files: [a])
        #expect(report.result == .pass, "report: \(Reporter().humanSummary(report))")
    }

    @Test func emptyFileListThrows() {
        #expect(throws: FileDragError.self) {
            try FileDragSource.drop(files: [], at: CGPoint(x: 0, y: 0))
        }
    }

    @Test func missingFileThrows() {
        #expect(throws: FileDragError.self) {
            try FileDragSource.drop(files: ["/no/such/file/at/all.txt"], at: CGPoint(x: 0, y: 0))
        }
    }
}
