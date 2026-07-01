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
        Self.assertSource(composerText, contains: "updateThreadFromAgentRun(thread)")
        Self.assertSource(modelText, excludesAll: [
            "func updateThreadFromAgentRun",
            "preservingSelection",
            "replaceThread("
        ])
    }
}
