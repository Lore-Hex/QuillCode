import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

final class WorkspaceReviewActionToolCallPlannerTests: XCTestCase {
    func testRunPlanExecutesReviewActionThenRefreshesDiff() throws {
        let plan = WorkspaceReviewActionToolCallPlanner.runPlan(
            for: WorkspaceReviewActionSurface(kind: .stage, path: "Sources/App.swift")
        )
        let actionArguments = try ToolArguments(plan.actionCall.argumentsJSON)

        XCTAssertEqual(plan.actionCall.name, ToolDefinition.gitStage.name)
        XCTAssertEqual(try actionArguments.requiredString("path"), "Sources/App.swift")
        XCTAssertEqual(plan.diffRefreshCall.name, ToolDefinition.gitDiff.name)
        XCTAssertEqual(plan.diffRefreshCall.argumentsJSON, "{}")
    }

    func testRunPlanFinalStatusRequiresActionAndDiffRefreshSuccess() {
        let plan = WorkspaceReviewActionToolCallPlanner.runPlan(
            for: WorkspaceReviewActionSurface(kind: .restore, path: "Sources/App.swift")
        )

        XCTAssertEqual(
            plan.finalStatus(actionResult: ToolResult(ok: true), diffRefreshResult: ToolResult(ok: true)),
            TopBarAgentStatusLabel.idle
        )
        XCTAssertEqual(
            plan.finalStatus(actionResult: ToolResult(ok: false), diffRefreshResult: ToolResult(ok: true)),
            TopBarAgentStatusLabel.failed
        )
        XCTAssertEqual(
            plan.finalStatus(actionResult: ToolResult(ok: true), diffRefreshResult: ToolResult(ok: false)),
            TopBarAgentStatusLabel.failed
        )
    }

    func testStageFileBuildsGitStageCall() throws {
        let call = WorkspaceReviewActionToolCallPlanner.toolCall(
            for: WorkspaceReviewActionSurface(kind: .stage, path: "Sources/App.swift")
        )
        let arguments = try ToolArguments(call.argumentsJSON)

        XCTAssertEqual(call.name, ToolDefinition.gitStage.name)
        XCTAssertEqual(try arguments.requiredString("path"), "Sources/App.swift")
        XCTAssertNil(arguments.string("patch"))
    }

    func testRestoreFileBuildsGitRestoreCall() throws {
        let call = WorkspaceReviewActionToolCallPlanner.toolCall(
            for: WorkspaceReviewActionSurface(kind: .restore, path: "Sources/App.swift")
        )
        let arguments = try ToolArguments(call.argumentsJSON)

        XCTAssertEqual(call.name, ToolDefinition.gitRestore.name)
        XCTAssertEqual(try arguments.requiredString("path"), "Sources/App.swift")
        XCTAssertNil(arguments.string("patch"))
    }

    func testStageHunkBuildsGitStageHunkCall() throws {
        let patch = "@@ -1 +1 @@\n-old\n+new\n"
        let call = WorkspaceReviewActionToolCallPlanner.toolCall(
            for: WorkspaceReviewActionSurface(
                kind: .stageHunk,
                path: "Sources/App.swift",
                patch: patch,
                targetID: "hunk-1"
            )
        )
        let arguments = try ToolArguments(call.argumentsJSON)

        XCTAssertEqual(call.name, ToolDefinition.gitStageHunk.name)
        XCTAssertEqual(try arguments.requiredString("path"), "Sources/App.swift")
        XCTAssertEqual(try arguments.requiredString("patch"), patch)
    }

    func testRestoreHunkBuildsGitRestoreHunkCall() throws {
        let patch = "@@ -1 +1 @@\n-old\n+new\n"
        let call = WorkspaceReviewActionToolCallPlanner.toolCall(
            for: WorkspaceReviewActionSurface(
                kind: .restoreHunk,
                path: "Sources/App.swift",
                patch: patch,
                targetID: "hunk-1"
            )
        )
        let arguments = try ToolArguments(call.argumentsJSON)

        XCTAssertEqual(call.name, ToolDefinition.gitRestoreHunk.name)
        XCTAssertEqual(try arguments.requiredString("path"), "Sources/App.swift")
        XCTAssertEqual(try arguments.requiredString("patch"), patch)
    }

    func testHunkActionWithoutPatchPreservesExecutorLevelValidation() throws {
        let call = WorkspaceReviewActionToolCallPlanner.toolCall(
            for: WorkspaceReviewActionSurface(
                kind: .stageHunk,
                path: "Sources/App.swift",
                patch: nil,
                targetID: "hunk-1"
            )
        )
        let arguments = try ToolArguments(call.argumentsJSON)

        XCTAssertEqual(call.name, ToolDefinition.gitStageHunk.name)
        XCTAssertEqual(try arguments.requiredString("path"), "Sources/App.swift")
        XCTAssertEqual(arguments.string("patch"), "")
    }
}
