import XCTest

final class ParityAppServerThreadItemsGateTests: QuillCodeParityTestCase {
    func testThreadItemsStayWiredThroughRuntimeTestsSmokeAndDocs() throws {
        let root = Self.packageRoot()
        let session = try text(root, "Sources/QuillCodeCLI/AppServerSession.swift")
        let items = try text(
            root,
            "Sources/QuillCodeCLI/AppServerSessionThreadItems.swift"
        )
        let pagination = try text(
            root,
            "Sources/QuillCodeCLI/AppServerThreadPagination.swift"
        )
        let tests = try text(root, "Tests/QuillCodeCLITests/AppServerThreadHistoryTests.swift")
        let smoke = try text(root, "scripts/app-server-smoke.sh")
        let parity = try Self.docsText(named: "CODEX_PARITY_MATRIX.md")
        let research = try Self.docsText(named: "CODEX_RESEARCH.md")
        let decisions = try Self.docsText(named: "DECISIONS.md")

        Self.assertSource(session, contains: "case \"thread/items/list\"")
        Self.assertSource(items, containsAll: [
            "listThreadItems",
            "projectedThreadHistoryTurns",
            "cursorIdentifier",
            "turnId"
        ])
        Self.assertSource(pagination, contains: "filteredAnchoredPage")
        Self.assertSource(
            tests,
            contains: "testThreadItemsListPagesFullItemsAcrossTurnFiltersAndDirections"
        )
        Self.assertSource(smoke, contains: "filtered_item_page")
        Self.assertSource(parity, contains: "App-server persisted item pagination")
        Self.assertSource(research, contains: "thread/items/list")
        Self.assertSource(decisions, contains: "Item cursors are anchored")
    }

    private func text(_ root: URL, _ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
