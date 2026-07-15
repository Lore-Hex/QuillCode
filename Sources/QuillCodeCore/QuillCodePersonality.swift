import Foundation

public enum QuillCodePersonality: String, Codable, Sendable, CaseIterable, Hashable {
    case friendly
    case pragmatic
    case none

    public static let defaultValue: Self = .pragmatic

    public var displayName: String {
        switch self {
        case .friendly: "Friendly"
        case .pragmatic: "Pragmatic"
        case .none: "None"
        }
    }

    public var summary: String {
        switch self {
        case .friendly:
            "Warm and conversational while staying focused on the work."
        case .pragmatic:
            "Direct, concise, and explicit about actions, evidence, and tradeoffs."
        case .none:
            "No additional communication-style guidance."
        }
    }

    public static func parse(_ value: String) -> Self? {
        Self(rawValue: value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}
