import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceMemoryContextUpdatePlannerTests: XCTestCase {
    func testGlobalMemoryChangedBuildsThreadNoticeAndRefreshedMemories() {
        let memories = [
            MemoryNote(
                id: "global-preferences",
                scope: .global,
                title: "Preferences",
                content: "Prefer concise answers.",
                relativePath: "memories/preferences.md",
                byteCount: 23
            )
        ]

        let update = WorkspaceMemoryContextUpdatePlanner.globalMemoryChanged(
            memories: memories,
            summary: "Saved memory: Preferences",
            relativePath: "memories/preferences.md"
        )

        XCTAssertEqual(update.memories, memories)
        XCTAssertEqual(update.event.kind, ThreadEventKind.notice)
        XCTAssertEqual(update.event.summary, "Saved memory: Preferences")
        XCTAssertEqual(update.event.payloadJSON, "memories/preferences.md")
    }
}
