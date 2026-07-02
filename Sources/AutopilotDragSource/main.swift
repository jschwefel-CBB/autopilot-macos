import AppKit

// AutopilotDragSource — a tiny foreground helper app whose sole job is to
// perform a REAL cross-process file drag-and-drop, then exit.
//
// AutoPilot's macOS backend cannot originate a drag from the `autopilot` CLI:
// a bare command-line Mach-O never becomes a foreground GUI app, so its source
// window never receives the synthetic seed mouseDown that starts the drag. A
// properly-bundled foreground .app CAN, so MacOSDriver launches THIS helper with
// the resolved drop point + files and waits for it to finish.
//
// Usage: AutopilotDragSource <x> <y> <file1> [file2 ...]
//   <x> <y> — drop point in CoreGraphics (top-left origin) screen coordinates.
//   files   — one or more existing file paths to drop.
// Exit codes: 0 = drop delivered (session ended with an operation),
//             2 = bad arguments, 3 = a file was missing, 4 = drop not accepted.

let rawArgs = Array(CommandLine.arguments.dropFirst())
guard rawArgs.count >= 3, let px = Double(rawArgs[0]), let py = Double(rawArgs[1]) else {
    FileHandle.standardError.write("usage: AutopilotDragSource <x> <y> <file>...\n".data(using: .utf8)!)
    exit(2)
}
let target = CGPoint(x: px, y: py)
let files = Array(rawArgs.dropFirst(2)).map { URL(fileURLWithPath: $0) }
for u in files where !FileManager.default.fileExists(atPath: u.path) {
    FileHandle.standardError.write("file does not exist: \(u.path)\n".data(using: .utf8)!)
    exit(3)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)

/// The drag source view. Its `mouseDown:` (delivered by the seed synthetic
/// click) starts a real `NSDraggingSession` carrying the file URLs.
final class DragSourceView: NSView, NSDraggingSource {
    var urls: [URL] = []
    var accepted = false
    var ended = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        // One NSDraggingItem per file, backed by an NSURL (NSPasteboardWriting):
        // AppKit vends public.file-url AND bridges the legacy NSFilenamesPboardType,
        // so a destination reading EITHER type receives ALL files.
        let items = urls.enumerated().map { index, url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            if index == 0 {
                item.setDraggingFrame(NSRect(x: 0, y: 0, width: 32, height: 32), contents: icon)
            } else {
                item.setDraggingFrame(NSRect(x: 0, y: 0, width: 1, height: 1), contents: nil)
            }
            return item
        }
        beginDraggingSession(with: items, event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    func draggingSession(_ session: NSDraggingSession,
                         endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        accepted = operation != []
        ended = true
    }
}

let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
// Source window near screen CENTER (a corner can fall under the Dock/menu bar,
// so the seed click would miss it).
let winFrame = NSRect(x: screen.midX - 30, y: screen.midY - 30, width: 60, height: 60)
let window = NSWindow(contentRect: winFrame, styleMask: [.borderless], backing: .buffered, defer: false)
let src = DragSourceView()
src.urls = files
window.contentView = src
window.isOpaque = false
window.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.15)
window.level = .floating
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)

/// Post a mouse CGEvent to the HID tap. `.cghidEventTap` moves the REAL system
/// cursor — which is what the WindowServer follows to route the drag to the
/// destination process for cross-process delivery.
func post(_ type: CGEventType, _ p: CGPoint, dx: CGFloat = 0, dy: CGFloat = 0) {
    guard let e = CGEvent(mouseEventSource: nil, mouseType: type,
                          mouseCursorPosition: p, mouseButton: .left) else { return }
    if type == .leftMouseDragged {
        e.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx))
        e.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy))
    }
    e.post(tap: .cghidEventTap)
}

// Drive the drag once the run loop is up and the window is realized.
DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
    let screenH = screen.height
    let s = CGPoint(x: winFrame.midX, y: screenH - winFrame.midY)   // source center, CG space

    // Steering runs DURING beginDraggingSession's modal loop, so schedule it:
    // interpolate the real cursor from source -> target in many small steps,
    // then dwell on the target so draggingEntered/Updated latch, then release.
    let steps = 40
    var prev = s
    for i in 0...steps {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(i * 20)) {
            let t = Double(i) / Double(steps)
            let p = CGPoint(x: s.x + (target.x - s.x) * t, y: s.y + (target.y - s.y) * t)
            post(.leftMouseDragged, p, dx: p.x - prev.x, dy: p.y - prev.y)
            prev = p
        }
    }
    for d in 1...4 {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds((steps + d) * 20)) {
            post(.leftMouseDragged, target)
        }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds((steps + 6) * 20)) {
        post(.leftMouseUp, target)
        // Give the destination's drop handler a beat, then exit with a status.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            exit(src.accepted ? 0 : 4)
        }
    }

    // Originate the drag: move to the source, then press (the real mouseDown:
    // that starts the session).
    post(.mouseMoved, s)
    usleep(30_000)
    post(.leftMouseDown, s)
}

// Safety valve: never hang forever.
DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { exit(src.accepted ? 0 : 4) }

app.run()
