import XCTest
@testable import QuillCodeApp
import QuillCodeTools

final class FileMentionCatalogTests: XCTestCase {
    private func index(_ paths: [String]) -> WorkspaceFileIndex {
        let entries = paths.map { path -> WorkspaceFileIndexEntry in
            let name = path.split(separator: "/").last.map(String.init) ?? path
            let directory = path.contains("/") ? String(path[path.startIndex..<path.lastIndex(of: "/")!]) : ""
            return WorkspaceFileIndexEntry(path: path, name: name, directory: directory)
        }
        return WorkspaceFileIndex(entries: entries, truncated: false)
    }

    private func dirIndex(_ entries: [(String, WorkspaceFileIndexEntry.EntryKind)]) -> WorkspaceFileIndex {
        let mapped = entries.map { path, kind -> WorkspaceFileIndexEntry in
            let name = path.split(separator: "/").last.map(String.init) ?? path
            let directory = path.contains("/") ? String(path[path.startIndex..<path.lastIndex(of: "/")!]) : ""
            return WorkspaceFileIndexEntry(path: path, name: name, directory: directory, kind: kind)
        }
        return WorkspaceFileIndex(entries: mapped)
    }

    func testDirectoryMentionInsertsATrailingSlash() {
        let suggestions = FileMentionCatalog.suggestions(
            for: "open @Sour",
            in: dirIndex([("Sources", .directory), ("Sources/App.swift", .file)]),
            limit: 6
        )
        let sources = suggestions.first { $0.path == "Sources" }
        XCTAssertEqual(sources?.kind, .directory)
        XCTAssertEqual(sources?.insertText, "open @Sources/ ")
    }

    func testDirectoryFloatsAboveItsChildrenOnAPrefixQuery() {
        let suggestions = FileMentionCatalog.suggestions(
            for: "open @Sources",
            in: dirIndex([("Sources/App.swift", .file), ("Sources", .directory)]),
            limit: 6
        )
        // The folder name matches the query exactly (a higher score than its children, whose
        // names don't match and only hit on the path prefix), so the folder leads.
        XCTAssertEqual(suggestions.first?.path, "Sources")
        XCTAssertEqual(suggestions.first?.kind, .directory)
    }

    func testEqualScoreMentionsBreakTiesByShorterPath() {
        // Both files match `app` only via a name prefix (equal text score), so the
        // path-length tiebreak alone decides — the shallower file must lead.
        let suggestions = FileMentionCatalog.suggestions(
            for: "open @app",
            in: index(["Sources/App.swift", "Sources/Deep/Nested/App.swift"]),
            limit: 6
        )
        XCTAssertEqual(suggestions.map(\.path), ["Sources/App.swift", "Sources/Deep/Nested/App.swift"])
    }

    func testDirectoriesAreNeverFlaggedChanged() {
        let suggestions = FileMentionCatalog.suggestions(
            for: "open @Sources",
            in: dirIndex([("Sources", .directory), ("Sources/App.swift", .file)]),
            changedPaths: ["Sources/App.swift"],
            limit: 6
        )
        XCTAssertEqual(suggestions.first(where: { $0.path == "Sources" })?.isChanged, false)
        XCTAssertEqual(suggestions.first(where: { $0.path == "Sources/App.swift" })?.isChanged, true)
    }

    func testActiveMentionDetectsTrailingToken() {
        let mention = FileMentionCatalog.activeMention(in: "look at @App")
        XCTAssertEqual(mention?.prefix, "look at ")
        XCTAssertEqual(mention?.query, "App")
    }

    func testActiveMentionAtDraftStart() {
        let mention = FileMentionCatalog.activeMention(in: "@read")
        XCTAssertEqual(mention?.prefix, "")
        XCTAssertEqual(mention?.query, "read")
    }

    func testBareAtSignIsAnEmptyMention() {
        let mention = FileMentionCatalog.activeMention(in: "explain @")
        XCTAssertEqual(mention?.prefix, "explain ")
        XCTAssertEqual(mention?.query, "")
    }

    func testEmailAddressIsNotAMention() {
        XCTAssertNil(FileMentionCatalog.activeMention(in: "ping name@example.com"))
    }

    func testCompletedMentionFollowedBySpaceIsNotActive() {
        XCTAssertNil(FileMentionCatalog.activeMention(in: "compare @App.swift and"))
    }

    func testNoMentionWithoutAtSign() {
        XCTAssertNil(FileMentionCatalog.activeMention(in: "just some text"))
    }

    func testSuggestionsRankNamePrefixAbovePathContains() {
        let suggestions = FileMentionCatalog.suggestions(
            for: "open @app",
            in: index(["Sources/App.swift", "Tests/AppSupport/Helper.swift", "docs/app-notes.md"]),
            limit: 6
        )
        XCTAssertEqual(suggestions.first?.path, "Sources/App.swift")
        XCTAssertTrue(suggestions.contains { $0.path == "docs/app-notes.md" })
    }

