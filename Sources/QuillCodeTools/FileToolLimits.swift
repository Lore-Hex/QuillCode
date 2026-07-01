enum FileToolLimits {
    static let defaultSearchMaxResults = 20
    static let absoluteSearchMaxResults = 100
    static let defaultListMaxEntries = 200
    static let absoluteListMaxEntries = 500
    static let maxSearchFileBytes = 1_000_000
    static let maxSearchScannedFiles = 2_000
    static let maxSearchPreviewCharacters = 240
    static let excludedWorkspaceDirectoryNames: Set<String> = [
        ".build",
        ".git",
        ".swiftpm",
        "DerivedData",
        "build",
        "node_modules"
    ]

    static func boundedSearchResultLimit(_ value: Int?) -> Int {
        min(max(value ?? defaultSearchMaxResults, 1), absoluteSearchMaxResults)
    }

    static func boundedListEntryLimit(_ value: Int?) -> Int {
        min(max(value ?? defaultListMaxEntries, 1), absoluteListMaxEntries)
    }

    static func boundedSearchPreview(_ line: String) -> String {
        let collapsed = line
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard collapsed.count > maxSearchPreviewCharacters else {
            return collapsed
        }
        return "\(collapsed.prefix(maxSearchPreviewCharacters))..."
    }
}
