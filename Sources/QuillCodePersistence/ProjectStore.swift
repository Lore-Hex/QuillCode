import Foundation
import QuillCodeCore

public struct JSONProjectStore: Sendable {
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
        try encoder.encode(projects)
            .write(to: fileURL, options: .atomic)
    }

    public func load() throws -> [ProjectRef] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let projects = try decoder.decode([ProjectRef].self, from: Data(contentsOf: fileURL))
        return projects.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }
}
