import Foundation

public struct PlanParser {
    public static let supportedSchemaVersion = "1.0"
    public static let maxIncludeDepth = 8

    public init() {}

    /// Parse raw JSON into a validated Plan. `baseDirectory` is the directory
    /// the plan file lives in, used to resolve `include` paths (Task 4).
    public func parse(data: Data, baseDirectory: URL) throws -> Plan {
        let plan: Plan
        do {
            plan = try JSONDecoder().decode(Plan.self, from: data)
        } catch {
            throw PlanError.decode(String(describing: error))
        }
        let resolved = try resolveIncludes(plan, baseDirectory: baseDirectory,
                                           stack: [], depth: 0)
        try validate(resolved)
        return resolved
    }

    /// Resolve includes — real implementation lands in Task 4. For now, no includes.
    func resolveIncludes(_ plan: Plan, baseDirectory: URL,
                         stack: [String], depth: Int) throws -> Plan {
        return plan
    }

    func validate(_ plan: Plan) throws {
        guard plan.schemaVersion == Self.supportedSchemaVersion else {
            throw PlanError.unsupportedSchemaVersion(plan.schemaVersion)
        }
        if (plan.target.bundleId?.isEmpty ?? true) && (plan.target.path?.isEmpty ?? true) {
            throw PlanError.invalidTarget("must set either bundleId or path")
        }
        var seen = Set<String>()
        for step in plan.steps {
            if !seen.insert(step.id).inserted {
                throw PlanError.duplicateStepId(step.id)
            }
            try validateStep(step)
        }
    }

    private static let targetRequiringActions: Set<Action> = [
        .click, .doubleClick, .rightClick, .type, .keyPress, .setValue, .scroll, .waitFor, .assert
    ]

    func validateStep(_ step: Step) throws {
        if Self.targetRequiringActions.contains(step.action), step.target == nil {
            throw PlanError.missingTarget(stepId: step.id, action: step.action.rawValue)
        }
        switch step.action {
        case .type, .setValue:
            if step.args?.text == nil {
                throw PlanError.missingArgs(stepId: step.id, action: step.action.rawValue, field: "text")
            }
        case .keyPress:
            if step.args?.keys == nil {
                throw PlanError.missingArgs(stepId: step.id, action: step.action.rawValue, field: "keys")
            }
        case .assert:
            if step.assert == nil {
                throw PlanError.missingArgs(stepId: step.id, action: step.action.rawValue, field: "assert")
            }
        case .wait:
            if step.args?.seconds == nil {
                throw PlanError.missingArgs(stepId: step.id, action: step.action.rawValue, field: "seconds")
            }
        default:
            break
        }
    }
}
