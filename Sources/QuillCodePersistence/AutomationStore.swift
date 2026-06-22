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
        let data = try encoder.encode(QuillAutomation.sortedForDisplay(automations))
        try data.write(to: fileURL, options: .atomic)
    }

    public func load() throws -> [QuillAutomation] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: fileURL)
        return QuillAutomation.sortedForDisplay(try decoder.decode([QuillAutomation].self, from: data))
    }
}
