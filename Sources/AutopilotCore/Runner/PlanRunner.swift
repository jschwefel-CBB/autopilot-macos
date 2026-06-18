import Foundation
import ApplicationServices

public struct RunOptions {
    public var keepGoing: Bool
    public var artifactsDir: URL
    /// Directory of the plan file, used to resolve relative vision-template paths.
    public var planBaseDir: URL?
    public init(keepGoing: Bool = false, artifactsDir: URL, planBaseDir: URL? = nil) {
        self.keepGoing = keepGoing; self.artifactsDir = artifactsDir
        self.planBaseDir = planBaseDir
    }
}

public struct PlanRunner {
    let clock: Clock
    let permissions = Permissions()
    let launcher = AppLauncher()
    let actions = ActionEngine()
    let assertions = AssertionEngine()
    let reporter = Reporter()

    public init(clock: Clock = SystemClock()) { self.clock = clock }

    /// A filesystem-safe slug for a plan name, for per-plan artifact directories.
    static func slug(_ name: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-_")
        let lowered = name.lowercased().map { allowed.contains($0) ? $0 : "-" }
        let collapsed = String(lowered).split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        return collapsed.isEmpty ? "plan" : collapsed
    }

    /// Parse-and-run is the caller's job for include base-dir reasons; this takes a resolved Plan.
    public func run(_ plan: Plan, options callerOptions: RunOptions) throws -> Report {
        // Namespace artifacts under a per-plan subdirectory so concurrent or
        // sequential multi-plan runs into one artifacts root don't clobber each
        // other's report.json / screenshots / AX dumps.
        var options = callerOptions
        options.artifactsDir = callerOptions.artifactsDir.appendingPathComponent(Self.slug(plan.name))

        var report = Report(plan: plan.name)
        let hasAX = permissions.hasAccessibility()
        let perm = PermissionStatus(accessibility: hasAX, automation: true)

        guard hasAX else {
            report.add(StepResult(id: "_preflight", result: .error, durationMs: 0,
                                  message: permissions.accessibilityInstructions()))
            report.finalize(permissions: perm)
            return report
        }

        let defaults = plan.defaults
        let timeoutMs = defaults?.timeoutMs ?? 5000
        let intervalMs = defaults?.retryIntervalMs ?? 100
        let targeting = Targeting(poller: Poller(clock: clock))

        let launched = try launcher.launch(plan.target)
        defer { /* leave app running unless a terminate step ran; harmless for tests */ }
        let appElement = AXTree.application(pid: launched.pid)
        // Give the app a beat to register its AX tree (polled, not a fixed sleep).
        _ = targeting.waitForPresence(Selector(role: "AXWindow"), present: true,
                                      app: appElement, timeoutMs: timeoutMs, intervalMs: intervalMs)
        // Bring the app frontmost and wait until it is key, so the first
        // synthesized keystroke/click is not dropped on a not-yet-active window.
        _ = launcher.activate(launched, timeoutMs: timeoutMs, intervalMs: intervalMs, clock: clock)

        for step in plan.steps {
            let stepTimeout = step.timeoutMs ?? timeoutMs
            let start = clock.now()
            do {
                let result = try runStep(step, app: appElement, launched: launched,
                                         targeting: targeting, timeoutMs: stepTimeout,
                                         intervalMs: intervalMs, options: options)
                let dur = Int((clock.now() - start) * 1000)
                var r = result; r.durationMs = dur
                report.add(r)
                if r.result != .pass && !options.keepGoing { break }
            } catch {
                let dur = Int((clock.now() - start) * 1000)
                let dump = writeAXDump(appElement, stepId: step.id, dir: options.artifactsDir)
                let shot = options.artifactsDir.appendingPathComponent("\(step.id).png").path
                Screenshot.captureMainDisplay(to: shot)
                // A targeting failure (element not found / ambiguous / timed out)
                // means the app's UI wasn't as the plan expected — that's a test
                // FAILURE. Everything else (launch failure, AX action failure,
                // unsupported key) is an infrastructure ERROR.
                let outcome: StepOutcome = (error is TargetingError) ? .fail : .error
                report.add(StepResult(id: step.id, result: outcome, durationMs: dur,
                                      message: String(describing: error),
                                      screenshot: shot, axDump: dump))
                if !options.keepGoing { break }
            }
        }
        report.finalize(permissions: perm)
        report.artifactsDir = options.artifactsDir.path
        // Write report.json into the per-plan artifacts dir so it travels with
        // its screenshots/AX dumps and never clobbers another plan's report.
        try? reporter.write(report, to: options.artifactsDir)
        return report
    }

