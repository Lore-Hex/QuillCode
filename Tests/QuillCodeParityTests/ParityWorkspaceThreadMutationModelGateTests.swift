import XCTest

final class ParityWorkspaceThreadMutationModelGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesThreadNoticeMutation() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let threadMutationText = try Self.appSourceText(named: "WorkspaceModelThreadMutation.swift")
        let reviewExtensionText = try Self.appSourceText(named: "WorkspaceModelReview.swift")
        let appenderText = try Self.appSourceText(named: "WorkspaceThreadNoticeAppender.swift")

        Self.assertSource(appenderText, containsAll: [
            "enum WorkspaceThreadNoticeAppender",
            "static func appendNotice",
            "static func appendAssistantNotice"
        ])
        Self.assertSource(threadMutationText, contains: "WorkspaceThreadNoticeAppender.appendNotice")
        Self.assertSource(reviewExtensionText, contains: "WorkspaceThreadNoticeAppender.appendAssistantNotice")
        Self.assertSource(modelText, excludesAll: [
            "WorkspaceThreadNoticeAppender.appendNotice",
            "WorkspaceThreadNoticeAppender.appendAssistantNotice",
            "thread.events.append(.init(kind: .notice",
            "thread.events.append(.init(kind: .message",
            "thread.messages.append(.init(role: .assistant"
        ])
    }

    func testWorkspaceModelUsesExplicitAgentRunThreadUpdates() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let threadMutationText = try Self.appSourceText(named: "WorkspaceModelThreadMutation.swift")
        let composerText = try Self.appSourceText(named: "WorkspaceModelComposer.swift")

        Self.assertSource(threadMutationText, contains: "func updateThreadFromAgentRun")
        Self.assertSource(threadMutationText, excludes: "ThreadEventLogCompactor.compact")
        Self.assertSource(composerText, containsAll: [
            "updateThreadFromAgentRun(",
            "preserveMemoryContext: !completion.shouldRefreshMemoryContext"
        ])
        Self.assertSource(modelText, excludesAll: [
            "func updateThreadFromAgentRun",
            "preservingSelection",
            "replaceThread("
        ])
    }

    func testStreamingProgressUsesDetachedInPlaceHistoryReconciliation() throws {
        let composerText = try Self.appSourceText(named: "WorkspaceModelComposer.swift")
        let threadMutationText = try Self.appSourceText(named: "WorkspaceModelThreadMutation.swift")
        let lifecycleText = try Self.appSourceText(named: "WorkspaceThreadLifecycleEngine.swift")
        let reconcilerText = try Self.appSourceText(named: "WorkspaceAgentProgressThreadReconciler.swift")

        Self.assertSource(composerText, contains: "updateThreadFromAgentProgress(progress.thread)")
        Self.assertSource(composerText, excludes: "updateThreadFromAgentRun(progress.thread)")
        Self.assertSource(threadMutationText, contains: "func updateThreadFromAgentProgress")
        Self.assertSource(lifecycleText, contains: "applyAgentRunProgressThreadUpdate")
        Self.assertSource(reconcilerText, containsAll: [
            "WorkspaceAgentProgressThreadReconciler",
            "live[index] = snapshot[index]",
            "live.append(contentsOf: snapshot[live.count...])",
            "live.removeAll(keepingCapacity: true)"
        ])
        Self.assertSource(reconcilerText, excludes: "live = snapshot")
    }
}
