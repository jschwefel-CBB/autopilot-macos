import Testing
import Foundation
@testable import AutopilotMCPKit

@Suite struct MCPServerTests {
    /// A server whose responses are collected into an array of parsed JSON objects.
    func makeServer() -> (MCPServer, () -> [[String: Any]]) {
        var lines: [String] = []
        let server = MCPServer(sink: { lines.append($0) })
        let collect: () -> [[String: Any]] = {
            lines.compactMap { ($0.data(using: .utf8)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } }
        }
        return (server, collect)
    }

    @Test func initializeReturnsServerInfo() {
        let (s, out) = makeServer()
        s.handle(["jsonrpc": "2.0", "id": 1, "method": "initialize"])
        let r = out().first!
        let info = (r["result"] as? [String: Any])?["serverInfo"] as? [String: Any]
        #expect(info?["name"] as? String == "autopilot")
    }

    @Test func toolsListContainsAllSix() {
        let (s, out) = makeServer()
        s.handle(["jsonrpc": "2.0", "id": 2, "method": "tools/list"])
        let tools = ((out().first!["result"] as? [String: Any])?["tools"] as? [[String: Any]]) ?? []
        let names = Set(tools.compactMap { $0["name"] as? String })
        #expect(names == ["run_plan", "get_report", "dump_axtree", "find_element", "suggest_selectors", "lint_plan"])
    }

    @Test func unknownMethodIsMethodNotFound() {
        let (s, out) = makeServer()
        s.handle(["jsonrpc": "2.0", "id": 3, "method": "nope"])
        let err = out().first!["error"] as? [String: Any]
        #expect(err?["code"] as? Int == -32601)
    }

    @Test func missingMethodIsInvalidRequest() {
        let (s, out) = makeServer()
        s.handle(["jsonrpc": "2.0", "id": 4])
        let err = out().first!["error"] as? [String: Any]
        #expect(err?["code"] as? Int == -32600)
    }

    @Test func unknownToolIsInvalidParams() {
        let (s, out) = makeServer()
        s.handle(["jsonrpc": "2.0", "id": 5, "method": "tools/call",
                  "params": ["name": "does_not_exist", "arguments": [:]]])
        let err = out().first!["error"] as? [String: Any]
        #expect(err?["code"] as? Int == -32602)
    }

    @Test func getReportBeforeAnyRunErrors() {
        let (s, out) = makeServer()
        s.handle(["jsonrpc": "2.0", "id": 6, "method": "tools/call",
                  "params": ["name": "get_report", "arguments": [:]]])
        let err = out().first!["error"] as? [String: Any]
        #expect(err?["code"] as? Int == -32603)
    }

    @Test func lintPlanReportsFindings() {
        let (s, out) = makeServer()
        // A plan with a missing-terminate + no window-wait → lint findings.
        let plan: [String: Any] = [
            "schemaVersion": "1.0", "name": "p", "target": ["bundleId": "a"],
            "steps": [["id": "c", "action": "click", "target": ["identifier": "ok"]]],
        ]
        s.handle(["jsonrpc": "2.0", "id": 7, "method": "tools/call",
                  "params": ["name": "lint_plan", "arguments": ["plan": plan]]])
        let text = ((out().first!["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String ?? ""
        #expect(text.contains("terminate") || text.contains("waitFor"))
    }

    @Test func runPlanWithNeitherPlanNorPathIsInvalidParams() {
        let (s, out) = makeServer()
        s.handle(["jsonrpc": "2.0", "id": 8, "method": "tools/call",
                  "params": ["name": "run_plan", "arguments": [:]]])
        let err = out().first!["error"] as? [String: Any]
        #expect(err?["code"] as? Int == -32602)
    }
}
