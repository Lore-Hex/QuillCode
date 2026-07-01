import XCTest

final class ParityAgentStreamingGateTests: QuillCodeParityTestCase {
    func testAgentStreamingHelpersLiveOutsideAgentRunnerFile() throws {
        let agentText = try Self.agentSourceText(named: "Agent.swift")
        let actionResolverText = try Self.agentSourceText(named: "AgentActionResolver.swift")
        let streamingText = try Self.agentSourceText(named: "AgentActionStreaming.swift")
        let textRunnerText = try Self.agentSourceText(named: "AgentTextStreamActionRunner.swift")
        let usageRunnerText = try Self.agentSourceText(named: "AgentUsageStreamActionRunner.swift")
        let rawCollectorText = try Self.agentSourceText(named: "AgentRawTextStreamActionCollector.swift")
        let textCollectorText = try Self.agentSourceText(named: "AgentTextStreamActionCollector.swift")
        let usageCollectorText = try Self.agentSourceText(named: "AgentUsageStreamActionCollector.swift")
        let draftPublisherText = try Self.agentSourceText(named: "AgentStreamingDraftPublisher.swift")

        Self.assertSource(streamingText, containsAll: [
            "public enum AgentActionStreamCollector",
            "public enum AgentActionStreamPreview",
            "var rawActionText",
            "AgentActionStreamPreview.visibleAssistantText"
        ])
        Self.assertSource(actionResolverText, containsAll: [
            "nextTextStreamingAction",
            "nextUsageStreamingAction"
        ])
        Self.assertSource(textRunnerText, contains: "func nextTextStreamingAction")
        Self.assertSource(usageRunnerText, contains: "func nextUsageStreamingAction")
        Self.assertSource(rawCollectorText, contains: "AgentActionStreamCollector.collect")
        Self.assertSource(textCollectorText, contains: "AgentActionStreamCollector.collect")
        Self.assertSource(usageCollectorText, contains: "AgentActionStreamCollector.collect")
        Self.assertSource(draftPublisherText, containsAll: [
            "publishAssistantDraft",
            "publishReasoningSummary"
        ])
        Self.assertSource(agentText, excludesAll: [
            "public enum AgentActionStreamCollector",
            "private static func partialJSONStringValue",
            "AgentActionStreamPreview.visibleAssistantText",
            "AgentActionStreamCollector.collect",
            "actionTextStream(",
            "actionEventStream(",
            "var rawActionText"
        ])
    }

    func testAgentCancellationTelemetryLivesInFocusedRecorder() throws {
        let agentText = try Self.agentSourceText(named: "Agent.swift")
        let recorderText = try Self.agentSourceText(named: "AgentCancellationRecorder.swift")
        let streamingTests = try Self.agentTestSourceText(named: "AgentStreamingTests.swift")

        Self.assertSource(recorderText, containsAll: [
            "enum AgentCancellationRecorder",
            "Stopped by user"
        ])
        Self.assertSource(agentText, contains: "AgentCancellationRecorder.recordCancelledRun")
        Self.assertSource(agentText, excludes: #""Stopped by user""#)
        Self.assertSource(streamingTests, containsAll: [
            "testCancellingBeforeModelActionPublishesStoppedNotice",
            "testCancellingRunningToolPublishesStoppedToolFailure"
        ])
    }
}
