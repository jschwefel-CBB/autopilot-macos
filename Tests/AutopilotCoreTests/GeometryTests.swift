import Testing
@testable import AutopilotCore

@Suite struct GeometryTests {
    @Test func rectMidpoints() {
        let r = Rect(x: 10, y: 20, width: 100, height: 40)
        #expect(r.midX == 60)
        #expect(r.midY == 40)
    }
    @Test func pointEquatable() {
        #expect(Point(x: 1, y: 2) == Point(x: 1, y: 2))
        #expect(Point(x: 1, y: 2) != Point(x: 2, y: 1))
    }
    @Test func resolvedElementPointCase() {
        let re = ResolvedElement.point(Point(x: 5, y: 6))
        guard case .point(let p) = re else { Issue.record("expected point"); return }
        #expect(p == Point(x: 5, y: 6))
    }
}