    private func runStep(_ step: Step, app: AXUIElement, launched: LaunchedApp,
                         targeting: Targeting, timeoutMs: Int, intervalMs: Int,
                         options: RunOptions) throws -> StepResult {
        switch step.action {
        case .launch:
            return StepResult(id: step.id, result: .pass, durationMs: 0)
        case .terminate:
            launcher.terminate(launched)
            return StepResult(id: step.id, result: .pass, durationMs: 0)
        case .wait:
            clock.sleep(step.args?.seconds ?? 0)
            return StepResult(id: step.id, result: .pass, durationMs: 0)
        case .screenshot:
            let path = step.args?.path ?? options.artifactsDir.appendingPathComponent("\(step.id).png").path
            let ok = Screenshot.captureMainDisplay(to: path)
            return StepResult(id: step.id, result: ok ? .pass : .fail, durationMs: 0,
                              screenshot: path)
        case .waitFor:
            let present = step.args?.present ?? true
            let ok = targeting.waitForPresence(step.target!, present: present, app: app,
                                               timeoutMs: timeoutMs, intervalMs: intervalMs)
            return StepResult(id: step.id, result: ok ? .pass : .fail, durationMs: 0,
                              message: ok ? nil : "element \(present ? "did not appear" : "did not disappear")")
        case .assert:
            return try runAssert(step, app: app, targeting: targeting,
                                 timeoutMs: timeoutMs, intervalMs: intervalMs, options: options)
        case .menu:
            guard let path = step.args?.menuPath, !path.isEmpty else {
                throw PlanError.decode("menu needs args.menuPath")
            }
            try MenuNavigator().selectPath(path, app: app)
            return StepResult(id: step.id, result: .pass, durationMs: 0)
        case .drag:
            let ref = try targeting.resolve(step.target!, app: app,
                                            timeoutMs: timeoutMs, intervalMs: intervalMs,
                                            baseDir: options.planBaseDir)
            guard let dest = step.args?.to else { throw PlanError.decode("drag needs args.to") }
            let destRef = try targeting.resolve(dest, app: app,
                                                timeoutMs: timeoutMs, intervalMs: intervalMs,
                                                baseDir: options.planBaseDir)
            guard let from = actions.point(for: ref), let to = actions.point(for: destRef) else {
                throw PlanError.decode("drag needs resolvable source and destination points")
            }
            EventSynthesizer.drag(from: from, to: to)
            return StepResult(id: step.id, result: .pass, durationMs: 0)
        case .click, .doubleClick, .rightClick, .press, .type, .keyPress, .setValue, .scroll:
            let ref = try targeting.resolve(step.target!, app: app,
                                            timeoutMs: timeoutMs, intervalMs: intervalMs,
                                            baseDir: options.planBaseDir)
            try actions.perform(action: step.action, args: step.args, ref: ref)
            return StepResult(id: step.id, result: .pass, durationMs: 0)
        }
    }

    private func runAssert(_ step: Step, app: AXUIElement, targeting: Targeting,
                           timeoutMs: Int, intervalMs: Int, options: RunOptions) throws -> StepResult {
        let assertion = step.assert!
        // exists / notExists assert on presence, not property value.
        if assertion.op == .exists || assertion.op == .notExists {
            let present = assertion.op == .exists
            let ok = targeting.waitForPresence(step.target!, present: present, app: app,
                                               timeoutMs: timeoutMs, intervalMs: intervalMs)
            return StepResult(id: step.id, result: ok ? .pass : .fail, durationMs: 0,
                              expected: present ? "exists" : "notExists",
                              actual: ok ? (present ? "exists" : "notExists") : (present ? "notExists" : "exists"))
        }
        guard case .ax(let el) = try targeting.resolve(step.target!, app: app,
                                                       timeoutMs: timeoutMs, intervalMs: intervalMs,
                                                       baseDir: options.planBaseDir) else {
            return StepResult(id: step.id, result: .fail, durationMs: 0,
                              message: "cannot assert property on vision-only element")
        }
        let expected = assertion.expected ?? ""
        // Poll the comparison on the same cadence as presence — a control's AX
        // value may update a beat after the action that triggered it. Succeed as
        // soon as it matches; only fail (and capture artifacts) at timeout.
        let outcome = assertions.pollEvaluate(
            op: assertion.op, expected: expected,
            timeoutMs: timeoutMs, intervalMs: intervalMs, clock: clock
        ) { assertions.readProperty(assertion.property, from: el) ?? "" }

        var result = StepResult(id: step.id, result: outcome.matched ? .pass : .fail, durationMs: 0,
                                expected: expected, actual: outcome.actual)
        if !outcome.matched {
            let dump = writeAXDump(app, stepId: step.id, dir: options.artifactsDir)
            let shot = options.artifactsDir.appendingPathComponent("\(step.id).png").path
            Screenshot.captureMainDisplay(to: shot)
            result.axDump = dump; result.screenshot = shot
        }
        return result
    }

    private func writeAXDump(_ app: AXUIElement, stepId: String, dir: URL) -> String? {
        let snap = AXTree.snapshot(app)
        let payload: [String: Any] = [
            "truncated": snap.truncated,   // never let a capped tree look complete
            "nodeCount": snap.nodes.count,
            "nodes": snap.nodes,
        ]
        let url = dir.appendingPathComponent("\(stepId).axtree.json")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
            try data.write(to: url)
            return url.path
        } catch { return nil }
    }
}
