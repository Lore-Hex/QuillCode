import Foundation

enum WorkspaceActivityText {
    static func boundedLine(_ value: String, limit: Int) -> String {
        let normalized = value
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard normalized.count > limit else { return normalized }
        return "\(String(normalized.prefix(limit)))..."
    }

    static func countLabel(_ count: Int, singular: String) -> String {
        "\(count) \(singular)\(count == 1 ? "" : "s")"
    }

    static func sourceTitle(_ path: String) -> String {
        let title = URL(fileURLWithPath: path).lastPathComponent
        return title.isEmpty ? path : title
    }

    static func summary(count: Int, singular: String, details: [String]) -> String {
        guard count > 0 else { return "none" }
        let countText = countLabel(count, singular: singular)
        guard !details.isEmpty else { return countText }
        return "\(countText) (\(details.joined(separator: ", ")))"
    }
}
