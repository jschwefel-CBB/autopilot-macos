import Foundation
import ApplicationServices

/// Resolves a Selector against a running app's AX tree.
public struct AXResolver {
    public init() {}

    /// Pure predicate: does a snapshot node satisfy the selector?
    /// All present predicates are ANDed. An all-nil selector matches nothing.
    public static func matches(node: [String: String], selector: Selector) -> Bool {
        var anyPredicate = false
        func check(_ value: String?, _ key: String) -> Bool {
            guard let value else { return true }      // predicate absent: no constraint
            anyPredicate = true
            return node[key] == value
        }
        let ok = check(selector.role, "role")
            && check(selector.identifier, "identifier")
            && check(selector.title, "title")
            && check(selector.label, "label")
            && check(selector.value, "value")
        return anyPredicate && ok
    }

    /// Resolve to exactly one AX element. Throws on zero or multiple matches.
    /// `path` and `vision` are handled by the Targeting orchestrator, not here.
    public func resolveOne(in appElement: AXUIElement, selector: Selector) throws -> AXUIElement {
        var matches: [AXUIElement] = []
        AXTree.walk(appElement) { el in
            var node: [String: String] = [:]
            if let r = AXTree.string(el, kAXRoleAttribute as String) { node["role"] = r }
            if let id = AXTree.string(el, kAXIdentifierAttribute as String) { node["identifier"] = id }
            if let t = AXTree.string(el, kAXTitleAttribute as String) { node["title"] = t }
            if let v = AXTree.string(el, kAXValueAttribute as String) { node["value"] = v }
            if Self.matches(node: node, selector: selector) { matches.append(el) }
        }
        let desc = Self.describe(selector)
        if matches.isEmpty { throw TargetingError.notFound(selector: desc) }
        if matches.count > 1 { throw TargetingError.ambiguous(selector: desc, count: matches.count) }
        return matches[0]
    }

    /// Count matches (for waitFor present/absent checks) without throwing.
    public func count(in appElement: AXUIElement, selector: Selector) -> Int {
        var n = 0
        AXTree.walk(appElement) { el in
            var node: [String: String] = [:]
            if let r = AXTree.string(el, kAXRoleAttribute as String) { node["role"] = r }
            if let id = AXTree.string(el, kAXIdentifierAttribute as String) { node["identifier"] = id }
            if let t = AXTree.string(el, kAXTitleAttribute as String) { node["title"] = t }
            if let v = AXTree.string(el, kAXValueAttribute as String) { node["value"] = v }
            if Self.matches(node: node, selector: selector) { n += 1 }
        }
        return n
    }

    static func describe(_ s: Selector) -> String {
        var parts: [String] = []
        if let r = s.role { parts.append("role=\(r)") }
        if let id = s.identifier { parts.append("identifier=\(id)") }
        if let t = s.title { parts.append("title=\(t)") }
        if let l = s.label { parts.append("label=\(l)") }
        if let v = s.value { parts.append("value=\(v)") }
        if let p = s.path { parts.append("path=\(p.joined(separator: "/"))") }
        return "{" + parts.joined(separator: ", ") + "}"
    }
}
