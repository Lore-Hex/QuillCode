import Foundation
import QuillCodeCore

public struct JSONAutomationStore: Sendable {
    public var fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func save(_ automations: [QuillAutomation]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Self.sorted(automations))
        try data.write(to: fileURL, options: .atomic)
    }

    public func load() throws -> [QuillAutomation] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: fileURL)
        return Self.sorted(try decoder.decode([QuillAutomation].self, from: data))
    }

    private static func sorted(_ automations: [QuillAutomation]) -> [QuillAutomation] {
        automations.sorted { lhs, rhs in
            if lhs.status != rhs.status {
                return lhs.status == .active
            }
            switch (lhs.nextRunAt, rhs.nextRunAt) {
            case let (lhsRun?, rhsRun?) where lhsRun != rhsRun:
                return lhsRun < rhsRun
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            default:
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
    }
}
