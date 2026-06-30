import XCTest
@testable import QuillCodeApp

@MainActor
final class WorkspaceComposerHistoryIntegrationTests: XCTestCase {
    func testSurfaceExposesSentMessageHistoryOldestFirst() async throws {
        let root = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Demo")

        XCTAssertTrue(model.surface().composer.sentMessageHistory.isEmpty)

        model.setDraft("run whoami")
        await model.submitComposer(workspaceRoot: root)
        model.setDraft("list the files here")
        await model.submitComposer(workspaceRoot: root)

        let history = model.surface().composer.sentMessageHistory
        XCTAssertEqual(history, ["run whoami", "list the files here"])
    }
}
