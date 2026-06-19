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

    @Test func dragNeedsToOrToFiles() throws {
        let json = """
        {"schemaVersion":"1.0","name":"x","target":{"bundleId":"a"},
         "steps":[{"id":"d","action":"drag","target":{"identifier":"src"}}]}
        """.data(using: .utf8)!
        #expect(throws: PlanError.self) {
            _ = try PlanParser().parse(data: json, baseDirectory: URL(fileURLWithPath: "/tmp"))
        }
    }

    @Test func dragWithDestinationIsValid() throws {
        let json = """
        {"schemaVersion":"1.0","name":"x","target":{"bundleId":"a"},
         "steps":[{"id":"d","action":"drag","target":{"identifier":"src"},
                   "args":{"to":{"identifier":"dst"}}}]}
        """.data(using: .utf8)!
        let plan = try PlanParser().parse(data: json, baseDirectory: URL(fileURLWithPath: "/tmp"))
        #expect(plan.steps[0].args?.to?.identifier == "dst")
    }

    @Test func assertPixelNeedsColorAtParse() throws {
        let json = """
        {"schemaVersion":"1.0","name":"x","target":{"bundleId":"a"},
         "steps":[{"id":"p","action":"assertPixel","args":{"atX":1,"atY":1}}]}
        """.data(using: .utf8)!
        #expect(throws: PlanError.self) {
            _ = try PlanParser().parse(data: json, baseDirectory: URL(fileURLWithPath: "/tmp"))
        }
    }

    @Test func assertRegionNeedsColorAtParse() throws {
        let json = """
        {"schemaVersion":"1.0","name":"x","target":{"bundleId":"a"},
         "steps":[{"id":"r","action":"assertRegion","args":{"atX":1,"atY":1,"width":4,"height":4}}]}
        """.data(using: .utf8)!
        #expect(throws: PlanError.self) {
            _ = try PlanParser().parse(data: json, baseDirectory: URL(fileURLWithPath: "/tmp"))
        }
    }

    @Test func snapshotNeedsReferenceAtParse() throws {
        let json = """
        {"schemaVersion":"1.0","name":"x","target":{"bundleId":"a"},
         "steps":[{"id":"s","action":"snapshot","args":{"atX":1,"atY":1}}]}
        """.data(using: .utf8)!
        #expect(throws: PlanError.self) {
            _ = try PlanParser().parse(data: json, baseDirectory: URL(fileURLWithPath: "/tmp"))
        }
    }

    @Test func keyPressBadChordRejectedAtParse() throws {
        let json = """
        {"schemaVersion":"1.0","name":"x","target":{"bundleId":"a"},
         "steps":[{"id":"k","action":"keyPress","target":{"identifier":"e"},"args":{"keys":"cmd+frobnicate"}}]}
        """.data(using: .utf8)!
        #expect(throws: PlanError.self) {
            _ = try PlanParser().parse(data: json, baseDirectory: URL(fileURLWithPath: "/tmp"))
        }
    }

    @Test func scrollNeedsADelta() throws {
        let json = """
        {"schemaVersion":"1.0","name":"x","target":{"bundleId":"a"},
         "steps":[{"id":"s","action":"scroll","target":{"identifier":"e"}}]}
        """.data(using: .utf8)!
        #expect(throws: PlanError.self) {
            _ = try PlanParser().parse(data: json, baseDirectory: URL(fileURLWithPath: "/tmp"))
        }
    }

    @Test func numericAssertNeedsNumericExpected() throws {
        let json = """
        {"schemaVersion":"1.0","name":"x","target":{"bundleId":"a"},
         "steps":[{"id":"a","action":"assert","target":{"identifier":"e"},
                   "assert":{"property":"value","op":"greaterThan","expected":"notanumber"}}]}
        """.data(using: .utf8)!
        #expect(throws: PlanError.self) {
            _ = try PlanParser().parse(data: json, baseDirectory: URL(fileURLWithPath: "/tmp"))
        }
    }

    @Test func matchesAssertNeedsValidRegex() throws {
        let json = """
        {"schemaVersion":"1.0","name":"x","target":{"bundleId":"a"},
         "steps":[{"id":"a","action":"assert","target":{"identifier":"e"},
                   "assert":{"property":"value","op":"matches","expected":"[unterminated"}}]}
        """.data(using: .utf8)!
        #expect(throws: PlanError.self) {
            _ = try PlanParser().parse(data: json, baseDirectory: URL(fileURLWithPath: "/tmp"))
        }
    }

    @Test func validAssertionsAndChordsParse() throws {
        let json = """
        {"schemaVersion":"1.0","name":"x","target":{"bundleId":"a"},
         "steps":[
           {"id":"k","action":"keyPress","target":{"identifier":"e"},"args":{"keys":"cmd+s"}},
           {"id":"sc","action":"scroll","target":{"identifier":"e"},"args":{"deltaY":-100}},
           {"id":"g","action":"assert","target":{"identifier":"e"},"assert":{"property":"value","op":"greaterThan","expected":"5"}},
           {"id":"m","action":"assert","target":{"identifier":"e"},"assert":{"property":"value","op":"matches","expected":"\\\\d+"}}
         ]}
        """.data(using: .utf8)!
        let plan = try PlanParser().parse(data: json, baseDirectory: URL(fileURLWithPath: "/tmp"))
        #expect(plan.steps.count == 4)
    }

    @Test func menuNeedsMenuPath() throws {
        let json = """
        {"schemaVersion":"1.0","name":"x","target":{"bundleId":"a"},
         "steps":[{"id":"m","action":"menu"}]}
        """.data(using: .utf8)!
        #expect(throws: PlanError.self) {
            _ = try PlanParser().parse(data: json, baseDirectory: URL(fileURLWithPath: "/tmp"))
        }
    }

    @Test func selectorIndexAndWithinDecode() throws {
        let json = """
        {"schemaVersion":"1.0","name":"x","target":{"bundleId":"a"},
         "steps":[{"id":"s","action":"click",
           "target":{"role":"AXButton","index":2,
                     "within":{"role":"AXRow","index":0}}}]}
        """.data(using: .utf8)!
        let plan = try PlanParser().parse(data: json, baseDirectory: URL(fileURLWithPath: "/tmp"))
        let sel = plan.steps[0].target!
        #expect(sel.index == 2)
        #expect(sel.withinSelector?.role == "AXRow")
        #expect(sel.withinSelector?.index == 0)
    }

    @Test func assertPixelWithColorAndPointIsValid() throws {
        // A complete assertPixel (color + absolute point) parses fine.
        let json = """
        {"schemaVersion":"1.0","name":"x","target":{"bundleId":"a"},
         "steps":[{"id":"p","action":"assertPixel","args":{"atX":10,"atY":10,"color":"#FF0000"}}]}
        """.data(using: .utf8)!
        let plan = try PlanParser().parse(data: json, baseDirectory: URL(fileURLWithPath: "/tmp"))
        #expect(plan.steps[0].args?.color == "#FF0000")
    }
}
