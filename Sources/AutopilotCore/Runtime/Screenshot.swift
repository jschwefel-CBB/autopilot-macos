import Foundation
import CoreGraphics
import AppKit

public enum Screenshot {
    /// Capture a screen rectangle to a PNG at `path`. Returns true on success.
    @discardableResult
    public static func captureRegion(_ rect: CGRect, to path: String) -> Bool {
        guard let image = try? ScreenCapture.image(of: rect) else { return false }
        return writePNG(image, to: path)
    }

    /// Capture the full main display to a PNG at `path`. Returns true on success.
    @discardableResult
    public static func captureMainDisplay(to path: String) -> Bool {
        let displayID = CGMainDisplayID()
        let rect = CGRect(x: 0, y: 0,
                          width: CGFloat(CGDisplayPixelsWide(displayID)),
                          height: CGFloat(CGDisplayPixelsHigh(displayID)))
        guard let image = try? ScreenCapture.image(of: rect) else { return false }
        return writePNG(image, to: path)
    }

    private static func writePNG(_ image: CGImage, to path: String) -> Bool {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        do { try data.write(to: URL(fileURLWithPath: path)); return true } catch { return false }
    }
}
