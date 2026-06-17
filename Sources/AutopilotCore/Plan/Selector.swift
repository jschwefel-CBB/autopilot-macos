import Foundation

/// A deterministic locator for one UI element. Predicates are ANDed.
/// Resolution priority is fixed: identifier > role+attr > path > vision.
public struct Selector: Codable, Equatable, Sendable {
    public var role: String?
    public var identifier: String?
    public var title: String?
    public var label: String?
    public var value: String?
    /// Positional index path, e.g. ["window[0]", "group[2]", "button[0]"].
    public var path: [String]?
    public var vision: VisionSelector?

    public init(role: String? = nil, identifier: String? = nil, title: String? = nil,
                label: String? = nil, value: String? = nil, path: [String]? = nil,
                vision: VisionSelector? = nil) {
        self.role = role; self.identifier = identifier; self.title = title
        self.label = label; self.value = value; self.path = path; self.vision = vision
    }
}

/// Template-match fallback locator. Deterministic: fixed confidence threshold, no LLM.
public struct VisionSelector: Codable, Equatable, Sendable {
    public var image: String          // path to template PNG, relative to plan file
    public var confidence: Double     // 0...1, required match threshold
    public init(image: String, confidence: Double) {
        self.image = image; self.confidence = confidence
    }
}
