import Foundation
import QuillCodeCore

public struct JSONProjectStore: Sendable {
    public static let maximumBytes = 16 * 1_024 * 1_024

    public var fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func save(_ projects: [ProjectRef]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(projects)
        guard data.count <= Self.maximumBytes else {
            throw BoundedFileDataError.exceedsSizeLimit(maximumBytes: Self.maximumBytes)
        }
        try data.write(to: fileURL, options: .atomic)
    }

    public func load() throws -> [ProjectRef] {
        guard let data = try BoundedFileDataReader.readIfPresent(
            from: fileURL,
            maximumBytes: Self.maximumBytes
        ) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let projects = try decoder.decode([ProjectRef].self, from: data)
        return projects.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }
}
