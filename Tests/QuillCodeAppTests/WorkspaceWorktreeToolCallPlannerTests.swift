import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

final class WorkspaceWorktreeToolCallPlannerTests: XCTestCase {
    func testCreateBuildsGitWorktreeCreateCallWithTrimmedOptionalArguments() throws {
        let call = WorkspaceWorktreeToolCallPlanner.create(.init(
            path: "../feature-worktree",
            branch: " feature/login ",
            base: " origin/main\n"
        ))
        let arguments = try ToolArguments(call.argumentsJSON)

        XCTAssertEqual(call.name, ToolDefinition.gitWorktreeCreate.name)
        XCTAssertEqual(try arguments.requiredString("path"), "../feature-worktree")
        XCTAssertEqual(try arguments.requiredString("branch"), "feature/login")
        XCTAssertEqual(try arguments.requiredString("base"), "origin/main")
    }

    func testManagedCreateIncludesExplicitManagedFlagWithoutBranch() throws {
        let call = WorkspaceWorktreeToolCallPlanner.create(.init(
            path: "/tmp/repo-task",
            base: "main",
            managed: true
        ))
        let arguments = try ToolArguments(call.argumentsJSON)

        XCTAssertEqual(call.name, ToolDefinition.gitWorktreeCreate.name)
        XCTAssertEqual(arguments.bool("managed"), true)
        XCTAssertEqual(arguments.string("base"), "main")
        XCTAssertNil(arguments.string("branch"))
    }

    func testCreateOmitsBlankOptionalArguments() throws {
        let call = WorkspaceWorktreeToolCallPlanner.create(.init(
            path: "../feature-worktree",
            branch: " \n ",
            base: "\t"
        ))
        let arguments = try ToolArguments(call.argumentsJSON)

        XCTAssertEqual(call.name, ToolDefinition.gitWorktreeCreate.name)
        XCTAssertEqual(try arguments.requiredString("path"), "../feature-worktree")
        XCTAssertNil(arguments.string("branch"))
        XCTAssertNil(arguments.string("base"))
    }

    func testRemoveBuildsGitWorktreeRemoveCall() throws {
        let call = WorkspaceWorktreeToolCallPlanner.remove(.init(
            path: "../feature-worktree",
            force: true
        ))
        let arguments = try ToolArguments(call.argumentsJSON)

        XCTAssertEqual(call.name, ToolDefinition.gitWorktreeRemove.name)
        XCTAssertEqual(try arguments.requiredString("path"), "../feature-worktree")
        XCTAssertEqual(arguments.bool("force"), true)
    }

    func testOpenBuildsGitWorktreeOpenCallWithTrimmedPath() throws {
        let call = WorkspaceWorktreeToolCallPlanner.open(.init(
            path: " ../feature-worktree\n"
        ))
        let arguments = try ToolArguments(call.argumentsJSON)

        XCTAssertEqual(call.name, ToolDefinition.gitWorktreeOpen.name)
        XCTAssertEqual(try arguments.requiredString("path"), "../feature-worktree")
    }

    func testRemovePreservesNonForcefulDefault() throws {
        let call = WorkspaceWorktreeToolCallPlanner.remove(.init(
            path: "../feature-worktree"
        ))
        let arguments = try ToolArguments(call.argumentsJSON)

        XCTAssertEqual(call.name, ToolDefinition.gitWorktreeRemove.name)
        XCTAssertEqual(try arguments.requiredString("path"), "../feature-worktree")
        XCTAssertEqual(arguments.bool("force"), false)
    }

    func testPruneBuildsGitWorktreePruneCall() throws {
        let call = WorkspaceWorktreeToolCallPlanner.prune(.init(dryRun: true, verbose: true))
        let arguments = try ToolArguments(call.argumentsJSON)

        XCTAssertEqual(call.name, ToolDefinition.gitWorktreePrune.name)
        XCTAssertEqual(arguments.bool("dryRun"), true)
        XCTAssertEqual(arguments.bool("verbose"), true)
    }
}
