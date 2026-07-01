import XCTest

final class ParityWorkspaceThreadSeedGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesThreadSeedBuilding() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let seedBuilderText = try Self.appSourceText(named: "WorkspaceThreadSeedBuilder.swift")
        let creationText = try Self.appSourceText(named: "WorkspaceThreadCreationEngine.swift")
        let continuationText = try Self.appSourceText(named: "WorkspaceModelContextContinuations.swift")
        let threadText = try Self.appSourceText(named: "WorkspaceModelThreads.swift")
        let summaryGeneratorText = try Self.appSourceText(named: "WorkspaceContextSummaryGenerators.swift")
        let summaryPromptText = try Self.appSourceText(named: "WorkspaceContextSummaryPromptBuilder.swift")
        let summarySanitizerText = try Self.appSourceText(named: "WorkspaceContextSummarySanitizer.swift")
        let summaryRequestText = try Self.appSourceText(named: "WorkspaceContextSummaryRequest.swift")
        let summaryTelemetryText = try Self.appSourceText(named: "WorkspaceContextSummaryTelemetry.swift")
        let runtimeText = try Self.appSourceText(named: "RuntimeFactory.swift")

        assertSeedBuilderContracts(seedBuilderText)
        assertSummaryBoundary(
            generator: summaryGeneratorText,
            prompt: summaryPromptText,
            sanitizer: summarySanitizerText,
            request: summaryRequestText,
            telemetry: summaryTelemetryText
        )
        assertSeedDelegation(creationText, continuationText, runtimeText)
        assertThreadAPIsAvoidSummaryOwnership(threadText)
        assertWorkspaceModelAvoidsSeedOwnership(modelText)
    }

    private func assertSeedBuilderContracts(_ source: String) {
        [
            "struct WorkspaceThreadSeedBuilder",
            "static func title(fromUserPrompt",
            "static func forkSeedMessages",
            "static func compactSeedMessages"
        ].forEach { Self.assertSource(source, contains: $0) }
    }

    private func assertSummaryBoundary(
        generator: String,
        prompt: String,
        sanitizer: String,
        request: String,
        telemetry: String
    ) {
        Self.assertSource(generator, contains: "protocol WorkspaceContextSummaryGenerating")
        Self.assertSource(generator, contains: "struct LLMWorkspaceContextSummaryGenerator")
        Self.assertSource(prompt, contains: "enum WorkspaceContextSummaryPromptBuilder")
        Self.assertSource(sanitizer, contains: "enum WorkspaceContextSummarySanitizer")
        Self.assertSource(request, contains: "struct WorkspaceContextSummaryRequest")
        Self.assertSource(telemetry, contains: "struct WorkspaceContextSummaryTelemetry")
    }

    private func assertSeedDelegation(
        _ creationText: String,
        _ continuationText: String,
        _ runtimeText: String
    ) {
        [
            "WorkspaceThreadSeedBuilder.forkSeedMessages",
            "WorkspaceThreadSeedBuilder.compactSeedMessages"
        ].forEach { Self.assertSource(creationText, contains: $0) }
        [
            "func startForkThread",
            "func compactContextWithConfiguredSummary",
            "WorkspaceContextSummaryTelemetryPlanner.continuationEvent"
        ].forEach { Self.assertSource(continuationText, contains: $0) }
        Self.assertSource(
            runtimeText,
            contains: "contextSummaryGenerator: LLMWorkspaceContextSummaryGenerator"
        )
    }

    private func assertThreadAPIsAvoidSummaryOwnership(_ threadText: String) {
        [
            "contextSummaryGenerator.summary",
            "recordContextSummarySourceNotice"
        ].forEach { Self.assertSource(threadText, excludes: $0) }
    }

    private func assertWorkspaceModelAvoidsSeedOwnership(_ modelText: String) {
        [
            "private static func forkSeedMessages",
            "private static func compactSeedMessages",
            "private static func compactSummaryMessage",
            "TrustedRouterLLMClient"
        ].forEach { Self.assertSource(modelText, excludes: $0) }
    }
}
