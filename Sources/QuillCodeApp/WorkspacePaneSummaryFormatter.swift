import Foundation

enum WorkspacePaneSummaryFormatter {
    static func count(_ count: Int, singular: String, plural: String? = nil) -> String {
        "\(count) \(count == 1 ? singular : plural ?? "\(singular)s")"
    }

    static func joinedCounts(_ counts: [(count: Int, singular: String, plural: String?)]) -> String {
        counts
            .map { count($0.count, singular: $0.singular, plural: $0.plural) }
            .joined(separator: " · ")
    }

    static func optionalCount(_ count: Int, singular: String, plural: String? = nil) -> [String] {
        count == 0 ? [] : [Self.count(count, singular: singular, plural: plural)]
    }
}
