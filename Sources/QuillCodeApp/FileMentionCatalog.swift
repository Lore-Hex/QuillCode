import Foundation
import QuillCodeTools

/// A single ranked file suggestion for an in-progress composer `@` mention.
public struct FileMentionSuggestionSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String { path }
    /// Workspace-relative path, for example `Sources/App.swift`.
    public var path: String
    /// Last path component, for example `App.swift`.
    public var name: String
    /// Workspace-relative parent directory, or `""` for root files.
    public var directory: String
    /// The full composer draft after this suggestion is accepted, with the active
    /// `@query` token replaced by `@path` and a trailing space.
    public var insertText: String

    public init(path: String, name: String, directory: String, insertText: String) {
        self.path = path
        self.name = name
        self.directory = directory
        self.insertText = insertText
    }
}

/// Detects an in-progress `@` file mention in the composer draft and ranks bounded
/// workspace files against it, mirroring ``SlashCommandCatalog`` so the composer can
/// reuse the same suggestion panel for both surfaces.
public enum FileMentionCatalog {
    /// The active mention being typed at the end of the draft, if any.
    public struct ActiveMention: Equatable {
        /// Text before the mention's `@`, preserved verbatim on acceptance.
        public var prefix: String
        /// The mention query (the text after `@`, lowercased for matching is done elsewhere).
        public var query: String

        public init(prefix: String, query: String) {
            self.prefix = prefix
            self.query = query
        }
    }

    /// Returns the active `@` mention the user is composing at the end of the draft.
    ///
    /// A mention is the trailing whitespace-delimited token that starts with `@`. The
    /// `@` must begin a fresh token (start of draft or preceded by whitespace), so
    /// values like `name@example.com` are not treated as mentions.
    public static func activeMention(in draft: String) -> ActiveMention? {
        guard let atIndex = trailingMentionStart(in: draft) else { return nil }
        let prefix = String(draft[draft.startIndex..<atIndex])
        let query = String(draft[draft.index(after: atIndex)..<draft.endIndex])
        return ActiveMention(prefix: prefix, query: query)
    }

    /// Ranks workspace files against the active mention, returning bounded suggestions
    /// whose acceptance replaces the `@query` token with `@path `.
    public static func suggestions(
        for draft: String,
        in index: WorkspaceFileIndex,
        limit: Int = 6
    ) -> [FileMentionSuggestionSurface] {
        guard let mention = activeMention(in: draft) else { return [] }
        return suggestions(prefix: mention.prefix, query: mention.query, entries: index.entries, limit: limit)
    }

    static func suggestions(
        prefix: String,
        query: String,
        entries: [WorkspaceFileIndexEntry],
        limit: Int
    ) -> [FileMentionSuggestionSurface] {
        let normalizedQuery = query.lowercased()
        let scored = entries.enumerated().compactMap { offset, entry -> (Int, Int, WorkspaceFileIndexEntry)? in
            score(entry, query: normalizedQuery).map { ($0, offset, entry) }
        }
        return scored
            .sorted { lhs, rhs in
                if lhs.0 != rhs.0 { return lhs.0 > rhs.0 }
                if lhs.2.path.count != rhs.2.path.count { return lhs.2.path.count < rhs.2.path.count }
                return lhs.2.path < rhs.2.path
            }
            .prefix(limit)
            .map { _, _, entry in
                FileMentionSuggestionSurface(
                    path: entry.path,
                    name: entry.name,
                    directory: entry.directory,
                    insertText: "\(prefix)@\(entry.path) "
                )
            }
    }

    private static func trailingMentionStart(in draft: String) -> String.Index? {
        guard !draft.isEmpty else { return nil }
        var index = draft.endIndex
        while index > draft.startIndex {
            let previous = draft.index(before: index)
            let character = draft[previous]
            if character.isWhitespace { return nil }
            if character == "@" {
                // The `@` must begin a fresh token: at draft start or after whitespace.
                if previous == draft.startIndex { return previous }
                let beforeAt = draft[draft.index(before: previous)]
                return beforeAt.isWhitespace ? previous : nil
            }
            index = previous
        }
        return nil
    }

    private static func score(_ entry: WorkspaceFileIndexEntry, query: String) -> Int? {
        guard !query.isEmpty else {
            // Empty mention: surface shallow files first.
            let depth = entry.path.reduce(into: 0) { $0 += $1 == "/" ? 1 : 0 }
            return 100 - min(depth, 20)
        }
        let name = entry.name.lowercased()
        let path = entry.path.lowercased()
        if name == query { return 200 }
        if name.hasPrefix(query) { return 170 }
        if path.hasPrefix(query) { return 150 }
        if name.contains(query) { return 120 }
        if path.contains(query) { return 90 }
        if isSubsequence(query, of: name) { return 60 }
        if isSubsequence(query, of: path) { return 40 }
        return nil
    }

    /// Returns whether `needle` appears as an in-order (not necessarily contiguous)
    /// subsequence of `haystack`, enabling lightweight fuzzy matching.
    static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        guard !needle.isEmpty else { return true }
        var needleIndex = needle.startIndex
        for character in haystack {
            if character == needle[needleIndex] {
                needleIndex = needle.index(after: needleIndex)
                if needleIndex == needle.endIndex { return true }
            }
        }
        return false
    }
}
