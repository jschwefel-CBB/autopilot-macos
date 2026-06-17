import AppKit

final class AppController: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
        styleMask: [.titled, .closable], backing: .buffered, defer: false)
    let nameField = NSTextField(frame: NSRect(x: 20, y: 150, width: 200, height: 24))
    let statusLabel = NSTextField(labelWithString: "status: ")
    let countLabel = NSTextField(labelWithString: "count: 0")
    var count = 0

    func applicationDidFinishLaunching(_ note: Notification) {
        window.title = "TestHostApp"
        let content = NSView(frame: window.contentView!.bounds)

        nameField.setAccessibilityIdentifier("nameField")
        nameField.target = self
        nameField.action = #selector(nameChanged)
        nameField.delegate = self   // live updates on every keystroke
        content.addSubview(nameField)

        statusLabel.frame = NSRect(x: 20, y: 110, width: 320, height: 20)
        statusLabel.setAccessibilityIdentifier("statusLabel")
        content.addSubview(statusLabel)

        countLabel.frame = NSRect(x: 20, y: 80, width: 320, height: 20)
        countLabel.setAccessibilityIdentifier("countLabel")
        content.addSubview(countLabel)

        let okButton = NSButton(title: "OK", target: self, action: #selector(okTapped))
        okButton.frame = NSRect(x: 20, y: 30, width: 80, height: 28)
        okButton.setAccessibilityIdentifier("okButton")
        content.addSubview(okButton)

        window.contentView = content
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func nameChanged() {
        statusLabel.stringValue = "status: \(nameField.stringValue)"
    }

    // Live update on every keystroke so GUI tests can observe derived state
    // without needing the field to commit (Enter / focus-loss).
    func controlTextDidChange(_ obj: Notification) {
        statusLabel.stringValue = "status: \(nameField.stringValue)"
    }

    @objc func okTapped() {
        count += 1
        countLabel.stringValue = "count: \(count)"
    }
}

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.setActivationPolicy(.regular)
app.run()
