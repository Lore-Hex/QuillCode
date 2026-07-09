import XCTest

final class ParityWorkspaceReviewSurfaceGateTests: QuillCodeParityTestCase {
    func testWorkspaceSurfaceDelegatesReviewSurfaceContracts() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let reviewText = try Self.appSourceText(named: "QuillCodeReviewSurface.swift")

        XCTAssertTrue(reviewText.contains("public struct WorkspaceReviewSurface"), "Review surface should live beside review pane contracts.")
        XCTAssertTrue(reviewText.contains("public struct WorkspaceReviewFileSurface"), "Review file rows should live beside review pane contracts.")
        XCTAssertTrue(reviewText.contains("public struct WorkspaceReviewHunkSurface"), "Review hunk rows should live beside review pane contracts.")
        XCTAssertTrue(reviewText.contains("public struct WorkspaceReviewLineSurface"), "Review line rows should live beside review pane contracts.")
        XCTAssertTrue(reviewText.contains("public struct WorkspaceReviewCommentSurface"), "Review comment rows should live beside review pane contracts.")
        XCTAssertTrue(reviewText.contains("public struct WorkspaceReviewActionSurface"), "Review actions should live beside review pane contracts.")
        XCTAssertTrue(reviewText.contains("public enum WorkspaceReviewLineKind"), "Review line kind presentation should live beside review pane contracts.")
        XCTAssertTrue(reviewText.contains("public enum WorkspaceReviewActionKind"), "Review action presentation should live beside review pane contracts.")
        XCTAssertTrue(reviewText.contains("public var unreadableReason"), "Review files should own unreadable-file presentation policy.")
        XCTAssertTrue(reviewText.contains("isDeleted"), "Review files should carry deleted-file state for action availability.")
        XCTAssertFalse(surfaceText.contains("public struct WorkspaceReviewSurface"), "WorkspaceSurface should not own review surface records.")
        XCTAssertFalse(surfaceText.contains("public struct WorkspaceReviewFileSurface"), "WorkspaceSurface should not own review file rows.")
        XCTAssertFalse(surfaceText.contains("public struct WorkspaceReviewHunkSurface"), "WorkspaceSurface should not own review hunk rows.")
        XCTAssertFalse(surfaceText.contains("public struct WorkspaceReviewLineSurface"), "WorkspaceSurface should not own review line rows.")
        XCTAssertFalse(surfaceText.contains("public struct WorkspaceReviewCommentSurface"), "WorkspaceSurface should not own review comment rows.")
        XCTAssertFalse(surfaceText.contains("public struct WorkspaceReviewActionSurface"), "WorkspaceSurface should not own review action rows.")
        XCTAssertFalse(surfaceText.contains("public enum WorkspaceReviewLineKind"), "WorkspaceSurface should not own review line kind presentation.")
        XCTAssertFalse(surfaceText.contains("public enum WorkspaceReviewActionKind"), "WorkspaceSurface should not own review action presentation.")
    }

    func testPullRequestReviewDraftContractsLiveInFocusedFile() throws {
        let reviewText = try Self.appSourceText(named: "QuillCodeReviewSurface.swift")
        let draftText = try Self.appSourceText(named: "WorkspacePullRequestReviewDraftSurface.swift")
        let runtimeText = try Self.appSourceText(named: "WorkspacePullRequestReviewDraft.swift")

        XCTAssertTrue(
            draftText.contains("public enum WorkspacePullRequestReviewActionKind"),
            "Pull request review action presentation should live beside the draft surface."
        )
        XCTAssertTrue(
            draftText.contains("public struct WorkspacePullRequestReviewDraftSurface"),
            "Pull request review draft state should live in the focused draft surface file."
        )
        XCTAssertTrue(
            draftText.contains("public struct WorkspacePullRequestReviewDraftSubmitSummarySurface"),
            "Pull request review submit summary should live in the focused draft surface file."
        )
        XCTAssertTrue(
            draftText.contains("public struct WorkspacePullRequestReviewDraftCommentSurface"),
            "Pull request inline draft comments should live in the focused draft surface file."
        )
        XCTAssertTrue(
            runtimeText.contains("WorkspacePullRequestReviewDraftToolCallPlanner"),
            "Pull request review runtime planning should remain in the runtime draft file."
        )
        XCTAssertFalse(
            reviewText.contains("public enum WorkspacePullRequestReviewActionKind"),
            "Broad review diff surface should not own pull request review draft action presentation."
        )
        XCTAssertFalse(
            reviewText.contains("public struct WorkspacePullRequestReviewDraftSurface"),
            "Broad review diff surface should not own pull request review draft state."
        )
        XCTAssertFalse(
            reviewText.contains("public struct WorkspacePullRequestReviewDraftSubmitSummarySurface"),
            "Broad review diff surface should not own pull request review submit summaries."
        )
        XCTAssertFalse(
            reviewText.contains("public struct WorkspacePullRequestReviewDraftCommentSurface"),
            "Broad review diff surface should not own pull request inline draft comments."
        )
    }

    func testPullRequestReviewDraftViewLivesInFocusedFile() throws {
        let paneText = try Self.appSourceText(named: "QuillCodeReviewPaneView.swift")
        let draftViewText = try Self.appSourceText(named: "QuillCodePullRequestReviewDraftView.swift")

        XCTAssertTrue(
            paneText.contains("QuillCodePullRequestReviewDraftView("),
            "Review pane should compose the focused pull request review draft editor."
        )
        XCTAssertFalse(
            paneText.contains("struct QuillCodePullRequestReviewDraftView"),
            "Broad review pane should not own the pull request review draft editor implementation."
        )
        XCTAssertTrue(
            draftViewText.contains("struct QuillCodePullRequestReviewDraftView: View"),
            "Pull request review draft editor should live in its own SwiftUI file."
        )
        XCTAssertTrue(
            draftViewText.contains("WorkspacePullRequestReviewDraftSurface"),
            "Pull request review draft editor should bind directly to the focused draft surface."
        )
    }

    func testWorkspaceSurfaceDelegatesTranscriptSurfaceContracts() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let transcriptText = try Self.appSourceText(named: "QuillCodeTranscriptSurface.swift")
        let contextBannerText = try Self.appSourceText(named: "QuillCodeContextBannerSurface.swift")
        let messageText = try Self.appSourceText(named: "QuillCodeMessageSurface.swift")
        let composerText = try Self.appSourceText(named: "QuillCodeComposerSurface.swift")

        XCTAssertTrue(transcriptText.contains("public struct TranscriptSurface"), "Transcript aggregate should live in a focused transcript surface file.")
        XCTAssertTrue(transcriptText.contains("public enum TranscriptTimelineItemKind"), "Transcript timeline kind should live in the transcript surface file.")
        XCTAssertTrue(transcriptText.contains("public struct TranscriptTimelineItemSurface"), "Transcript timeline rows should live in the transcript surface file.")
        XCTAssertTrue(contextBannerText.contains("public struct ContextBannerSurface"), "Context banner presentation should live in a focused context banner file.")
        XCTAssertTrue(messageText.contains("public struct MessageSurface"), "Message presentation should live in a focused message surface file.")
        XCTAssertTrue(composerText.contains("public struct ComposerSurface"), "Composer presentation should live in a focused composer surface file.")
        XCTAssertFalse(surfaceText.contains("public struct TranscriptSurface"), "WorkspaceSurface should not own transcript aggregate records.")
        XCTAssertFalse(surfaceText.contains("public enum TranscriptTimelineItemKind"), "WorkspaceSurface should not own transcript timeline kind presentation.")
        XCTAssertFalse(surfaceText.contains("public struct TranscriptTimelineItemSurface"), "WorkspaceSurface should not own transcript timeline rows.")
        XCTAssertFalse(surfaceText.contains("public struct ContextBannerSurface"), "WorkspaceSurface should not own context banner presentation.")
        XCTAssertFalse(surfaceText.contains("public struct MessageSurface"), "WorkspaceSurface should not own message presentation.")
        XCTAssertFalse(surfaceText.contains("public struct ComposerSurface"), "WorkspaceSurface should not own composer presentation.")
    }

    func testWorkspaceSurfaceDelegatesReviewSurfaceBuilding() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceReviewSurfaceBuilder.swift")

        XCTAssertTrue(builderText.contains("struct WorkspaceReviewSurfaceBuilder"), "Review diff construction should live in a focused builder.")
        XCTAssertTrue(builderText.contains("func surface() -> WorkspaceReviewSurface"), "Review builder should expose directly testable review construction.")
        XCTAssertTrue(builderText.contains("latestCompletedGitDiffResult"), "Review builder should own latest git-diff result selection.")
        XCTAssertTrue(builderText.contains("reviewCommentBuckets"), "Review builder should own review comment bucketing.")
        XCTAssertTrue(surfaceText.contains("WorkspaceReviewSurfaceBuilder("), "WorkspaceSurface should delegate review construction.")
        XCTAssertFalse(surfaceText.contains("private func reviewSurface("), "WorkspaceSurface should not own review surface construction.")
        XCTAssertFalse(surfaceText.contains("reviewCommentBuckets"), "WorkspaceSurface should not own review comment bucketing.")
        XCTAssertFalse(surfaceText.contains("GitDiffReviewParser.parse"), "WorkspaceSurface should not parse git diffs directly.")
    }

    func testWorkspaceModelDelegatesReviewCommentPlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let reviewExtensionText = try Self.appSourceText(named: "WorkspaceModelReview.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceReviewCommentPlanner.swift")

        XCTAssertTrue(plannerText.contains("public struct WorkspaceReviewCommentState"), "Review comment payload state should live beside the planner.")
        XCTAssertTrue(plannerText.contains("struct WorkspaceReviewCommentPlanner"), "Review comment event construction should live in a focused planner.")
        XCTAssertTrue(plannerText.contains("static func event"), "Review comment planning should be directly testable.")
        XCTAssertTrue(plannerText.contains("private static func normalizedRange"), "Review line-range normalization should be isolated in the planner.")
        XCTAssertTrue(plannerText.contains("private static func rangeExists"), "Review range validation should be isolated in the planner.")
        XCTAssertTrue(reviewExtensionText.contains("WorkspaceReviewCommentPlanner.event"), "Workspace review extension should delegate review comment planning.")
        XCTAssertFalse(modelText.contains("func addReviewComment"), "WorkspaceModel should not own review comment mutation APIs.")
        XCTAssertFalse(modelText.contains("WorkspaceReviewCommentState: Codable"), "WorkspaceModel should not own review comment payload state.")
        XCTAssertFalse(modelText.contains("normalizedReviewRange"), "WorkspaceModel should not own review line-range normalization.")
        XCTAssertFalse(modelText.contains("reviewRangeExists"), "WorkspaceModel should not own review range validation.")
        XCTAssertFalse(modelText.contains("JSONHelpers.encodePretty(comment)"), "WorkspaceModel should not own review comment payload encoding.")
    }

    func testWorkspaceModelDelegatesReviewActionToolCallPlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let reviewExtensionText = try Self.appSourceText(named: "WorkspaceModelReview.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceReviewActionToolCallPlanner.swift")
        let runnerText = try Self.appSourceText(named: "WorkspaceReviewActionRunner.swift")
        let runActionStart = try XCTUnwrap(reviewExtensionText.range(of: "func runReviewAction"))
        let runActionEnd = try XCTUnwrap(reviewExtensionText.range(of: "func runToolCardAction"))
        let runActionBody = String(reviewExtensionText[runActionStart.lowerBound..<runActionEnd.lowerBound])

        XCTAssertTrue(plannerText.contains("struct WorkspaceReviewActionRunPlan"), "Review action run sequencing should live in a focused plan.")
        XCTAssertTrue(plannerText.contains("enum WorkspaceReviewActionToolCallPlanner"), "Review action tool-call planning should live in a focused planner.")
        XCTAssertTrue(plannerText.contains("static func runPlan"), "Review action run planning should be directly testable.")
        XCTAssertTrue(plannerText.contains("static func toolCall"), "Review action tool-call planning should be directly testable.")
        XCTAssertTrue(plannerText.contains("diffRefreshCall"), "Review diff refresh sequencing should live in the planner.")
        XCTAssertTrue(plannerText.contains("finalStatus"), "Review action status derivation should live in the planner.")
        XCTAssertTrue(plannerText.contains("ToolDefinition.gitStage.name"), "File stage calls should live in the planner.")
        XCTAssertTrue(plannerText.contains("ToolDefinition.gitRestore.name"), "File restore calls should live in the planner.")
        XCTAssertTrue(plannerText.contains("ToolDefinition.gitStageHunk.name"), "Hunk stage calls should live in the planner.")
        XCTAssertTrue(plannerText.contains("ToolDefinition.gitRestoreHunk.name"), "Hunk restore calls should live in the planner.")
        XCTAssertTrue(runnerText.contains("struct WorkspaceReviewActionRunner"), "Review action execution should live in a focused runner.")
        XCTAssertTrue(runnerText.contains("struct WorkspaceReviewActionRunResult"), "Review action execution should return a typed result.")
        XCTAssertTrue(runnerText.contains("recordedResults"), "Review action execution should expose ordered tool results for transcript recording.")
        XCTAssertTrue(runnerText.contains("executor.executePrimary(plan.actionCall)"), "Review action runner should execute the action call.")
        XCTAssertTrue(runnerText.contains("plan.diffRefreshCall.map"), "Review action runner should execute the diff refresh call when the plan pairs one.")
        XCTAssertTrue(reviewExtensionText.contains("WorkspaceReviewActionToolCallPlanner.runPlan"), "Workspace review extension should delegate review action run planning.")
        XCTAssertTrue(reviewExtensionText.contains("unreadableReviewFileReason"), "Workspace review extension should guard stale unreadable Open actions.")
        XCTAssertTrue(runActionBody.contains("WorkspaceReviewActionRunner("), "Workspace review extension should delegate review action execution.")
        XCTAssertTrue(runActionBody.contains("result.recordedResults"), "Workspace review extension should record typed review action results.")
        XCTAssertTrue(runActionBody.contains("result.finalStatus"), "Workspace review extension should use the runner result for final review action status.")
        XCTAssertFalse(modelText.contains("func runReviewAction"), "WorkspaceModel should not own review action APIs.")
        XCTAssertFalse(modelText.contains("private extension WorkspaceReviewActionSurface"), "WorkspaceModel should not own review action surface extensions.")
        XCTAssertFalse(modelText.contains("var toolCall: ToolCall"), "WorkspaceModel should not own review action tool-call mapping.")
        XCTAssertFalse(modelText.contains("ToolCall(name: ToolDefinition.gitDiff.name"), "WorkspaceModel should not own review diff refresh call construction.")
        XCTAssertFalse(modelText.contains("ToolDefinition.gitStageHunk.name"), "WorkspaceModel should not own hunk review tool-call details.")
        XCTAssertFalse(modelText.contains("ToolDefinition.gitRestoreHunk.name"), "WorkspaceModel should not own hunk review tool-call details.")
        XCTAssertFalse(runActionBody.contains("executePrimary(runPlan.actionCall)"), "WorkspaceModel should not execute review action calls inline.")
        XCTAssertFalse(runActionBody.contains("executePrimary(runPlan.diffRefreshCall)"), "WorkspaceModel should not execute review diff refresh calls inline.")
    }

}
