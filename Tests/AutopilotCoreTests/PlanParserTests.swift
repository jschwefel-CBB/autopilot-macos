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
