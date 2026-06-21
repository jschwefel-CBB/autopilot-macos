import Testing
@testable import AutopilotCore

@Suite struct VisionResolverPureTests {
    @Test func bestMatchFindsNeedle() {
        // A 2x2 needle WITH internal structure (variance) — NCC is undefined for a
        // uniform template, so a real template always has structure. Stamp it at
        // (1,1) in a 4x4 zero haystack and confirm it is located there.
        let needle: [[Double]] = [[1, 0], [0, 1]]
        var haystack = Array(repeating: Array(repeating: 0.0, count: 4), count: 4)
        for y in 0..<2 { for x in 0..<2 { haystack[1 + y][1 + x] = needle[y][x] } }
        let m = VisionResolver.bestMatch(haystack: haystack, needle: needle)
        #expect(m != nil)
        #expect(m?.x == 1); #expect(m?.y == 1)
    }
    @Test func zeroVarianceNeedleReturnsNil() {
        // A flat template has zero variance: NCC is undefined, must return nil.
        #expect(VisionResolver.bestMatch(haystack: [[0.5, 0.5], [0.5, 0.5]], needle: [[0.5]]) == nil)
    }
}
