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

    func testSubsequenceHelper() {
        XCTAssertTrue(FileMentionCatalog.isSubsequence("abc", of: "aXbYcZ"))
        XCTAssertFalse(FileMentionCatalog.isSubsequence("acb", of: "abc"))
        XCTAssertTrue(FileMentionCatalog.isSubsequence("", of: "anything"))
    }
}
