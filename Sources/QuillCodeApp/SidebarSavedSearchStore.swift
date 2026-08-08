import Foundation
import QuillCodePersistence

public struct JSONSidebarSavedSearchStore: Sendable {
    public static let maximumBytes = 4 * 1_024 * 1_024

    public var fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func save(_ savedSearches: [SidebarSavedSearch]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Self.normalized(savedSearches))
        guard data.count <= Self.maximumBytes else {
            throw BoundedFileDataError.exceedsSizeLimit(maximumBytes: Self.maximumBytes)
        }
        try data.write(to: fileURL, options: .atomic)
    }

    public func load() throws -> [SidebarSavedSearch] {
        guard let data = try BoundedFileDataReader.readIfPresent(
            from: fileURL,
            maximumBytes: Self.maximumBytes
        ) else { return [] }
        let decoded = try JSONDecoder().decode([SidebarSavedSearch].self, from: data)
        return Self.normalized(decoded)
    }

    static func normalized(_ savedSearches: [SidebarSavedSearch]) -> [SidebarSavedSearch] {
        var seenIDs = Set<UUID>()
        return savedSearches.compactMap { savedSearch in
            let normalized = SidebarSavedSearch(
                id: savedSearch.id,
                title: savedSearch.title,
                query: savedSearch.query
            )
            guard normalized.isValid, seenIDs.insert(normalized.id).inserted else {
                return nil
            }
            return normalized
        }
    }
}
