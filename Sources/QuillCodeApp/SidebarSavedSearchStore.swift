import Foundation

public struct JSONSidebarSavedSearchStore: Sendable {
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
        try data.write(to: fileURL, options: .atomic)
    }

    public func load() throws -> [SidebarSavedSearch] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let decoded = try JSONDecoder().decode(
            [SidebarSavedSearch].self,
            from: Data(contentsOf: fileURL)
        )
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
