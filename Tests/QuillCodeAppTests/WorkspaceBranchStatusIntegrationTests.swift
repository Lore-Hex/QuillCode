import XCTest
@testable import QuillCodeApp
import QuillCodeCore

@MainActor
final class WorkspaceBranchStatusIntegrationTests: XCTestCase {
    private func gitStatusCall() -> ToolCall {
        ToolCall(name: ToolDefinition.gitStatus.name, argumentsJSON: ToolArguments.json([:]))
    }

    func testGitStatusRunPopulatesBranchStatusChip() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Demo")

        // No branch chip until a git status runs.
        XCTAssertNil(model.surface().topBar.branchStatusLabel)

        let result = model.runToolCall(gitStatusCall(), workspaceRoot: root)
        XCTAssertTrue(result.ok, result.error ?? "")

        let label = model.surface().topBar.branchStatusLabel
        XCTAssertNotNil(label)
        XCTAssertFalse(label?.isEmpty ?? true)
    }

    func testNonGitStatusRunLeavesBranchStatusUntouched() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Demo")

        _ = model.runToolCall(gitStatusCall(), workspaceRoot: root)
        let seeded = model.surface().topBar.branchStatusLabel
        XCTAssertNotNil(seeded)

        _ = model.runToolCall(
            ToolCall(name: ToolDefinition.fileList.name, argumentsJSON: ToolArguments.json([:])),
            workspaceRoot: root
        )
        XCTAssertEqual(model.surface().topBar.branchStatusLabel, seeded)
    }

    func testViewingAnotherProjectsThreadHidesBranchStatus() throws {
        let rootA = try makeTempGitRepoWithInitialCommit()
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: rootA, name: "A")
        _ = model.newChat()
        _ = model.runToolCall(gitStatusCall(), workspaceRoot: rootA)
        XCTAssertNotNil(model.surface().topBar.branchStatusLabel)

        // Viewing a thread in a different project must not bleed A's branch chip.
        let rootB = try makeQuillCodeTestDirectory()
        _ = model.addProject(path: rootB, name: "B")
        _ = model.newChat()
        XCTAssertNil(model.surface().topBar.branchStatusLabel)
    }
}
