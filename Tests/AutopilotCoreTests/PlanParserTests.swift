import Testing
import Foundation
@testable import AutopilotCore

@Suite struct PlanDecodingTests {
    @Test func decodesMinimalPlan() throws {
        let json = """
        {
          "schemaVersion": "1.0",
          "name": "smoke",
          "target": { "bundleId": "com.example.app" },
          "steps": [
            { "id": "c1", "action": "click",
              "target": { "role": "AXButton", "identifier": "ok" } }
          ]
        }
        """.data(using: .utf8)!
        let plan = try JSONDecoder().decode(Plan.self, from: json)
        #expect(plan.name == "smoke")
        #expect(plan.schemaVersion == "1.0")
        #expect(plan.target.bundleId == "com.example.app")
        #expect(plan.steps.count == 1)
        #expect(plan.steps[0].id == "c1")
        #expect(plan.steps[0].action == .click)
        #expect(plan.steps[0].target?.identifier == "ok")
    }
}

@Suite struct PlanValidationTests {
    @Test func rejectsUnsupportedSchemaVersion() throws {
        let json = """
        {"schemaVersion":"2.0","name":"x","target":{"bundleId":"a"},"steps":[]}
        """.data(using: .utf8)!
        #expect(throws: PlanError.self) {
            _ = try PlanParser().parse(data: json, baseDirectory: URL(fileURLWithPath: "/tmp"))
        }
    }

    @Test func rejectsTargetWithNeitherBundleIdNorPath() throws {
        let json = """
        {"schemaVersion":"1.0","name":"x","target":{},"steps":[]}
        """.data(using: .utf8)!
        #expect(throws: PlanError.self) {
            _ = try PlanParser().parse(data: json, baseDirectory: URL(fileURLWithPath: "/tmp"))
        }
    }

    @Test func rejectsDuplicateStepIds() throws {
        let json = """
        {"schemaVersion":"1.0","name":"x","target":{"bundleId":"a"},
         "steps":[{"id":"s","action":"screenshot"},{"id":"s","action":"screenshot"}]}
        """.data(using: .utf8)!
        #expect(throws: PlanError.self) {
            _ = try PlanParser().parse(data: json, baseDirectory: URL(fileURLWithPath: "/tmp"))
        }
    }

    @Test func rejectsActionRequiringTargetWithoutOne() throws {
        // click requires a target
        let json = """
        {"schemaVersion":"1.0","name":"x","target":{"bundleId":"a"},
         "steps":[{"id":"s","action":"click"}]}
        """.data(using: .utf8)!
        #expect(throws: PlanError.self) {
            _ = try PlanParser().parse(data: json, baseDirectory: URL(fileURLWithPath: "/tmp"))
        }
    }

    @Test func acceptsValidPlan() throws {
        let json = """
        {"schemaVersion":"1.0","name":"x","target":{"bundleId":"a"},
         "steps":[{"id":"s","action":"click","target":{"identifier":"ok"}}]}
        """.data(using: .utf8)!
        let plan = try PlanParser().parse(data: json, baseDirectory: URL(fileURLWithPath: "/tmp"))
        #expect(plan.steps.count == 1)
    }
}
