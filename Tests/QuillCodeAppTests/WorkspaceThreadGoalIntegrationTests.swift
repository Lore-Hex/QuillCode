import XCTest
import QuillCodeCore
import QuillCodePersistence
@testable import QuillCodeApp

@MainActor
final class WorkspaceThreadGoalIntegrationTests: XCTestCase {
    func testSlashGoalLifecyclePersistsAndProjectsIntoTopBar() async throws {
        let workspace = try makeQuillCodeTestDirectory()
        let store = JSONThreadStore(directory: workspace.appendingPathComponent("threads"))
        let model = QuillCodeWorkspaceModel(threadStore: store)

        model.setDraft("/goal Ship a green release")
        await model.submitComposer(workspaceRoot: workspace)

        let threadID = try XCTUnwrap(model.selectedThread?.id)
        XCTAssertEqual(model.selectedThread?.goal?.objective, "Ship a green release")
        XCTAssertEqual(model.selectedThread?.goal?.status, .active)
        XCTAssertEqual(model.surface().topBar.goal?.label, "Goal")
        XCTAssertTrue(model.surface().topBar.goal?.detail.contains("Ship a green release") == true)
        let persistedGoal = try XCTUnwrap(store.load(threadID).goal)
        XCTAssertEqual(persistedGoal.objective, model.selectedThread?.goal?.objective)
        XCTAssertEqual(persistedGoal.status, model.selectedThread?.goal?.status)

        model.setDraft("/goal block Waiting for CI")
        await model.submitComposer(workspaceRoot: workspace)
        XCTAssertEqual(model.selectedThread?.goal?.status, .blocked)
        XCTAssertEqual(model.selectedThread?.goal?.blocker, "Waiting for CI")
        XCTAssertEqual(model.surface().topBar.goal?.tone, .blocked)

        model.setDraft("/goal resume")
        await model.submitComposer(workspaceRoot: workspace)
        XCTAssertEqual(model.selectedThread?.goal?.status, .active)
        XCTAssertNil(model.selectedThread?.goal?.blocker)

        model.setDraft("/goal complete")
        await model.submitComposer(workspaceRoot: workspace)
        XCTAssertEqual(model.selectedThread?.goal?.status, .completed)
        XCTAssertEqual(model.surface().topBar.goal?.label, "Goal complete")

        model.setDraft("/goal clear")
        await model.submitComposer(workspaceRoot: workspace)
        XCTAssertNil(model.selectedThread?.goal)
        XCTAssertNil(model.surface().topBar.goal)
        XCTAssertNil(try store.load(threadID).goal)
    }
}
