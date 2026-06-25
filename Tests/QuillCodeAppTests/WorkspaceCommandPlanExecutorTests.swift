import Foundation
import XCTest
import QuillCodeCore
@testable import QuillCodeApp

@MainActor
final class WorkspaceCommandPlanExecutorTests: XCTestCase {
    func testExecutorRunsDraftPlanWithoutCommandIDParsing() throws {
        let model = QuillCodeWorkspaceModel()

        XCTAssertTrue(model.runWorkspaceCommandPlan(.setDraft("/remember "), workspaceRoot: try makeTempDirectory()))
        XCTAssertEqual(model.composer.draft, "/remember ")
    }

    func testExecutorRunsStaticActionPlan() throws {
        let model = QuillCodeWorkspaceModel()

        XCTAssertFalse(model.terminal.isVisible)
        XCTAssertTrue(model.runWorkspaceCommandPlan(.action(.toggleTerminal), workspaceRoot: try makeTempDirectory()))
        XCTAssertTrue(model.terminal.isVisible)
    }

    func testExecutorRunsNewChatCommandPlan() throws {
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [ChatThread(title: "Existing")],
            selectedThreadID: nil
        ))

        XCTAssertTrue(model.runWorkspaceCommand("new-chat", workspaceRoot: try makeTempDirectory()))

        XCTAssertEqual(model.root.threads.count, 2)
        XCTAssertEqual(model.selectedThread?.title, "New chat")
    }

}
