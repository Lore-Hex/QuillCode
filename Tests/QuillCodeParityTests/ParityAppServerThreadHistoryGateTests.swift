import XCTest

final class ParityAppServerThreadHistoryGateTests: QuillCodeParityTestCase {
    func testThreadHistoryDiscoveryStaysWiredThroughRuntimeTestsSmokeAndDocs() throws {
        let root = Self.packageRoot()
        let session = try text(root, "Sources/QuillCodeCLI/AppServerSession.swift")
        let queries = try text(root, "Sources/QuillCodeCLI/AppServerSessionThreadQueries.swift")
        let searchRequest = try text(
            root,
            "Sources/QuillCodeCLI/AppServerThreadSearchRequest.swift"
        )
        let history = try text(root, "Sources/QuillCodeCLI/AppServerSessionThreadHistory.swift")
        let projection = try text(
            root,
            "Sources/QuillCodeCLI/AppServerThreadHistoryProjection.swift"
        )
        let pagination = try text(root, "Sources/QuillCodeCLI/AppServerThreadPagination.swift")
        let tests = try text(
            root,
            "Tests/QuillCodeCLITests/AppServerThreadHistoryTests.swift"
        )
        let smoke = try text(root, "scripts/app-server-smoke.sh")
        let parity = try Self.docsText(named: "CODEX_PARITY_MATRIX.md")
        let decisions = try Self.docsText(named: "DECISIONS.md")
        let research = try Self.docsText(named: "CODEX_RESEARCH.md")

        Self.assertSource(session, containsAll: [
            "case \"thread/search\"",
            "case \"thread/loaded/list\"",
            "case \"thread/turns/list\"",
            "case \"thread/turns/items/list\""
        ])
        Self.assertSource(queries, containsAll: [
            "func searchThreads",
            "func listLoadedThreads",
            "thread/search requires a non-empty searchTerm",
            "AppServerThreadSearchSnippet"
        ])
        Self.assertSource(searchRequest, containsAll: [
            "struct AppServerThreadSearchRequest",
            "Invalid request: unknown variant",
            "AppServerThreadSourceKind.expectedValues"
        ])
        Self.assertSource(history, containsAll: [
            "func listThreadTurns",
            "case notLoaded",
            "case summary",
            "case full",
            "activeProjectedTurn"
        ])
        Self.assertSource(projection, containsAll: [
            "turnEventSlices",
            "messageEventIndices",
            "AppServerProgressProjector"
        ])
        Self.assertSource(pagination, containsAll: [
            "defaultLimit = 25",
            "maximumLimit = 100",
            "includeAnchor",
            "backwardsCursor"
        ])
        Self.assertSource(tests, containsAll: [
            "testThreadSearchUsesTranscriptContentAndHonorsArchiveAndSourceFilters",
            "testLoadedThreadsAreConnectionScopedAndCursorPaged",
            "testTurnHistorySupportsViewsStableCursorsAndValidation",
            "testPersistedTurnHistoryReconstructsShellOutputAfterReconnect",
            "testPersistedHistoryKeepsRepeatedMessagesInTheirOriginalTurns",
            "testActiveTurnHistoryUsesTheLiveInProgressProjection"
        ])
        Self.assertSource(smoke, containsAll: [
            "thread/loaded/list",
            "thread/search",
            "thread/turns/list",
            "thread/turns/items/list is not supported yet"
        ])
        Self.assertSource(parity, containsAll: [
            "thread/search",
            "thread/loaded/list",
            "thread/turns/list"
        ])
        Self.assertSource(decisions, contains: "Thread discovery and history use durable content and stable anchors")
        Self.assertSource(research, contains: "thread/turns/items/list")
    }

    private func text(_ root: URL, _ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
