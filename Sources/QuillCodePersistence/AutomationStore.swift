import Foundation
import QuillCodeCore

public struct JSONAutomationStore: Sendable {
    public static let maximumBytes = 16 * 1_024 * 1_024

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
        guard data.count <= Self.maximumBytes else {
            throw BoundedFileDataError.exceedsSizeLimit(maximumBytes: Self.maximumBytes)
        }
        try data.write(to: fileURL, options: .atomic)
    }

    public func load() throws -> [QuillAutomation] {
        guard let data = try BoundedFileDataReader.readIfPresent(
            from: fileURL,
            maximumBytes: Self.maximumBytes
        ) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return QuillAutomation.sortedForDisplay(try decoder.decode([QuillAutomation].self, from: data))
    }
}