    func testSuggestionAcceptanceReplacesActiveTokenAndAddsTrailingSpace() {
        let suggestions = FileMentionCatalog.suggestions(
            for: "please read @App",
            in: index(["Sources/App.swift"]),
            limit: 6
        )
        XCTAssertEqual(suggestions.first?.insertText, "please read @Sources/App.swift ")
    }

    func testEmptyMentionSurfacesShallowFilesFirst() {
        let suggestions = FileMentionCatalog.suggestions(
            for: "@",
            in: index(["a/b/c/Deep.swift", "Top.swift", "a/Mid.swift"]),
            limit: 6
        )
        XCTAssertEqual(suggestions.first?.path, "Top.swift")
    }

    func testNoSuggestionsWithoutActiveMention() {
        let suggestions = FileMentionCatalog.suggestions(
            for: "no mention here",
            in: index(["Sources/App.swift"]),
            limit: 6
        )
        XCTAssertTrue(suggestions.isEmpty)
    }

    func testSuggestionsHonorLimit() {
        let suggestions = FileMentionCatalog.suggestions(
            for: "@swift",
            in: index((0..<10).map { "File\($0).swift" }),
            limit: 3
        )
        XCTAssertEqual(suggestions.count, 3)
    }

    func testFuzzySubsequenceMatchesScatteredCharacters() {
        let suggestions = FileMentionCatalog.suggestions(
            for: "@wks",
            in: index(["Sources/WorkspaceState.swift", "Sources/Other.swift"]),
            limit: 6
        )
        XCTAssertEqual(suggestions.map(\.path), ["Sources/WorkspaceState.swift"])
    }

    func testSuggestionSurfaceRoundTripsIsChanged() throws {
        let surface = FileMentionSuggestionSurface(
            path: "Sources/B.swift", name: "B.swift", directory: "Sources",
            insertText: "@Sources/B.swift ", isChanged: true
        )
        let decoded = try JSONDecoder().decode(
            FileMentionSuggestionSurface.self,
            from: JSONEncoder().encode(surface)
        )
        XCTAssertEqual(decoded, surface)
        XCTAssertTrue(decoded.isChanged)
    }

    func testSubsequenceHelper() {
        XCTAssertTrue(FileMentionCatalog.isSubsequence("abc", of: "aXbYcZ"))
        XCTAssertFalse(FileMentionCatalog.isSubsequence("acb", of: "abc"))
        XCTAssertTrue(FileMentionCatalog.isSubsequence("", of: "anything"))
    }

    func testChangedFileBoostOutranksHigherTextMatch() {
        // "App.swift" is a name-prefix match (score 170); "Map.swift" only matches as a
        // name-contains (score 120) — but the changed boost floats Map.swift to the top.
        let suggestions = FileMentionCatalog.suggestions(
            for: "open @ap",
            in: index(["Sources/App.swift", "Sources/Map.swift"]),
            changedPaths: ["Sources/Map.swift"],
            limit: 6
        )
        XCTAssertEqual(suggestions.first?.path, "Sources/Map.swift")
        XCTAssertTrue(suggestions.first?.isChanged ?? false)
        XCTAssertEqual(suggestions.first { $0.path == "Sources/App.swift" }?.isChanged, false)
    }

    func testChangedFilesPreserveTextOrderingWithinTheGroup() {
        // Two changed files: both get the boost, so the stronger text match still wins.
        let suggestions = FileMentionCatalog.suggestions(
            for: "open @app",
            in: index(["Sources/App.swift", "Sources/AppHelper.swift"]),
            changedPaths: ["Sources/App.swift", "Sources/AppHelper.swift"],
            limit: 6
        )
        XCTAssertEqual(suggestions.map(\.path), ["Sources/App.swift", "Sources/AppHelper.swift"])
        XCTAssertTrue(suggestions.allSatisfy(\.isChanged))
    }

    func testEmptyChangedPathsIsByteIdenticalToToday() {
        let paths = ["Sources/App.swift", "Tests/AppSupport/Helper.swift", "docs/app-notes.md"]
        let withDefault = FileMentionCatalog.suggestions(for: "open @app", in: index(paths), limit: 6)
        let withEmpty = FileMentionCatalog.suggestions(for: "open @app", in: index(paths), changedPaths: [], limit: 6)
        // Same ordering, same insertText, and never flagged when no git status has run.
        XCTAssertEqual(withDefault.map(\.path), withEmpty.map(\.path))
        XCTAssertEqual(withDefault.map(\.insertText), withEmpty.map(\.insertText))
        XCTAssertTrue(withEmpty.allSatisfy { !$0.isChanged })
    }
}
