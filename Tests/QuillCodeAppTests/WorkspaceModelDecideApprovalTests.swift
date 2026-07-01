import XCTest
@testable import QuillCodeApp

final class WorkspaceModelDecideApprovalTests: XCTestCase {
    @MainActor
    func testDecideUnknownApprovalIsGraceful() async throws {
        // The notification's Approve action can arrive after the gate is gone (the user already acted
        // in-app, or the thread moved on). Deciding a stale/unknown request must fail cleanly, not crash.
        let root = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Demo")
        _ = model.newChat()

        let didAct = await model.decidePendingApproval(
            requestID: "does-not-exist",
            approve: true,
            workspaceRoot: root
        )
        XCTAssertFalse(didAct)
    }
}
