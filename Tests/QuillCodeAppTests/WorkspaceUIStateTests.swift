import XCTest
@testable import QuillCodeApp

final class WorkspaceUIStateTests: XCTestCase {
    func testComposerDefaultsMatchPrimaryChatEntryPoint() {
        let state = ComposerState()

        XCTAssertEqual(state.draft, "")
        XCTAssertFalse(state.isSending)
        XCTAssertEqual(state.placeholder, "Message QuillCode")
    }

    func testVisibilityStatesDefaultClosedAndPreserveCollapsedActivitySections() {
        XCTAssertFalse(MemoriesState().isVisible)

        let activity = ActivityState(
            isVisible: true,
            collapsedSectionIDs: [.tools, .sources],
            dismissedInstructionDiagnosticIDs: ["instruction-conflict"]
        )

        XCTAssertTrue(activity.isVisible)
        XCTAssertEqual(activity.collapsedSectionIDs, [.tools, .sources])
        XCTAssertEqual(activity.dismissedInstructionDiagnosticIDs, ["instruction-conflict"])
    }
}
