import Foundation

/// Deterministic template matching via normalized cross-correlation.
/// Pure math over grayscale buffers; image decoding lives in the platform driver.
public enum VisionResolver {
    public struct Match { public var x: Int; public var y: Int; public var score: Double }

    /// Pure NCC over grayscale buffers. Returns the best top-left match, or nil
    /// if the correlation is undefined (e.g. zero-variance window).
    public static func bestMatch(haystack: [[Double]], needle: [[Double]]) -> Match? {
        let H = haystack.count, W = haystack.first?.count ?? 0
        let h = needle.count, w = needle.first?.count ?? 0
        guard H >= h, W >= w, h > 0, w > 0 else { return nil }

        // Precompute needle mean/variance.
        var nSum = 0.0
        for row in needle { for v in row { nSum += v } }
        let nMean = nSum / Double(h * w)
        var nVar = 0.0
        for row in needle { for v in row { nVar += (v - nMean) * (v - nMean) } }
        guard nVar > 0 else { return nil }

        var best: Match? = nil
        for oy in 0...(H - h) {
            for ox in 0...(W - w) {
                var wSum = 0.0
                for y in 0..<h { for x in 0..<w { wSum += haystack[oy + y][ox + x] } }
                let wMean = wSum / Double(h * w)
                var cov = 0.0, wVar = 0.0
                for y in 0..<h {
                    for x in 0..<w {
                        let a = haystack[oy + y][ox + x] - wMean
                        let b = needle[y][x] - nMean
                        cov += a * b
                        wVar += a * a
                    }
                }
                guard wVar > 0 else { continue }
                let score = cov / (wVar.squareRoot() * nVar.squareRoot())
                if best == nil || score > best!.score {
                    best = Match(x: ox, y: oy, score: score)
                }
            }
        }
        return best
    }
}
