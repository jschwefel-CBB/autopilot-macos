import Testing
import Foundation
@testable import AutopilotCore

@Suite struct SelectorMatcherTests {
    // A snapshot node is a [String:String] as produced by AXTree.snapshot.
    @Test func matchesByIdentifier() {
        let node = ["role": "AXButton", "identifier": "okButton", "title": "OK"]
        #expect(AXResolver.matches(node: node, selector: Selector(identifier: "okButton")))
        #expect(!AXResolver.matches(node: node, selector: Selector(identifier: "cancel")))
    }

    @Test func matchesByRoleAndTitle() {
        let node = ["role": "AXButton", "title": "OK"]
        #expect(AXResolver.matches(node: node, selector: Selector(role: "AXButton", title: "OK")))
        #expect(!AXResolver.matches(node: node, selector: Selector(role: "AXButton", title: "No")))
    }

    @Test func andsAllPredicates() {
        let node = ["role": "AXButton", "identifier": "okButton", "title": "OK"]
        // identifier matches but role does not -> no match
        #expect(!AXResolver.matches(node: node,
            selector: Selector(role: "AXTextField", identifier: "okButton")))
    }

    @Test func emptySelectorMatchesNothing() {
        let node = ["role": "AXButton"]
        #expect(!AXResolver.matches(node: node, selector: Selector()))
    }
}
