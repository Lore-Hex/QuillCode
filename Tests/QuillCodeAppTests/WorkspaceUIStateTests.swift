import XCTest
@testable import QuillCodeApp

final class WorkspaceUIStateTests: XCTestCase {
    func testComposerDefaultsMatchPrimaryChatEntryPoint() {
        let state = ComposerState()

        XCTAssertEqual(state.draft, "")
        XCTAssertFalse(state.isSending)
        XCTAssertEqual(state.placeholder, "Message QuillCode")
    }

    @MainActor
    func testWorkspaceChromeDefaultsToVisibleSidebarAndTogglesThroughModel() {
        let model = QuillCodeWorkspaceModel()

        XCTAssertTrue(model.chrome.isSidebarVisible)
        XCTAssertTrue(model.surface().chrome.isSidebarVisible)

        model.toggleSidebar()

        XCTAssertFalse(model.chrome.isSidebarVisible)
        XCTAssertFalse(model.surface().chrome.isSidebarVisible)
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
