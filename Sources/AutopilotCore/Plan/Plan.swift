import Foundation

public struct TargetApp: Codable, Equatable, Sendable {
    public var bundleId: String?
    public var path: String?
    public var launchArgs: [String]?
    public var launchFiles: [String]?
    public init(bundleId: String? = nil, path: String? = nil,
                launchArgs: [String]? = nil, launchFiles: [String]? = nil) {
        self.bundleId = bundleId; self.path = path
        self.launchArgs = launchArgs; self.launchFiles = launchFiles
    }
}

public struct PlanDefaults: Codable, Equatable, Sendable {
    public var timeoutMs: Int?
    public var retryIntervalMs: Int?
    public init(timeoutMs: Int? = nil, retryIntervalMs: Int? = nil) {
        self.timeoutMs = timeoutMs; self.retryIntervalMs = retryIntervalMs
    }
}

public struct Step: Codable, Equatable, Sendable {
    public var id: String
    public var action: Action
    public var target: Selector?
    public var args: ActionArgs?
    public var assert: Assertion?
    public var timeoutMs: Int?
    public init(id: String, action: Action, target: Selector? = nil,
                args: ActionArgs? = nil, assert: Assertion? = nil, timeoutMs: Int? = nil) {
        self.id = id; self.action = action; self.target = target
        self.args = args; self.assert = assert; self.timeoutMs = timeoutMs
    }
}

public struct Plan: Codable, Equatable, Sendable {
    public var schemaVersion: String
    public var name: String
    public var include: [String]?
    public var target: TargetApp
    public var defaults: PlanDefaults?
    public var steps: [Step]
    public init(schemaVersion: String, name: String, include: [String]? = nil,
                target: TargetApp, defaults: PlanDefaults? = nil, steps: [Step]) {
        self.schemaVersion = schemaVersion; self.name = name; self.include = include
        self.target = target; self.defaults = defaults; self.steps = steps
    }
}
