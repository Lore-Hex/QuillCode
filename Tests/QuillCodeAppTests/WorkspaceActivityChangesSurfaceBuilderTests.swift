import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceActivityChangesSurfaceBuilderTests: XCTestCase {
    private func file(_ path: String, _ insertions: Int, _ deletions: Int, hunks: Int = 1, binary: Bool = false) -> WorkspaceReviewFileSurface {
        WorkspaceReviewFileSurface(path: path, insertions: insertions, deletions: deletions, hunks: hunks, isBinary: binary)
    }

    func testOrdersByChurnDescendingThenPath() {
        let items = WorkspaceActivityChangesSurfaceBuilder.items(from: [
            file("small.swift", 1, 1),        // churn 2
            file("big.swift", 40, 10),        // churn 50
            file("mid-b.swift", 5, 5),        // churn 10
            file("mid-a.swift", 6, 4)         // churn 10 -> tie, path breaks it (mid-a before mid-b)
        ])
        XCTAssertEqual(items.map(\.title), ["big.swift", "mid-a.swift", "mid-b.swift", "small.swift"])
    }

    func testDetailCarriesTheChangeLabel() {
        let items = WorkspaceActivityChangesSurfaceBuilder.items(from: [file("a.swift", 12, 3, hunks: 2)])
        XCTAssertEqual(items.first?.detail, "+12 · -3 · 2 hunks")
        XCTAssertEqual(items.first?.kind, "change")
        XCTAssertEqual(items.first?.id, "change:a.swift")
        XCTAssertEqual(items.first?.statusLabel, "")
    }

    func testBinaryFileIsFlagged() {
        let items = WorkspaceActivityChangesSurfaceBuilder.items(from: [file("logo.png", 0, 0, hunks: 0, binary: true)])
        XCTAssertEqual(items.first?.statusLabel, "binary")
    }

    func testBoundsToLimitButOrderingRunsFirst() {
        // 20 files, only the top-`limit` by churn survive — the biggest edits, not the first-listed.
        let files = (0..<20).map { file("f\($0).swift", $0, 0) }
        let items = WorkspaceActivityChangesSurfaceBuilder.items(from: files, limit: 3)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.map(\.title), ["f19.swift", "f18.swift", "f17.swift"])
    }

    func testEmptyInputIsEmpty() {
        XCTAssertTrue(WorkspaceActivityChangesSurfaceBuilder.items(from: []).isEmpty)
    }

    // The `.changes` section is only present when there ARE changes (it is not alwaysVisible).
    func testSurfaceGainsChangesSectionWhenFilesChanged() {
        let surface = WorkspaceActivitySurface(
            isVisible: true,
            thread: ChatThread(title: "Task", messages: [], events: []),
            toolCards: [],
            instructions: [],
            memories: [],
            agentStatus: "Idle",
            changeFiles: [file("Sources/A.swift", 9, 2)]
        )
        let changes = surface.sections.first { $0.kind == .changes }
        XCTAssertNotNil(changes)
        XCTAssertEqual(changes?.items.map(\.title), ["Sources/A.swift"])
        XCTAssertEqual(changes?.countLabel, "1 file")
    }

    func testSurfaceOmitsChangesSectionWhenNothingChanged() {
        let surface = WorkspaceActivitySurface(
            isVisible: true,
            thread: ChatThread(title: "Task", messages: [], events: []),
            toolCards: [],
            instructions: [],
            memories: [],
            agentStatus: "Idle",
            changeFiles: []
        )
        XCTAssertNil(surface.sections.first { $0.kind == .changes })
    }
}
