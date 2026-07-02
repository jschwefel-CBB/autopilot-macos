import Foundation
import CoreGraphics

/// Performs a REAL cross-process file drop by launching the bundled
/// `AutopilotDragSource.app` helper.
///
/// Why a helper app and not inline code: originating a drag requires a real
/// foreground GUI app whose window can receive the synthetic seed mouse-down.
/// The `autopilot` CLI is a bare command-line Mach-O — it never becomes a
/// foreground app, so an in-process drag source's window never receives the
/// click and the drag never starts. A properly-bundled `.app` does. The helper
/// takes the drop point + files, performs a genuine `NSDraggingSession` (the
/// destination's real AppKit handlers fire with `public.file-url` +
/// `NSFilenamesPboardType`), and exits.
public enum FileDragSource {

    /// Drop `files` onto screen `point` (CoreGraphics / top-left coordinate
    /// space — the same space `EventSynthesizer` uses). Throws if the list is
    /// empty, a file is missing, the helper cannot be located, or the drop is
    /// not accepted.
    public static func drop(files: [String], at point: CGPoint) throws {
        guard !files.isEmpty else { throw FileDragError.noFiles }
        for f in files where !FileManager.default.fileExists(atPath: f) {
            throw FileDragError.missingFile(f)
        }
        guard let helper = locateHelper() else { throw FileDragError.helperNotFound }

        let proc = Process()
        proc.executableURL = helper
        proc.arguments = [String(Int(point.x.rounded())), String(Int(point.y.rounded()))] + files
        let errPipe = Pipe()
        proc.standardError = errPipe
        do {
            try proc.run()
        } catch {
            throw FileDragError.helperLaunchFailed(error.localizedDescription)
        }
        proc.waitUntilExit()

        switch proc.terminationStatus {
        case 0:
            return
        default:
            let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                             encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw FileDragError.dropFailed(status: proc.terminationStatus, message: msg)
        }
    }

    /// Find the `AutopilotDragSource` helper executable. Resolution order:
    ///  1. `AUTOPILOT_DRAG_SOURCE` env var (explicit override — used by tests).
    ///  2. `AutopilotDragSource.app/Contents/MacOS/AutopilotDragSource` next to
    ///     the running binary (the shipped layout).
    ///  3. A bare `AutopilotDragSource` binary next to the running binary
    ///     (the `swift build` layout, where products sit side by side).
    static func locateHelper() -> URL? {
        let fm = FileManager.default
        if let override = ProcessInfo.processInfo.environment["AUTOPILOT_DRAG_SOURCE"],
           fm.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }
        let binDir = URL(fileURLWithPath: CommandLine.arguments.first ?? "/usr/local/bin/autopilot")
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()

        let bundled = binDir
            .appendingPathComponent("AutopilotDragSource.app/Contents/MacOS/AutopilotDragSource")
        if fm.isExecutableFile(atPath: bundled.path) { return bundled }

        let bare = binDir.appendingPathComponent("AutopilotDragSource")
        if fm.isExecutableFile(atPath: bare.path) { return bare }

        return nil
    }
}

/// Error surfaced when a file drag cannot proceed.
public enum FileDragError: Error, CustomStringConvertible {
    case noFiles
    case missingFile(String)
    case helperNotFound
    case helperLaunchFailed(String)
    case dropFailed(status: Int32, message: String)
    public var description: String {
        switch self {
        case .noFiles: return "file drag: no files provided"
        case .missingFile(let p): return "file drag: file does not exist: \(p)"
        case .helperNotFound:
            return "file drag: could not locate AutopilotDragSource helper (set AUTOPILOT_DRAG_SOURCE or install it next to autopilot)"
        case .helperLaunchFailed(let m): return "file drag: failed to launch drag helper: \(m)"
        case .dropFailed(let status, let message):
            return "file drag: drop not delivered (helper exit \(status))" + (message.isEmpty ? "" : ": \(message)")
        }
    }
}
