import Foundation
import AppKit

public struct LaunchedApp {
    public let pid: pid_t
    public let runningApp: NSRunningApplication
}

public enum AppLaunchError: Error, CustomStringConvertible {
    case notFound(String)
    case launchFailed(String)
    public var description: String {
        switch self {
        case .notFound(let s): return "App not found: \(s)"
        case .launchFailed(let s): return "Failed to launch: \(s)"
        }
    }
}

public struct AppLauncher {
    public init() {}

    /// Resolve the app URL from a TargetApp (bundleId or explicit path).
    public func resolveURL(_ target: TargetApp) throws -> URL {
        if let path = target.path { return URL(fileURLWithPath: path) }
        if let bundleId = target.bundleId,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return url
        }
        throw AppLaunchError.notFound(target.bundleId ?? target.path ?? "?")
    }

    /// Launch the target app, opening any launchFiles, and return the running app.
    public func launch(_ target: TargetApp) throws -> LaunchedApp {
        let url = try resolveURL(target)
        let config = NSWorkspace.OpenConfiguration()
        if let args = target.launchArgs { config.arguments = args }
        let fileURLs = (target.launchFiles ?? []).map { URL(fileURLWithPath: $0) }

        let sem = DispatchSemaphore(value: 0)
        var result: Result<NSRunningApplication, Error>?
        let completion: (NSRunningApplication?, Error?) -> Void = { app, err in
            if let app { result = .success(app) }
            else { result = .failure(err ?? AppLaunchError.launchFailed(url.path)) }
            sem.signal()
        }
        if fileURLs.isEmpty {
            NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: completion)
        } else {
            NSWorkspace.shared.open(fileURLs, withApplicationAt: url, configuration: config, completionHandler: completion)
        }
        sem.wait()
        switch result! {
        case .success(let app): return LaunchedApp(pid: app.processIdentifier, runningApp: app)
        case .failure(let err): throw err
        }
    }

    public func terminate(_ app: LaunchedApp) {
        app.runningApp.terminate()
    }
}
