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

    func testExecutorRunsBrowserTabCommandPlans() throws {
        let model = QuillCodeWorkspaceModel()
        let root = try makeTempDirectory()
        let firstTabID = model.browser.selectedTabID

        XCTAssertTrue(model.runWorkspaceCommand("browser-tab-new", workspaceRoot: root))
        let secondTabID = model.browser.selectedTabID
        XCTAssertNotEqual(firstTabID, secondTabID)
        XCTAssertEqual(model.browser.tabs.count, 2)

        XCTAssertTrue(model.runWorkspaceCommand("browser-tab-select:\(firstTabID.uuidString)", workspaceRoot: root))
        XCTAssertEqual(model.browser.selectedTabID, firstTabID)
        XCTAssertTrue(model.runWorkspaceCommand("browser-tab-close:\(firstTabID.uuidString)", workspaceRoot: root))
        XCTAssertEqual(model.browser.selectedTabID, secondTabID)
        XCTAssertEqual(model.browser.tabs.count, 1)
    }

}
