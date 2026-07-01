import XCTest

final class ParityWorkspaceThreadSeedGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesThreadSeedBuilding() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let seedBuilderText = try Self.appSourceText(named: "WorkspaceThreadSeedBuilder.swift")
        let creationText = try Self.appSourceText(named: "WorkspaceThreadCreationEngine.swift")
        let continuationText = try Self.appSourceText(named: "WorkspaceModelContextContinuations.swift")
        let threadExtensionText = try Self.appSourceText(named: "WorkspaceModelThreads.swift")
        let summaryGeneratorText = try Self.appSourceText(named: "WorkspaceContextSummaryGenerators.swift")
        let summaryPromptText = try Self.appSourceText(named: "WorkspaceContextSummaryPromptBuilder.swift")
        let summarySanitizerText = try Self.appSourceText(named: "WorkspaceContextSummarySanitizer.swift")
        let summaryRequestText = try Self.appSourceText(named: "WorkspaceContextSummaryRequest.swift")
        let summaryTelemetryText = try Self.appSourceText(named: "WorkspaceContextSummaryTelemetry.swift")
        let runtimeText = try Self.appSourceText(named: "RuntimeFactory.swift")

        [
            "struct WorkspaceThreadSeedBuilder",
            "static func title(fromUserPrompt",
            "static func forkSeedMessages",
            "static func compactSeedMessages"
        ].forEach { Self.assertSource(seedBuilderText, contains: $0) }
        [
            "protocol WorkspaceContextSummaryGenerating",
            "struct LLMWorkspaceContextSummaryGenerator"
        ].forEach { Self.assertSource(summaryGeneratorText, contains: $0) }
        Self.assertSource(summaryPromptText, contains: "enum WorkspaceContextSummaryPromptBuilder")
        Self.assertSource(summarySanitizerText, contains: "enum WorkspaceContextSummarySanitizer")
        Self.assertSource(summaryRequestText, contains: "struct WorkspaceContextSummaryRequest")
        Self.assertSource(summaryTelemetryText, contains: "struct WorkspaceContextSummaryTelemetry")
        Self.assertSource(runtimeText, contains: "contextSummaryGenerator: LLMWorkspaceContextSummaryGenerator")
        [
            "WorkspaceThreadSeedBuilder.forkSeedMessages",
            "WorkspaceThreadSeedBuilder.compactSeedMessages"
        ].forEach { Self.assertSource(creationText, contains: $0) }
        [
            "func startForkThread",
            "func compactContextWithConfiguredSummary",
            "WorkspaceContextSummaryTelemetryPlanner.continuationEvent"
        ].forEach { Self.assertSource(continuationText, contains: $0) }
        [
            "contextSummaryGenerator.summary",
            "recordContextSummarySourceNotice"
        ].forEach { Self.assertSource(threadExtensionText, excludes: $0) }
        [
            "private static func forkSeedMessages",
            "private static func compactSeedMessages",
            "private static func compactSummaryMessage",
            "TrustedRouterLLMClient"
        ].forEach { Self.assertSource(modelText, excludes: $0) }
    }
}
