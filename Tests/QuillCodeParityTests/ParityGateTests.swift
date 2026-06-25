import XCTest

final class ParityGateTests: QuillCodeParityTestCase {
    func testQuillCodeAppHasNoLinuxConditionals() throws {
        let packageRoot = Self.packageRoot()
        let sourceRoots = [
            packageRoot.appendingPathComponent("Sources/QuillCodeApp"),
            packageRoot.appendingPathComponent("Sources/quill-code-desktop")
        ]
        let files = try sourceRoots.flatMap { root in
            try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil
            ).filter { $0.pathExtension == "swift" }
        }

        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(text.contains("#if os(Linux)"), "\(file.path) contains app-level Linux conditional")
            XCTAssertFalse(text.contains("#if linux"), "\(file.path) contains app-level Linux conditional")
        }
    }

    func testProductionSourcesAvoidForceUnwrapsAndForceCasts() throws {
        let sourceFiles = try Self.swiftSourceFiles(in: "Sources")
        for file in sourceFiles {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(text.contains("try!"), "\(file.path) should not force-try in production source.")
            XCTAssertFalse(text.contains("as!"), "\(file.path) should not force-cast in production source.")
            XCTAssertFalse(
                text.range(of: #"[A-Za-z0-9_\)\]]!\s*(\.|\)|,|\]|$)"#, options: .regularExpression) != nil,
                "\(file.path) should not force-unwrap in production source."
            )
        }
    }

    func testParityDocsExist() {
        let root = Self.packageRoot()
        for name in ["DECISIONS.md", "CODEX_RESEARCH.md", "CODEX_PARITY_MATRIX.md", "ROADMAP.md", "TEST_PLAN.md"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("docs/\(name)").path), name)
        }
    }

    func testParityGatesUseFocusedSuitesAndSharedSupport() throws {
        let root = Self.packageRoot().appendingPathComponent("Tests/QuillCodeParityTests")
        let suiteFiles = [
            "ParityTestSupport.swift",
            "ParityToolGateTests.swift",
            "ParityDesktopGateTests.swift",
            "ParityTopBarGateTests.swift",
            "ParitySlashGateTests.swift",
            "ParityModelGateTests.swift",
            "ParityWorkspaceSurfaceGateTests.swift",
            "ParityWorkspaceModelGateTests.swift",
            "ParityWorkspaceExecutionGateTests.swift",
            "ParityWorkspaceProjectGateTests.swift",
            "ParityWorkspaceMemoryGateTests.swift",
            "ParityWorkspaceIntegrationGateTests.swift"
        ]
        for suiteFile in suiteFiles {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(suiteFile).path), suiteFile)
        }

        let mainText = try String(contentsOf: root.appendingPathComponent("ParityGateTests.swift"), encoding: .utf8)
        let mainLines = Set(mainText.components(separatedBy: .newlines))
        XCTAssertFalse(mainLines.contains("    private static func packageRoot() -> URL {"), "Shared source-reading helpers should live in ParityTestSupport.")

        let focusedSuiteTests: [(suiteName: String, testNames: [String])] = [
            ("ParityToolGateTests", ["testToolArgumentJSONSerializationLivesInCore"]),
            ("ParityDesktopGateTests", ["testDesktopDefinesNativeMenuBarWidget"]),
            ("ParityTopBarGateTests", ["testTopBarViewsDelegateStatusPresentationSemantics"]),
            ("ParitySlashGateTests", ["testSlashParserDelegatesPullRequestSubcommands"]),
            ("ParityModelGateTests", ["testTrustedRouterModelCatalogLivesOutsideGeneralDomainModels"]),
            ("ParityWorkspaceSurfaceGateTests", ["testWorkspaceSurfaceDelegatesSecondaryPaneSurfaceContracts"]),
            ("ParityWorkspaceModelGateTests", [
                "testWorkspaceModelDelegatesToolCardSurfaceTypes",
                "testWorkspaceModelDelegatesProjectContextRefresh",
                "testWorkspaceModelDelegatesThreadSeedBuilding",
                "testWorkspaceModelDelegatesThreadCreationRecords",
                "testWorkspaceModelDelegatesThreadLifecycleTransitions",
                "testWorkspaceModelDelegatesConfigurationTransitions",
                "testWorkspaceConfigurationIntegrationTestsOwnModelConfigurationFlows",
                "testWorkspaceModelDelegatesRetryPlanning",
                "testWorkspaceActivityIntegrationTestsOwnModelActivityFlows",
                "testWorkspaceActivitySurfaceUsesFocusedBuilderAndSectionTypes",
                "testWorkspaceToolCardIntegrationTestsOwnModelToolCardFlows",
                "testWorkspaceModelTestsRemainRetired",
                "testFocusedWorkspaceUnitSuitesUseSharedTemporaryDirectorySupport",
                "testWorkspaceModelDelegatesStatusTextAndLabels",
                "testWorkspaceModelDelegatesContextResolving",
                "testWorkspaceModelDelegatesAgentProgressStatusCopy",
                "testWorkspaceModelDelegatesThreadNoticeMutation",
                "testWorkspaceModelUsesExplicitAgentRunThreadUpdates"
            ]),
            ("ParityWorkspaceExecutionGateTests", [
                "testWorkspaceModelDelegatesComposerCancellationPlanning",
                "testWorkspaceModelDelegatesComposerSubmissionPlanning",
                "testWorkspaceModelDelegatesAgentSendSessionExecution",
                "testWorkspaceModelDelegatesSlashCommandTranscriptPlanning",
                "testWorkspaceModelDelegatesCommandActionPlanning",
                "testWorkspaceModelDelegatesCommandPlanExecution",
                "testWorkspaceModelDelegatesAgentRunContextAssembly",
                "testWorkspaceModelDelegatesAgentSendSession",
                "testWorkspaceModelDelegatesToolEventRecording",
                "testWorkspaceModelDelegatesToolCallExecutionRouting",
                "testWorkspaceModelDelegatesShellToolCallPlanning",
                "testWorkspaceComposerIntegrationTestsOwnModelComposerFlows",
                "testWorkspaceModelDelegatesSlashCommandDispatchPlanning",
                "testWorkspaceModelDelegatesToolExecutionOverrideCombining"
            ]),
            ("ParityWorkspaceProjectGateTests", [
                "testWorkspaceModelDelegatesProjectMetadataLoading",
                "testWorkspaceModelTestsDoNotOwnPureProjectLoaderCoverage",
                "testWorkspaceProjectExtensionIntegrationTestsOwnModelExtensionFlows",
                "testWorkspaceProjectIntegrationTestsOwnModelProjectFlows",
                "testWorkspaceRemoteProjectIntegrationTestsOwnModelRemoteProjectFlows",
                "testWorkspacePullRequestIntegrationTestsOwnModelPullRequestFlows",
                "testWorkspaceWorktreeIntegrationTestsOwnModelWorktreeFlows",
                "testWorkspaceModelDelegatesWorktreeOpenRecords"
            ]),
            ("ParityWorkspaceMemoryGateTests", [
                "testWorkspaceModelDelegatesMemoryCommandOrchestration",
                "testWorkspaceMemoryIntegrationTestsOwnModelMemoryFlows"
            ]),
            ("ParityWorkspaceIntegrationGateTests", [
                "testWorkspaceMCPIntegrationTestsOwnModelMCPFlows",
                "testWorkspaceReviewIntegrationTestsOwnModelReviewFlows",
                "testFocusedFeedbackAndArtifactTestsOwnSurfaceSpecificFlows",
                "testWorkspaceRuntimeIssueIntegrationTestsOwnModelRuntimeIssueFlows",
                "testWorkspaceThreadLifecycleIntegrationTestsOwnModelLifecycleFlows",
                "testWorkspaceSlashCommandIntegrationTestsOwnCoreSlashFlows",
                "testWorkspaceLocalEnvironmentIntegrationTestsOwnModelLocalEnvironmentFlows",
                "testWorkspaceAutomationIntegrationTestsOwnModelAutomationFlows",
                "testWorkspaceTerminalIntegrationTestsOwnModelTerminalFlows",
                "testWorkspaceModelTestsDoNotOwnRuntimeFactoryCoverage"
            ])
        ]

        for (suiteName, testNames) in focusedSuiteTests {
            for testName in testNames {
                XCTAssertFalse(
                    mainLines.contains("    func \(testName)() throws {"),
                    "\(testName) should live in \(suiteName)."
                )
            }
        }
    }

    func testAgentRunnerDelegatesFinalAnswerFormatting() throws {
        let agentText = try Self.agentSourceText(named: "Agent.swift")
        let builderText = try Self.agentSourceText(named: "AgentFinalAnswerBuilder.swift")

        XCTAssertTrue(builderText.contains("enum AgentFinalAnswerBuilder"), "Tool-result final answer copy should live in a focused builder.")
        XCTAssertTrue(builderText.contains("static func finalAnswer"), "Final answer formatting should be directly testable.")
        XCTAssertTrue(builderText.contains("ToolDefinition.shellRun.name"), "Shell final-answer special cases should live in the builder.")
        XCTAssertTrue(builderText.contains("ToolDefinition.browserInspect.name"), "Browser final-answer special cases should live in the builder.")
        XCTAssertTrue(agentText.contains("AgentFinalAnswerBuilder.finalAnswer"), "AgentRunner should delegate final-answer formatting.")
        XCTAssertFalse(agentText.contains("private static func shellAnswer"), "AgentRunner should not own shell final-answer formatting.")
        XCTAssertFalse(agentText.contains("private static func browserInspectionAnswer"), "AgentRunner should not own browser final-answer formatting.")
    }

    func testMockLLMClientLivesOutsideAgentRunnerFile() throws {
        let agentText = try Self.agentSourceText(named: "Agent.swift")
        let mockText = try Self.agentSourceText(named: "MockLLMClient.swift")
        let pullRequestPlannerText = try Self.agentSourceText(named: "MockPullRequestIntentPlanner.swift")
        let pullRequestExtractorText = try Self.agentSourceText(named: "MockPullRequestArgumentExtractor.swift")

        XCTAssertTrue(mockText.contains("public struct MockLLMClient"), "The deterministic mock LLM client should live in its own file.")
        XCTAssertTrue(mockText.contains("MockPullRequestIntentPlanner.toolCall"), "The mock LLM client should delegate PR-specific planning.")
        XCTAssertTrue(mockText.contains("AgentRunner.finalAnswer"), "Mock tool feedback should still reuse the production final-answer contract.")
        XCTAssertTrue(pullRequestPlannerText.contains("enum MockPullRequestIntentPlanner"), "Mock PR intent detection should live in a focused planner.")
        XCTAssertTrue(pullRequestPlannerText.contains("MockPullRequestArgumentExtractor.createArguments"), "Mock PR planner should delegate payload construction.")
        XCTAssertTrue(pullRequestExtractorText.contains("enum MockPullRequestArgumentExtractor"), "Mock PR payload construction should live in a focused extractor.")
        XCTAssertTrue(pullRequestExtractorText.contains("static func createArguments"), "Mock PR create argument extraction should stay out of intent routing.")
        XCTAssertFalse(agentText.contains("public struct MockLLMClient"), "Agent.swift should not own mock LLM planning.")
        XCTAssertFalse(agentText.contains("extractPullRequestArguments"), "Agent.swift should not own mock PR parsing heuristics.")
        XCTAssertFalse(mockText.contains("extractPullRequestArguments"), "MockLLMClient.swift should not own PR parsing heuristics.")
        XCTAssertFalse(mockText.contains("isPullRequestRequest"), "MockLLMClient.swift should not own PR intent detection.")
        XCTAssertFalse(pullRequestPlannerText.contains("static func createArguments"), "Mock PR planner should not own argument extraction.")
    }

    func testAgentStreamingHelpersLiveOutsideAgentRunnerFile() throws {
        let agentText = try Self.agentSourceText(named: "Agent.swift")
        let streamingText = try Self.agentSourceText(named: "AgentActionStreaming.swift")

        XCTAssertTrue(streamingText.contains("public enum AgentActionStreamCollector"), "Streaming action collection should live in a focused helper.")
        XCTAssertTrue(streamingText.contains("public enum AgentActionStreamPreview"), "Partial assistant preview parsing should live with streaming helpers.")
        XCTAssertTrue(streamingText.contains("var rawActionText"), "Progressive stream accumulation should live with the stream collector.")
        XCTAssertTrue(streamingText.contains("AgentActionStreamPreview.visibleAssistantText"), "Stream collector should own draft-preview extraction.")
        XCTAssertTrue(agentText.contains("AgentActionStreamCollector.collect"), "AgentRunner should delegate streaming collection.")
        XCTAssertFalse(agentText.contains("public enum AgentActionStreamCollector"), "Agent.swift should not own streaming collection details.")
        XCTAssertFalse(agentText.contains("private static func partialJSONStringValue"), "Agent.swift should not own partial JSON preview parsing.")
        XCTAssertFalse(agentText.contains("AgentActionStreamPreview.visibleAssistantText"), "Agent.swift should not own streaming preview parsing.")
        XCTAssertFalse(agentText.contains("var rawActionText"), "Agent.swift should not own raw streaming accumulation.")
    }

    func testTrustedRouterActionParserLivesOutsideTransportClient() throws {
        let clientText = try Self.agentSourceText(named: "TrustedRouterLLMClient.swift")
        let parserText = try Self.agentSourceText(named: "AgentActionJSONParser.swift")
        let extractorText = try Self.agentSourceText(named: "AgentActionJSONExtractor.swift")
        let recoveryText = try Self.agentSourceText(named: "AgentShellCommandRecovery.swift")
        let normalizerText = try Self.agentSourceText(named: "AgentToolArgumentNormalizer.swift")

        XCTAssertTrue(parserText.contains("public enum AgentActionJSONParser"), "Action JSON parsing should live in a focused parser file.")
        XCTAssertTrue(normalizerText.contains("enum AgentToolArgumentNormalizer"), "Tool argument normalization should live in a focused normalizer.")
        XCTAssertTrue(normalizerText.contains("canonicalArguments"), "The normalizer should own canonical argument construction.")
        XCTAssertTrue(parserText.contains("AgentToolArgumentNormalizer.canonicalArguments"), "Action JSON parsing should delegate canonical argument construction.")
        XCTAssertTrue(parserText.contains("AgentActionJSONExtractor.actionObject"), "Action JSON parsing should delegate messy JSON extraction.")
        XCTAssertTrue(normalizerText.contains("AgentShellCommandRecovery.explicitCommand"), "Tool argument normalization should delegate malformed shell recovery.")
        XCTAssertTrue(extractorText.contains("enum AgentActionJSONExtractor"), "JSON object scanning should live in a focused helper.")
        XCTAssertTrue(recoveryText.contains("enum AgentShellCommandRecovery"), "Malformed shell-command recovery should live in a focused helper.")
        XCTAssertTrue(clientText.contains("AgentActionStreamCollector.collect"), "TrustedRouter client should delegate action collection/parsing.")
        XCTAssertFalse(clientText.contains("public enum AgentActionJSONParser"), "TrustedRouter transport should not own action parsing.")
        XCTAssertFalse(clientText.contains("canonicalArguments"), "TrustedRouter transport should not own tool argument normalization.")
        XCTAssertFalse(parserText.contains("private static func canonicalArguments"), "Action parser should not own tool argument normalization details.")
        XCTAssertFalse(parserText.contains("normalizePullRequestArguments"), "Action parser should not own pull request argument alias policy.")
        XCTAssertFalse(parserText.contains("requiresNonEmptyArguments"), "Action parser should not own tool minimum-argument policy.")
        XCTAssertFalse(parserText.contains("jsonObjectCandidates"), "Action parser should not own JSON-object scanning.")
        XCTAssertFalse(parserText.contains("inlineCodeSpans"), "Action parser should not own prose shell command recovery.")
        XCTAssertFalse(clientText.contains("AgentShellCommandRecovery"), "TrustedRouter transport should not own malformed-output recovery.")
        XCTAssertFalse(clientText.contains("jsonObjectCandidates"), "TrustedRouter transport should not own JSON-object extraction.")
    }

    func testTrustedRouterPromptBuilderLivesOutsideTransportClient() throws {
        let clientText = try Self.agentSourceText(named: "TrustedRouterLLMClient.swift")
        let builderText = try Self.agentSourceText(named: "TrustedRouterPromptBuilder.swift")

        XCTAssertTrue(builderText.contains("public struct TrustedRouterPromptBuilder"), "Prompt rendering should live in a focused builder.")
        XCTAssertTrue(builderText.contains("historyLimit"), "Prompt history policy should stay with the prompt builder.")
        XCTAssertTrue(builderText.contains("systemPrompt(tools"), "System prompt copy should stay with the prompt builder.")
        XCTAssertTrue(builderText.contains("projectInstructionsPrompt"), "Project instruction formatting should stay with the prompt builder.")
        XCTAssertTrue(builderText.contains("memoryPrompt"), "Memory formatting should stay with the prompt builder.")
        XCTAssertTrue(clientText.contains("promptBuilder.messages"), "TrustedRouter client should delegate message construction.")
        XCTAssertFalse(clientText.contains("systemPrompt(tools"), "TrustedRouter transport should not own system prompt copy.")
        XCTAssertFalse(clientText.contains("projectInstructionsPrompt"), "TrustedRouter transport should not own project instruction formatting.")
        XCTAssertFalse(clientText.contains("memoryPrompt"), "TrustedRouter transport should not own memory formatting.")
        XCTAssertFalse(clientText.contains("thread.messages.suffix"), "TrustedRouter transport should not own message history projection.")
    }

    func testTrustedRouterAPIKeyResolutionLivesInFocusedResolver() throws {
        let clientText = try Self.agentSourceText(named: "TrustedRouterLLMClient.swift")
        let safetyClientText = try Self.agentSourceText(named: "TrustedRouterSafetyModelClient.swift")
        let resolverText = try Self.agentSourceText(named: "TrustedRouterAPIKeyResolver.swift")

        XCTAssertTrue(resolverText.contains("public struct TrustedRouterAPIKeyResolver"), "TrustedRouter API-key resolution should live in a focused helper.")
        XCTAssertTrue(resolverText.contains("apiKeyOverride"), "Developer override handling should stay with the resolver.")
        XCTAssertTrue(resolverText.contains("sessionStore?.apiKey()"), "Session-store fallback should stay with the resolver.")
        XCTAssertTrue(resolverText.contains("nonEmptyKey"), "Whitespace trimming should stay with the resolver.")
        XCTAssertTrue(clientText.contains("TrustedRouterAPIKeyResolver("), "TrustedRouter clients should delegate key resolution.")
        XCTAssertTrue(safetyClientText.contains("TrustedRouterAPIKeyResolver("), "TrustedRouter safety clients should delegate key resolution.")
        XCTAssertFalse(clientText.contains("trimmingCharacters(in: .whitespacesAndNewlines)"), "TrustedRouter clients should not duplicate key trimming.")
        XCTAssertFalse(clientText.contains("sessionStore?.apiKey()"), "TrustedRouter clients should not duplicate session-store fallback.")
        XCTAssertFalse(safetyClientText.contains("sessionStore?.apiKey()"), "TrustedRouter safety clients should not duplicate session-store fallback.")
    }

    func testTrustedRouterSafetyClientLivesOutsideActionTransportFile() throws {
        let clientText = try Self.agentSourceText(named: "TrustedRouterLLMClient.swift")
        let safetyClientText = try Self.agentSourceText(named: "TrustedRouterSafetyModelClient.swift")

        XCTAssertTrue(safetyClientText.contains("public struct TrustedRouterSafetyModelClient"), "TrustedRouter safety-review transport should live in its own file.")
        XCTAssertTrue(safetyClientText.contains("SafetyModelClient"), "The safety transport file should own the SafetyModelClient conformance.")
        XCTAssertTrue(safetyClientText.contains("Return only the requested JSON object."), "Safety-review JSON response framing should live with the safety transport.")
        XCTAssertFalse(clientText.contains("TrustedRouterSafetyModelClient"), "TrustedRouter action transport should not also own the safety-review client.")
        XCTAssertFalse(clientText.contains("SafetyModelClient"), "TrustedRouter action transport should not import or conform to safety protocols.")
    }

    func testTrustedRouterChatParametersLiveOutsideTransportClients() throws {
        let clientText = try Self.agentSourceText(named: "TrustedRouterLLMClient.swift")
        let safetyClientText = try Self.agentSourceText(named: "TrustedRouterSafetyModelClient.swift")
        let parametersText = try Self.agentSourceText(named: "TrustedRouterChatParameters.swift")

        XCTAssertTrue(parametersText.contains("public enum TrustedRouterChatParameters"), "Shared TrustedRouter chat request parameters should live in a focused catalog.")
        XCTAssertTrue(parametersText.contains("\"response_format\""), "JSON response-format payload should stay in the parameter catalog.")
        XCTAssertTrue(clientText.contains("TrustedRouterChatParameters.jsonObjectResponse"), "Action transport should use shared JSON response parameters.")
        XCTAssertTrue(safetyClientText.contains("TrustedRouterChatParameters.jsonObjectResponse"), "Safety transport should use shared JSON response parameters.")
        XCTAssertFalse(clientText.contains("\"response_format\""), "Action transport should not own raw response-format payloads.")
        XCTAssertFalse(safetyClientText.contains("\"response_format\""), "Safety transport should not own raw response-format payloads.")
        XCTAssertFalse(safetyClientText.contains("TrustedRouterLLMClient."), "Safety transport should not depend on the action transport type.")
    }

    func testStaticSafetyPolicyLivesOutsideReviewerControlFlow() throws {
        let reviewerText = try Self.safetySourceText(named: "Safety.swift")
        let policyText = try Self.safetySourceText(named: "StaticSafetyPolicy.swift")

        XCTAssertTrue(policyText.contains("struct StaticSafetyPolicy"), "Static safety intent policy should live in a focused policy file.")
        XCTAssertTrue(policyText.contains("StaticSafetyHardDenyRule"), "Hard-deny patterns should be explicit policy table entries.")
        XCTAssertTrue(policyText.contains("StaticSafetyIntentRule"), "Intent-to-tool matching should use table-driven rules.")
        XCTAssertTrue(policyText.contains("StaticSafetyPullRequestPolicy"), "Pull request safety routing should live beside the static policy tables.")
        XCTAssertTrue(reviewerText.contains("policy.hardDenyReason"), "StaticSafetyReviewer should delegate hard-deny checks to the policy.")
        XCTAssertTrue(reviewerText.contains("policy.userIntentMatches"), "StaticSafetyReviewer should delegate intent matching to the policy.")
        XCTAssertFalse(reviewerText.contains(#""rm -rf /""#), "StaticSafetyReviewer should not own raw hard-deny command patterns.")
        XCTAssertFalse(reviewerText.contains("user.contains(\"pull request\")"), "StaticSafetyReviewer should not own raw pull-request intent chains.")
    }

    func testCoreToolModelsLiveOutsideGeneralDomainModels() throws {
        let modelsText = try Self.coreSourceText(named: "Models.swift")
        let toolModelsText = try Self.coreSourceText(named: "ToolModels.swift")

        XCTAssertTrue(toolModelsText.contains("public struct ToolDefinition"), "Tool schema records should live in a focused core file.")
        XCTAssertTrue(toolModelsText.contains("public struct ToolCall"), "Tool-call payload records should live beside tool schemas.")
        XCTAssertTrue(toolModelsText.contains("public struct ToolResult"), "Tool-result payload records should live beside tool schemas.")
        XCTAssertTrue(toolModelsText.contains("redactedForTranscript"), "Tool-call redaction belongs with tool-call payload records.")
        XCTAssertTrue(toolModelsText.contains("public struct BrowserInspectionToolOutput"), "Tool-specific browser output compatibility belongs with tool models.")
        XCTAssertTrue(toolModelsText.contains("public struct MemoryRememberToolOutput"), "Tool-specific memory output compatibility belongs with tool models.")
        XCTAssertTrue(toolModelsText.contains("static let planUpdate"), "Built-in core tool definitions should live with tool schema records.")
        XCTAssertFalse(modelsText.contains("public struct ToolDefinition"), "General domain models should not own tool schema records.")
        XCTAssertFalse(modelsText.contains("public struct ToolCall"), "General domain models should not own tool-call payload records.")
        XCTAssertFalse(modelsText.contains("public struct ToolResult"), "General domain models should not own tool-result payload records.")
        XCTAssertFalse(modelsText.contains("redactedForTranscript"), "General domain models should not own tool-call redaction.")
        XCTAssertFalse(modelsText.contains("public struct BrowserInspectionToolOutput"), "General domain models should not own tool-specific output compatibility.")
        XCTAssertFalse(modelsText.contains("public struct MemoryRememberToolOutput"), "General domain models should not own tool-specific output compatibility.")
    }

    func testAutomationModelsLiveOutsideGeneralDomainModels() throws {
        let modelsText = try Self.coreSourceText(named: "Models.swift")
        let automationText = try Self.coreSourceText(named: "AutomationModels.swift")

        XCTAssertTrue(automationText.contains("public enum QuillAutomationKind"), "Automation kind should live in a focused core file.")
        XCTAssertTrue(automationText.contains("public enum QuillAutomationStatus"), "Automation status should live beside automation records.")
        XCTAssertTrue(automationText.contains("public enum QuillAutomationScheduleKind"), "Automation schedule kind should live beside automation records.")
        XCTAssertTrue(automationText.contains("public struct QuillAutomationRecurrence"), "Automation recurrence should live beside automation records.")
        XCTAssertTrue(automationText.contains("nextRun(after"), "Automation recurrence scheduling should stay with recurrence records.")
        XCTAssertTrue(automationText.contains("sortedForDisplay"), "Automation display sorting should stay with automation records.")
        XCTAssertFalse(modelsText.contains("public enum QuillAutomationKind"), "General domain models should not own automation records.")
        XCTAssertFalse(modelsText.contains("public enum QuillAutomationStatus"), "General domain models should not own automation status.")
        XCTAssertFalse(modelsText.contains("public enum QuillAutomationScheduleKind"), "General domain models should not own automation schedule records.")
        XCTAssertFalse(modelsText.contains("public struct QuillAutomationRecurrence"), "General domain models should not own automation recurrence.")
        XCTAssertFalse(modelsText.contains("sortedForDisplay(_ automations"), "General domain models should not own automation sorting.")
    }

    func testProjectModelsLiveOutsideGeneralDomainModels() throws {
        let modelsText = try Self.coreSourceText(named: "Models.swift")
        let projectText = try Self.coreSourceText(named: "ProjectModels.swift")

        XCTAssertTrue(projectText.contains("public enum ProjectConnectionKind"), "Project connection kinds should live in a focused core file.")
        XCTAssertTrue(projectText.contains("public struct ProjectConnection"), "Project connection parsing and display should live beside project records.")
        XCTAssertTrue(projectText.contains("parseSSH"), "SSH project parsing should stay with project connection records.")
        XCTAssertTrue(projectText.contains("public struct ProjectRef"), "Project references should live in the project model boundary.")
        XCTAssertTrue(projectText.contains("public struct LocalEnvironmentAction"), "Local environment actions should live beside project records.")
        XCTAssertTrue(projectText.contains("public struct ProjectExtensionManifest"), "Project extension manifests should live beside project records.")
        XCTAssertFalse(modelsText.contains("public enum ProjectConnectionKind"), "General domain models should not own project connection kinds.")
        XCTAssertFalse(modelsText.contains("public struct ProjectConnection"), "General domain models should not own project connection records.")
        XCTAssertFalse(modelsText.contains("parseSSH"), "General domain models should not own SSH project parsing.")
        XCTAssertFalse(modelsText.contains("public struct ProjectRef"), "General domain models should not own project references.")
        XCTAssertFalse(modelsText.contains("public struct LocalEnvironmentAction"), "General domain models should not own local environment actions.")
        XCTAssertFalse(modelsText.contains("public struct ProjectExtensionManifest"), "General domain models should not own project extension manifests.")
    }

    func testAgentToolStepRunnerLivesOutsideAgentRunnerFile() throws {
        let agentText = try Self.agentSourceText(named: "Agent.swift")
        let runnerText = try Self.agentSourceText(named: "AgentToolStepRunner.swift")

        XCTAssertTrue(runnerText.contains("enum AgentToolStep"), "Tool-step state should live beside the extracted runner.")
        XCTAssertTrue(runnerText.contains("func runToolStep"), "Tool-step execution should live in a focused runner extension.")
        XCTAssertTrue(runnerText.contains("appendQueuedEvent"), "Tool lifecycle transcript events should be owned by the tool-step runner.")
        XCTAssertTrue(runnerText.contains("SafetyReview"), "Safety-review blocking copy should stay with tool-step execution.")
        XCTAssertTrue(agentText.contains("runToolStep("), "AgentRunner should delegate individual tool-step execution.")
        XCTAssertFalse(agentText.contains("private func runToolStep"), "Agent.swift should not own individual tool-step execution.")
        XCTAssertFalse(agentText.contains("kind: .toolQueued"), "Agent.swift should not own tool lifecycle event emission.")
        XCTAssertFalse(agentText.contains("Tool is not available in this workspace"), "Agent.swift should not own unavailable-tool result copy.")
    }

    func testWorkspaceModelDelegatesAutomationStateMutations() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let modelAutomationText = try Self.appSourceText(named: "WorkspaceModelAutomations.swift")
        let automationText = try Self.appSourceText(named: "WorkspaceAutomationEngine.swift")

        XCTAssertTrue(modelAutomationText.contains("extension QuillCodeWorkspaceModel"), "Automation model API should live in a focused workspace model extension.")
        XCTAssertTrue(automationText.contains("enum WorkspaceAutomationStateReducer"), "Automation state mutation should live in a focused reducer.")
        XCTAssertTrue(automationText.contains("struct WorkspaceAutomationStateMutation"), "Automation state mutations should return typed mutation results.")
        XCTAssertTrue(automationText.contains("static func setItems"), "Automation sorting and visibility preservation should be reducer-owned.")
        XCTAssertTrue(automationText.contains("static func createThreadFollowUp"), "Thread follow-up creation should be reducer-owned.")
        XCTAssertTrue(automationText.contains("static func createWorkspaceSchedule"), "Workspace schedule creation should be reducer-owned.")
        XCTAssertTrue(automationText.contains("static func updateStatus"), "Automation status mutation should be reducer-owned.")
        XCTAssertTrue(automationText.contains("static func delete("), "Automation deletion should be reducer-owned.")
        XCTAssertTrue(automationText.contains("static func replace("), "Automation replacement should be reducer-owned.")
        XCTAssertTrue(modelAutomationText.contains("WorkspaceAutomationStateReducer.setItems"), "WorkspaceModel automation extension should delegate automation item setting.")
        XCTAssertTrue(modelAutomationText.contains("WorkspaceAutomationStateReducer.createThreadFollowUp"), "WorkspaceModel automation extension should delegate thread follow-up creation.")
        XCTAssertTrue(modelAutomationText.contains("WorkspaceAutomationStateReducer.createWorkspaceSchedule"), "WorkspaceModel automation extension should delegate workspace schedule creation.")
        XCTAssertTrue(modelAutomationText.contains("WorkspaceAutomationStateReducer.updateStatus"), "WorkspaceModel automation extension should delegate status changes.")
        XCTAssertTrue(modelAutomationText.contains("WorkspaceAutomationStateReducer.delete"), "WorkspaceModel automation extension should delegate deletion.")
        XCTAssertTrue(modelAutomationText.contains("WorkspaceAutomationStateReducer.replace"), "WorkspaceModel automation extension should delegate replacement.")
        XCTAssertFalse(modelText.contains("public func createThreadFollowUpAutomation"), "WorkspaceModel.swift should not own automation scheduling APIs.")
        XCTAssertFalse(modelText.contains("public func createWorkspaceScheduleAutomation"), "WorkspaceModel.swift should not own workspace-check scheduling APIs.")
        XCTAssertFalse(modelText.contains("public func runDueAutomations"), "WorkspaceModel.swift should not own automation-run orchestration.")
        XCTAssertFalse(modelText.contains("setAutomations(automations.items + [automation])"), "WorkspaceModel should not append automation records inline.")
        XCTAssertFalse(modelText.contains("QuillAutomation.sortedForDisplay(items)"), "WorkspaceModel should not own automation display sorting.")
        XCTAssertFalse(modelText.contains("automations.items[index].status"), "WorkspaceModel should not mutate automation status inline.")
        XCTAssertFalse(modelText.contains("automations.items.removeAll"), "WorkspaceModel should not delete automation records inline.")
    }

    func testWorkspaceSurfaceDelegatesAutomationsSurfaceBuilding() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceAutomationsSurfaceBuilder.swift")

        XCTAssertTrue(builderText.contains("struct WorkspaceAutomationsSurfaceBuilder"), "Automation pane assembly should live in a focused builder.")
        XCTAssertTrue(builderText.contains("func surface() -> WorkspaceAutomationsSurface"), "Automation pane assembly should be directly testable.")
        XCTAssertTrue(builderText.contains("hasSelectedThread"), "Thread follow-up command availability should be builder-owned.")
        XCTAssertTrue(builderText.contains("hasSelectedProject"), "Workspace schedule command availability should be builder-owned.")
        XCTAssertTrue(surfaceText.contains("WorkspaceAutomationsSurfaceBuilder("), "WorkspaceSurface should delegate automation pane assembly.")
        XCTAssertFalse(surfaceText.contains("automationCreateThreadFollowUp"), "WorkspaceSurface should not build automation follow-up commands inline.")
        XCTAssertFalse(surfaceText.contains("automationCreateWorkspaceSchedule"), "WorkspaceSurface should not build automation schedule commands inline.")
        XCTAssertFalse(surfaceText.contains("automationScheduleThreadFollowUpCommands"), "WorkspaceSurface should not build thread schedule command variants inline.")
        XCTAssertFalse(surfaceText.contains("automationScheduleWorkspaceScheduleCommands"), "WorkspaceSurface should not build workspace schedule command variants inline.")
    }

    func testWorkspaceModelDelegatesSidebarSelectionTransitions() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let selectionText = try Self.appSourceText(named: "WorkspaceSidebarSelectionEngine.swift")
        let bulkPlannerText = try Self.appSourceText(named: "WorkspaceSidebarBulkActionPlanner.swift")
        let bulkExecutorText = try Self.appSourceText(named: "WorkspaceSidebarBulkActionExecutor.swift")

        XCTAssertTrue(selectionText.contains("public struct SidebarSelectionState"), "Sidebar selection state should live beside the focused reducer.")
        XCTAssertTrue(selectionText.contains("struct WorkspaceSidebarSelectionEngine"), "Sidebar selection transitions should live in a focused reducer.")
        XCTAssertTrue(selectionText.contains("static func start"), "Selection start should be directly testable.")
        XCTAssertTrue(selectionText.contains("static func selectAll"), "Select-all behavior should be directly testable.")
        XCTAssertTrue(selectionText.contains("static func toggle"), "Selection toggles should be directly testable.")
        XCTAssertTrue(selectionText.contains("static func resolve"), "Stale-ID pruning and sidebar ordering should be directly testable.")
        XCTAssertTrue(modelText.contains("WorkspaceSidebarSelectionEngine.start"), "WorkspaceModel should delegate selection start.")
        XCTAssertTrue(modelText.contains("WorkspaceSidebarSelectionEngine.selectAll"), "WorkspaceModel should delegate select-all.")
        XCTAssertTrue(modelText.contains("WorkspaceSidebarSelectionEngine.toggle"), "WorkspaceModel should delegate selection toggles.")
        XCTAssertTrue(modelText.contains("WorkspaceSidebarSelectionEngine.resolve"), "WorkspaceModel should delegate stale-ID pruning and ordering.")
        XCTAssertTrue(bulkPlannerText.contains("struct WorkspaceSidebarBulkActionPlanner"), "Sidebar bulk action planning should live in a focused planner.")
        XCTAssertTrue(bulkPlannerText.contains("static func plan"), "Sidebar bulk action plans should be directly testable.")
        XCTAssertTrue(bulkPlannerText.contains("enum FollowUpSelection"), "Bulk action selection follow-up policy should be explicit.")
        XCTAssertTrue(modelText.contains("WorkspaceSidebarBulkActionPlanner.plan"), "WorkspaceModel should delegate bulk action target planning.")
        XCTAssertTrue(bulkExecutorText.contains("struct WorkspaceSidebarBulkActionExecutor"), "Sidebar bulk action execution should live in a focused executor.")
        XCTAssertTrue(bulkExecutorText.contains("static func execute"), "Sidebar bulk mutations should be directly testable.")
        XCTAssertTrue(modelText.contains("WorkspaceSidebarBulkActionExecutor.execute"), "WorkspaceModel should delegate bulk action execution.")
        XCTAssertFalse(modelText.contains("public struct SidebarSelectionState"), "WorkspaceModel should not own sidebar selection state.")
        XCTAssertFalse(modelText.contains("selectedThreadIDs.insert"), "WorkspaceModel should not mutate sidebar selection sets directly.")
        XCTAssertFalse(modelText.contains("selectedThreadIDs.remove"), "WorkspaceModel should not mutate sidebar selection sets directly.")
        XCTAssertFalse(modelText.contains("selectedThreadIDs.intersection"), "WorkspaceModel should not prune sidebar selection sets directly.")
        XCTAssertFalse(modelText.contains("let ids = selectedSidebarThreadIDs()"), "WorkspaceModel should not inline bulk selected-ID planning.")
        XCTAssertFalse(modelText.contains("case .pin(let ids):"), "WorkspaceModel should not execute sidebar bulk pin mutations inline.")
        XCTAssertFalse(modelText.contains("WorkspaceThreadLifecycleEngine.archiveThreads"), "WorkspaceModel should not execute sidebar bulk archive mutations inline.")
        XCTAssertFalse(modelText.contains("WorkspaceThreadLifecycleEngine.unarchiveThreads"), "WorkspaceModel should not execute sidebar bulk unarchive mutations inline.")
        XCTAssertFalse(modelText.contains("WorkspaceThreadLifecycleEngine.deleteThreads"), "WorkspaceModel should not execute sidebar bulk delete mutations inline.")
    }

    func testSidebarRowActionsUseSharedPlannerAndExecutor() throws {
        let workspaceViewText = try Self.appSourceText(named: "WorkspaceSwiftUIView.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceSidebarRowActionPlanner.swift")
        let desktopControllerText = try Self.desktopSourceText(named: "QuillCodeDesktopController.swift")

        XCTAssertTrue(plannerText.contains("enum WorkspaceThreadRowMutation"), "Thread row mutations should have typed values.")
        XCTAssertTrue(plannerText.contains("enum WorkspaceProjectRowMutation"), "Project row mutations should have typed values.")
        XCTAssertTrue(plannerText.contains("struct WorkspaceSidebarRowActionPlanner"), "Sidebar row action planning should live in a focused planner.")
        XCTAssertTrue(plannerText.contains("struct WorkspaceSidebarRowMutationExecutor"), "Sidebar row mutations should execute through a focused desktop/model boundary.")
        XCTAssertTrue(workspaceViewText.contains("WorkspaceSidebarRowActionPlanner("), "WorkspaceSwiftUIView should delegate row action planning.")
        XCTAssertTrue(workspaceViewText.contains("handleSidebarRowAction"), "WorkspaceSwiftUIView should execute typed row actions.")
        XCTAssertTrue(desktopControllerText.contains("WorkspaceSidebarRowMutationExecutor.execute"), "Desktop controller should delegate row mutations.")
        XCTAssertFalse(workspaceViewText.contains("action.kind == .rename"), "WorkspaceSwiftUIView should not inline rename row lookup.")
        XCTAssertFalse(workspaceViewText.contains("surface.sidebar.items.first(where:"), "WorkspaceSwiftUIView should not lookup thread row titles directly.")
        XCTAssertFalse(workspaceViewText.contains("surface.projects.items.first(where:"), "WorkspaceSwiftUIView should not lookup project row names directly.")
        XCTAssertFalse(desktopControllerText.contains("switch action.kind"), "Desktop controller should not switch over row action kinds.")
    }

    func testSidebarCommandPresentationIsSharedByNativeAndHTMLSurfaces() throws {
        let presentationText = try Self.appSourceText(named: "QuillCodeSidebarCommandPresentation.swift")
        let adapterText = try Self.appSourceText(named: "QuillCodeSidebarCommandAdapter.swift")
        let sidebarText = try Self.appSourceText(named: "QuillCodeSidebarView.swift")
        let threadListText = try Self.appSourceText(named: "QuillCodeSidebarThreadListView.swift")
        let threadRowText = try Self.appSourceText(named: "QuillCodeSidebarThreadRowView.swift")
        let projectListText = try Self.appSourceText(named: "QuillCodeProjectListView.swift")
        let htmlSidebarText = try Self.appSourceText(named: "WorkspaceHTMLSidebarRenderer.swift")
        let iconCatalogText = try Self.appSourceText(named: "QuillCodeCommandIconCatalog.swift")

        XCTAssertTrue(presentationText.contains("struct QuillCodeSidebarCommandPresentation"), "Sidebar command labels and icons should live in one focused presentation helper.")
        XCTAssertTrue(presentationText.contains("QuillCodeSidebarCommandMetadata"), "Sidebar command label/icon/test metadata should share one command table.")
        XCTAssertTrue(presentationText.contains("metadataByCommandID"), "Sidebar command presentation should centralize command metadata.")
        XCTAssertTrue(presentationText.contains("static let primaryCommandIDs"), "Primary sidebar command order should be explicit.")
        XCTAssertTrue(presentationText.contains("struct QuillCodeSidebarCommandGroup"), "Sidebar utility grouping should be a focused contract.")
        XCTAssertTrue(presentationText.contains("static let utilityCommandGroups"), "Utility sidebar command grouping should be explicit.")
        XCTAssertTrue(presentationText.contains("static var utilityCommandIDs"), "Utility sidebar command order should be derived from explicit groups.")
        XCTAssertTrue(presentationText.contains("visibleUtilityCommandGroups"), "Utility sidebar filtering should be shared by native and HTML renderers.")
        XCTAssertTrue(presentationText.contains("static func displayTitle"), "Sidebar command display titles should be shared.")
        XCTAssertTrue(presentationText.contains("QuillCodeCommandIconCatalog.systemImage"), "Native sidebar command icons should delegate to the shared icon catalog.")
        XCTAssertTrue(iconCatalogText.contains("enum QuillCodeCommandIconCatalog"), "Command icon mapping should live in one focused catalog.")
        XCTAssertTrue(presentationText.contains("static func htmlIconToken"), "HTML sidebar icon tokens should be shared.")
        XCTAssertTrue(sidebarText.contains("QuillCodeSidebarThreadListView"), "Native sidebar shell should delegate thread list and row rendering.")
        XCTAssertTrue(sidebarText.contains("QuillCodeProjectListView"), "Native sidebar shell should delegate project list and row rendering.")
        XCTAssertTrue(threadListText.contains("struct QuillCodeSidebarThreadListView"), "Thread list rendering should live in a focused native sidebar file.")
        XCTAssertTrue(threadListText.contains("QuillCodeSidebarThreadRowView"), "Thread list rendering should compose the focused thread row view.")
        XCTAssertTrue(threadRowText.contains("struct QuillCodeSidebarThreadRowView"), "Thread row rendering should live in a focused native sidebar file.")
        XCTAssertTrue(projectListText.contains("struct QuillCodeProjectListView"), "Project list rendering should live in a focused native sidebar file.")
        XCTAssertTrue(projectListText.contains("QuillCodeProjectRowView"), "Project row rendering should live beside project list rendering.")
        XCTAssertTrue(sidebarText.contains("QuillCodeSidebarCommandPresentation.primaryCommandIDs"), "Native sidebar should consume shared primary command ordering.")
        XCTAssertTrue(sidebarText.contains("QuillCodeSidebarCommandPresentation.visibleUtilityCommandGroups"), "Native sidebar should consume shared utility command groups.")
        XCTAssertTrue(sidebarText.contains("QuillCodeSidebarCommandPresentation.displayTitle"), "Native sidebar should consume shared labels.")
        XCTAssertTrue(sidebarText.contains("QuillCodeSidebarCommandPresentation.systemImage"), "Native sidebar should consume shared SF Symbols.")
        XCTAssertTrue(adapterText.contains("enum QuillCodeSidebarCommandAdapter"), "Sidebar command payload construction should live in a focused adapter.")
        XCTAssertTrue(sidebarText.contains("QuillCodeSidebarCommandAdapter.workspaceCommand") || threadListText.contains("QuillCodeSidebarCommandAdapter.workspaceCommand"), "Native sidebar should use the shared command adapter for bulk actions.")
        XCTAssertTrue(threadRowText.contains("QuillCodeSidebarCommandAdapter.toggleSelectionCommand"), "Native sidebar thread rows should use the shared command adapter for selection toggles.")
        XCTAssertTrue(htmlSidebarText.contains("renderPrimaryActions"), "HTML sidebar renderer should build primary sidebar actions through a helper.")
        XCTAssertTrue(htmlSidebarText.contains("renderUtilityActions"), "HTML sidebar renderer should build utility menu actions through a helper.")
        XCTAssertTrue(htmlSidebarText.contains("QuillCodeSidebarCommandPresentation.primaryCommandIDs"), "HTML sidebar renderer should consume shared primary command ordering.")
        XCTAssertTrue(htmlSidebarText.contains("QuillCodeSidebarCommandPresentation.visibleUtilityCommandGroups"), "HTML sidebar renderer should consume shared utility command groups.")
        XCTAssertTrue(htmlSidebarText.contains("QuillCodeSidebarCommandPresentation.htmlIconToken"), "HTML sidebar renderer should consume shared icon tokens.")
        XCTAssertFalse(sidebarText.contains("struct QuillCodeSidebarThreadRowView"), "Native sidebar shell should not own thread row rendering.")
        XCTAssertFalse(threadListText.contains("private struct QuillCodeSidebarThreadRowView"), "Native sidebar thread list should not own thread row rendering.")
        XCTAssertFalse(sidebarText.contains("struct QuillCodeProjectRowView"), "Native sidebar shell should not own project row rendering.")
        XCTAssertFalse(sidebarText.contains("private func displayTitle"), "Native sidebar should not maintain a second label map.")
        XCTAssertFalse(sidebarText.contains("private func systemImage"), "Native sidebar should not maintain a second icon map.")
        XCTAssertFalse(presentationText.contains("switch commandID"), "Sidebar command presentation should not repeat command-ID switches for label/icon/test metadata.")
        XCTAssertFalse(sidebarText.contains("WorkspaceCommandSurface("), "Native sidebar should not duplicate command payload construction.")
        XCTAssertFalse(htmlSidebarText.contains(#"data-icon="plugins">Plugins"#), "HTML sidebar renderer should not hard-code sidebar plugin markup.")
    }

    func testNativeSidebarDelegatesProjectListRendering() throws {
        let sidebarText = try Self.appSourceText(named: "QuillCodeSidebarView.swift")
        let projectListText = try Self.appSourceText(named: "QuillCodeProjectListView.swift")

        XCTAssertTrue(sidebarText.contains("QuillCodeProjectListView("), "Native sidebar should compose a focused project-list view.")
        XCTAssertTrue(projectListText.contains("struct QuillCodeProjectListView"), "Native project-list rendering should live in a focused file.")
        XCTAssertTrue(projectListText.contains("struct QuillCodeProjectRowView"), "Native project-row rendering should live beside the project-list view.")
        XCTAssertTrue(projectListText.contains("maxProjectListHeight"), "Project rows should have an explicit scroll boundary so utility controls stay reachable.")
        XCTAssertFalse(sidebarText.contains("struct QuillCodeProjectRowView"), "Native sidebar should not own project-row rendering.")
        XCTAssertFalse(sidebarText.contains("maxProjectListHeight"), "Native sidebar should not own project-list sizing policy.")
    }

    func testWorkspaceSwiftUIViewDelegatesTranscriptFindAndContextBanner() throws {
        let shellText = try Self.appSourceText(named: "WorkspaceSwiftUIView.swift")
        let mainPaneText = try Self.appSourceText(named: "QuillCodeWorkspaceMainPaneView.swift")
        let transcriptText = try Self.appSourceText(named: "QuillCodeTranscriptView.swift")
        let findText = try Self.appSourceText(named: "QuillCodeTranscriptFindView.swift")
        let contextBannerText = try Self.appSourceText(named: "QuillCodeContextBannerView.swift")

        XCTAssertTrue(mainPaneText.contains("struct QuillCodeWorkspaceMainPaneView"), "Workspace center-pane layout should live in a focused view file.")
        XCTAssertTrue(transcriptText.contains("struct QuillCodeTranscriptView"), "Transcript layout should live in a focused view file.")
        XCTAssertTrue(transcriptText.contains("QuillCodeTranscriptFindBar"), "Transcript layout should compose the focused Find bar.")
        XCTAssertTrue(transcriptText.contains("QuillCodeContextBannerView"), "Transcript layout should compose the focused context banner.")
        XCTAssertTrue(transcriptText.contains("QuillCodeRuntimeIssueView"), "Transcript layout should own runtime issue placement.")
        XCTAssertTrue(transcriptText.contains("QuillCodeReviewPaneView"), "Transcript layout should own review placement.")
        XCTAssertTrue(transcriptText.contains("QuillCodeToolCardView"), "Transcript layout should own tool-card timeline placement.")
        XCTAssertTrue(findText.contains("struct QuillCodeTranscriptFindMatch"), "Transcript Find matching should live in a focused Find file.")
        XCTAssertTrue(findText.contains("struct QuillCodeTranscriptFindBar"), "Transcript Find bar should live in a focused Find file.")
        XCTAssertTrue(contextBannerText.contains("struct QuillCodeContextBannerView"), "Context banner rendering should live in a focused banner file.")
        XCTAssertTrue(shellText.contains("QuillCodeWorkspaceMainPaneView"), "Workspace shell should compose the extracted center-pane view.")
        XCTAssertTrue(mainPaneText.contains("QuillCodeTranscriptView"), "Workspace center pane should compose the extracted transcript view.")
        XCTAssertFalse(shellText.contains("struct QuillCodeTranscriptView"), "Workspace shell should not own transcript layout.")
        XCTAssertFalse(shellText.contains("struct QuillCodeTranscriptFindMatch"), "Workspace shell should not own transcript Find matching.")
        XCTAssertFalse(shellText.contains("struct QuillCodeTranscriptFindBar"), "Workspace shell should not own transcript Find UI.")
        XCTAssertFalse(shellText.contains("struct QuillCodeContextBannerView"), "Workspace shell should not own context banner UI.")
        XCTAssertFalse(shellText.contains("QuillCodeRuntimeIssueView"), "Workspace shell should not own runtime issue transcript placement.")
        XCTAssertFalse(shellText.contains("QuillCodeReviewPaneView"), "Workspace shell should not own review transcript placement.")
        XCTAssertFalse(shellText.contains("QuillCodeToolCardView"), "Workspace shell should not own tool-card timeline placement.")
    }

    func testNativeReviewPaneDelegatesFileHunkAndLineRendering() throws {
        let paneText = try Self.appSourceText(named: "QuillCodeReviewPaneView.swift")
        let fileRowText = try Self.appSourceText(named: "QuillCodeReviewFileRowView.swift")
        let hunkText = try Self.appSourceText(named: "QuillCodeReviewHunkView.swift")
        let lineText = try Self.appSourceText(named: "QuillCodeReviewLineRowView.swift")
        let actionText = try Self.appSourceText(named: "QuillCodeReviewActionButton.swift")

        XCTAssertTrue(paneText.contains("struct QuillCodeReviewPaneView"), "Review pane shell should remain a focused root view.")
        XCTAssertTrue(paneText.contains("QuillCodeReviewFileRowView("), "Native review pane should compose focused file-row rendering.")
        XCTAssertTrue(fileRowText.contains("struct QuillCodeReviewFileRowView"), "Review file-row rendering should live in a focused file.")
        XCTAssertTrue(fileRowText.contains("QuillCodeReviewHunkView("), "Review file rows should delegate hunk rendering.")
        XCTAssertTrue(hunkText.contains("struct QuillCodeReviewHunkView"), "Review hunk rendering should live in a focused file.")
        XCTAssertTrue(hunkText.contains("QuillCodeReviewLineRowView("), "Review hunk rows should delegate line rendering.")
        XCTAssertTrue(lineText.contains("struct QuillCodeReviewLineRowView"), "Review line rendering should live in a focused file.")
        XCTAssertTrue(lineText.contains("markerColor"), "Line marker styling should live beside line-row rendering.")
        XCTAssertTrue(lineText.contains("lineBackground"), "Line background styling should live beside line-row rendering.")
        XCTAssertTrue(actionText.contains("struct QuillCodeReviewActionButton"), "Review action buttons should live in a focused file.")
        XCTAssertFalse(paneText.contains("struct QuillCodeReviewFileRowView"), "Native review pane should not own file-row rendering.")
        XCTAssertFalse(paneText.contains("struct QuillCodeReviewHunkView"), "Native review pane should not own hunk rendering.")
        XCTAssertFalse(paneText.contains("struct QuillCodeReviewLineRowView"), "Native review pane should not own line rendering.")
        XCTAssertFalse(paneText.contains("struct QuillCodeReviewActionButton"), "Native review pane should not own action-button rendering.")
    }

    func testWorkspaceSwiftUIViewDelegatesSheetPresentation() throws {
        let shellText = try Self.appSourceText(named: "WorkspaceSwiftUIView.swift")
        let sheetsText = try Self.appSourceText(named: "QuillCodeWorkspaceSheets.swift")
        let renameDialogsText = try Self.appSourceText(named: "QuillCodeWorkspaceDialogs.swift")
        let commandPaletteText = try Self.appSourceText(named: "QuillCodeCommandPaletteDialog.swift")
        let searchShortcutText = try Self.appSourceText(named: "QuillCodeSearchAndShortcutDialogs.swift")
        let worktreeDialogsText = try Self.appSourceText(named: "QuillCodeWorktreeDialogs.swift")
        let dialogChromeText = try Self.appSourceText(named: "QuillCodeDialogChrome.swift")

        XCTAssertTrue(sheetsText.contains("struct QuillCodeWorkspaceSheetsModifier"), "Workspace sheet presentation should live in a focused modifier.")
        XCTAssertTrue(sheetsText.contains("func quillCodeWorkspaceSheets("), "Workspace sheet presentation should expose one root-shell modifier.")
        XCTAssertTrue(sheetsText.contains("QuillCodeSettingsView("), "Settings sheet wiring should live in the sheet presenter.")
        XCTAssertTrue(sheetsText.contains("QuillCodeSearchView("), "Search sheet wiring should live in the sheet presenter.")
        XCTAssertTrue(sheetsText.contains("QuillCodeKeyboardShortcutsView("), "Keyboard shortcut sheet wiring should live in the sheet presenter.")
        XCTAssertTrue(sheetsText.contains("QuillCodeCommandPaletteView("), "Command palette sheet wiring should live in the sheet presenter.")
        XCTAssertTrue(sheetsText.contains("QuillCodeWorktreeCreateView("), "Worktree create sheet wiring should live in the sheet presenter.")
        XCTAssertTrue(sheetsText.contains("QuillCodeWorktreeRemoveView("), "Worktree remove sheet wiring should live in the sheet presenter.")
        XCTAssertTrue(sheetsText.contains("QuillCodeThreadRenameView("), "Thread rename sheet wiring should live in the sheet presenter.")
        XCTAssertTrue(sheetsText.contains("QuillCodeProjectRenameView("), "Project rename sheet wiring should live in the sheet presenter.")
        XCTAssertTrue(commandPaletteText.contains("struct QuillCodeCommandPaletteView"), "Command palette UI should live in its focused dialog file.")
        XCTAssertTrue(commandPaletteText.contains("QuillCodeCommandIconCatalog.systemImage"), "Command palette rows should consume the shared command icon catalog.")
        XCTAssertFalse(commandPaletteText.contains("enum QuillCodeCommandIcon"), "Command palette should not maintain a duplicate command icon map.")
        XCTAssertTrue(searchShortcutText.contains("struct QuillCodeSearchView"), "Chat search dialog UI should live with shortcut/search dialogs.")
        XCTAssertTrue(searchShortcutText.contains("struct QuillCodeKeyboardShortcutsView"), "Keyboard shortcut dialog UI should live with shortcut/search dialogs.")
        XCTAssertTrue(worktreeDialogsText.contains("struct QuillCodeWorktreeCreateView"), "Worktree create UI should live in the worktree dialog file.")
        XCTAssertTrue(worktreeDialogsText.contains("struct QuillCodeWorktreeRemoveView"), "Worktree remove UI should live in the worktree dialog file.")
        XCTAssertTrue(dialogChromeText.contains("struct QuillCodeDialogHeader"), "Shared dialog chrome should live in one reusable file.")
        XCTAssertTrue(renameDialogsText.contains("struct QuillCodeThreadRenameView"), "Rename sheets should remain in the small workspace rename dialog file.")
        XCTAssertFalse(renameDialogsText.contains("struct QuillCodeCommandPaletteView"), "Workspace rename dialogs should not own command palette UI.")
        XCTAssertFalse(renameDialogsText.contains("struct QuillCodeSearchView"), "Workspace rename dialogs should not own search UI.")
        XCTAssertFalse(renameDialogsText.contains("struct QuillCodeWorktreeCreateView"), "Workspace rename dialogs should not own worktree UI.")
        XCTAssertTrue(shellText.contains(".quillCodeWorkspaceSheets("), "Workspace shell should compose the extracted sheet presenter.")
        XCTAssertFalse(shellText.contains("QuillCodeSettingsView("), "Workspace shell should not own settings sheet wiring.")
        XCTAssertFalse(shellText.contains("QuillCodeSearchView("), "Workspace shell should not own search sheet wiring.")
        XCTAssertFalse(shellText.contains("QuillCodeCommandPaletteView("), "Workspace shell should not own command palette sheet wiring.")
        XCTAssertFalse(shellText.contains("QuillCodeWorktreeCreateView("), "Workspace shell should not own worktree create sheet wiring.")
        XCTAssertFalse(shellText.contains("QuillCodeThreadRenameView("), "Workspace shell should not own thread rename sheet wiring.")
        XCTAssertFalse(shellText.contains(".sheet(isPresented:"), "Workspace shell should not own sheet presentation modifiers.")
        XCTAssertFalse(shellText.contains(".sheet(item:"), "Workspace shell should not own item sheet presentation modifiers.")
    }

    func testNativeSettingsDelegatesFocusedViewsAndDraftState() throws {
        let settingsText = try Self.appSourceText(named: "QuillCodeSettingsView.swift")
        let computerUseText = try Self.appSourceText(named: "QuillCodeComputerUseSettingsCard.swift")
        let runtimeIssueText = try Self.appSourceText(named: "QuillCodeRuntimeIssueView.swift")
        let draftText = try Self.appSourceText(named: "QuillCodeSettingsDraft.swift")

        XCTAssertTrue(settingsText.contains("struct QuillCodeSettingsView"), "Settings shell should remain in the settings view file.")
        XCTAssertTrue(settingsText.contains("QuillCodeComputerUseSettingsCard("), "Settings shell should compose focused Computer Use onboarding.")
        XCTAssertTrue(settingsText.contains("QuillCodeRuntimeIssueView("), "Settings shell should compose the focused runtime issue callout.")
        XCTAssertTrue(computerUseText.contains("struct QuillCodeComputerUseSettingsCard"), "Computer Use settings UI should live in a focused file.")
        XCTAssertTrue(computerUseText.contains("struct QuillCodePermissionRow"), "Computer Use permission rows should live beside the Computer Use card.")
        XCTAssertTrue(runtimeIssueText.contains("struct QuillCodeRuntimeIssueView"), "Reusable runtime issue callout should live in a focused file.")
        XCTAssertTrue(draftText.contains("struct QuillCodeSettingsDraft"), "Settings draft/update state should live in a focused file.")
        XCTAssertTrue(draftText.contains("var update: WorkspaceSettingsUpdate"), "Settings draft should own update projection.")
        XCTAssertFalse(settingsText.contains("struct QuillCodeComputerUseSettingsCard"), "Settings shell should not own Computer Use card internals.")
        XCTAssertFalse(settingsText.contains("struct QuillCodePermissionRow"), "Settings shell should not own Computer Use permission rows.")
        XCTAssertFalse(settingsText.contains("struct QuillCodeRuntimeIssueView"), "Settings shell should not own runtime issue callout internals.")
        XCTAssertFalse(settingsText.contains("struct QuillCodeSettingsDraft"), "Settings shell should not own settings draft state.")
    }

    func testWorkspaceModelDelegatesMCPSupportTypes() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let mcpSurfaceText = try Self.appSourceText(named: "QuillCodeMCPSurface.swift")
        let mcpRequestText = try Self.appSourceText(named: "WorkspaceMCPRequests.swift")
        let mcpRuntimeText = try Self.appSourceText(named: "WorkspaceMCPRuntime.swift")
        let mcpLauncherText = try Self.appSourceText(named: "WorkspaceMCPServerLauncher.swift")
        let mcpCatalogText = try Self.appSourceText(named: "WorkspaceMCPToolCatalog.swift")

        XCTAssertTrue(mcpSurfaceText.contains("public struct ExtensionsState"), "MCP extension state should live in a focused surface file.")
        XCTAssertTrue(mcpSurfaceText.contains("public enum MCPServerLifecycleStatus"), "MCP lifecycle status should live in a focused surface file.")
        XCTAssertTrue(mcpSurfaceText.contains("public struct MCPServerProbeSummary"), "MCP probe summary should live in a focused surface file.")
        XCTAssertTrue(mcpRequestText.contains("struct MCPToolCallRequest"), "MCP tool-call parsing should live in a focused request parser file.")
        XCTAssertTrue(mcpRequestText.contains("struct MCPResourceReadRequest"), "MCP resource parsing should live in a focused request parser file.")
        XCTAssertTrue(mcpRequestText.contains("struct MCPPromptGetRequest"), "MCP prompt parsing should live in a focused request parser file.")
        XCTAssertTrue(mcpRuntimeText.contains("final class WorkspaceMCPRuntime"), "MCP process lifecycle should live in a focused runtime file.")
        XCTAssertTrue(mcpRuntimeText.contains("private final class WorkspaceMCPProcessHandle"), "MCP process handles should be private to the runtime.")
        XCTAssertTrue(mcpLauncherText.contains("protocol WorkspaceMCPServerLaunching"), "MCP process launch should have an injectable launcher protocol.")
        XCTAssertTrue(mcpLauncherText.contains("struct WorkspaceMCPLaunchRequest"), "MCP launch request validation should live beside the launcher.")
        XCTAssertTrue(mcpLauncherText.contains("struct WorkspaceMCPProcessLaunchConfiguration"), "MCP command resolution should live beside the launcher.")
        XCTAssertTrue(mcpLauncherText.contains("struct DefaultWorkspaceMCPServerLauncher"), "Concrete MCP stdio launch should live in a focused launcher.")
        XCTAssertTrue(mcpRuntimeText.contains("private let launcher"), "MCP runtime should delegate server launch through the launcher seam.")
        XCTAssertTrue(mcpRuntimeText.contains("WorkspaceMCPLaunchRequest.make"), "MCP runtime should delegate manifest launch validation to launch request construction.")
        XCTAssertTrue(mcpRuntimeText.contains("launcher.launch("), "MCP runtime should delegate process creation to the launcher.")
        XCTAssertTrue(mcpCatalogText.contains("struct WorkspaceMCPToolCatalog"), "MCP dynamic tool descriptions should live in a focused catalog file.")
        XCTAssertTrue(mcpRuntimeText.contains("WorkspaceMCPToolCatalog("), "MCP runtime should delegate dynamic tool definitions to the catalog.")
        XCTAssertTrue(mcpRuntimeText.contains("static func executionOverride"), "MCP dynamic tool routing should live in the runtime.")
        XCTAssertFalse(modelText.contains("public struct ExtensionsState"), "WorkspaceModel should not own MCP extension state.")
        XCTAssertFalse(modelText.contains("public enum MCPServerLifecycleStatus"), "WorkspaceModel should not own MCP lifecycle state.")
        XCTAssertFalse(modelText.contains("public struct MCPServerProbeSummary"), "WorkspaceModel should not own MCP probe summaries.")
        XCTAssertFalse(modelText.contains("struct MCPToolCallRequest {"), "WorkspaceModel should not own MCP tool-call request parsing.")
        XCTAssertFalse(modelText.contains("struct MCPResourceReadRequest {"), "WorkspaceModel should not own MCP resource request parsing.")
        XCTAssertFalse(modelText.contains("struct MCPPromptGetRequest {"), "WorkspaceModel should not own MCP prompt request parsing.")
        XCTAssertFalse(modelText.contains("MCPServerProcessHandle"), "WorkspaceModel should not own MCP process handles.")
        XCTAssertFalse(modelText.contains("Process()"), "WorkspaceModel should not spawn MCP processes directly.")
        XCTAssertFalse(mcpRuntimeText.contains("Process()"), "WorkspaceMCPRuntime should not construct concrete processes directly.")
        XCTAssertFalse(mcpRuntimeText.contains("MCPStdioProber("), "WorkspaceMCPRuntime should not construct stdio sessions directly.")
        XCTAssertFalse(mcpRuntimeText.contains("URL(fileURLWithPath: \"/usr/bin/env\")"), "WorkspaceMCPRuntime should not resolve launch commands directly.")
        XCTAssertTrue(mcpLauncherText.contains("Process()"), "Concrete process construction should be isolated to the MCP launcher.")
        XCTAssertFalse(modelText.contains("readyMCPToolDescriptions"), "WorkspaceModel should not format MCP tool descriptions directly.")
        XCTAssertFalse(mcpRuntimeText.contains("func readyToolDescriptions"), "MCP runtime should not format MCP tool descriptions directly.")
        XCTAssertFalse(mcpRuntimeText.contains("func readyResourceDescriptions"), "MCP runtime should not format MCP resource descriptions directly.")
        XCTAssertFalse(mcpRuntimeText.contains("func readyPromptDescriptions"), "MCP runtime should not format MCP prompt descriptions directly.")
    }

    func testMCPStdioProberDelegatesCodecAndResultMapping() throws {
        let proberText = try Self.toolsSourceText(named: "MCPStdioProber.swift")
        let codecText = try Self.toolsSourceText(named: "MCPStdioMessageCodec.swift")
        let mapperText = try Self.toolsSourceText(named: "MCPStdioResultMapper.swift")
        let modelsText = try Self.toolsSourceText(named: "MCPStdioModels.swift")
        let definitionsText = try Self.toolsSourceText(named: "MCPToolDefinitions.swift")

        XCTAssertTrue(proberText.contains("public final class MCPStdioProber"), "MCP stdio session orchestration should remain in the prober.")
        XCTAssertTrue(codecText.contains("public enum MCPStdioMessageCodec"), "MCP Content-Length framing should live in a focused codec.")
        XCTAssertTrue(mapperText.contains("enum MCPStdioResultMapper"), "MCP result mapping should live in a focused mapper.")
        XCTAssertTrue(modelsText.contains("public struct MCPServerProbeResult"), "MCP probe result models should live outside the stdio prober.")
        XCTAssertTrue(modelsText.contains("public enum MCPProbeError"), "MCP probe errors should live with the public stdio models.")
        XCTAssertTrue(definitionsText.contains("static let mcpCall"), "MCP tool definitions should live outside the stdio prober.")
        XCTAssertTrue(proberText.contains("MCPStdioMessageCodec.encodeJSONObject"), "MCP prober should delegate outbound framing to the codec.")
        XCTAssertTrue(proberText.contains("MCPStdioResultMapper.toolDescriptors"), "MCP prober should delegate tool schema summaries to the mapper.")
        XCTAssertTrue(proberText.contains("MCPStdioResultMapper.toolResult"), "MCP prober should delegate tool result formatting to the mapper.")
        XCTAssertFalse(proberText.contains("public enum MCPStdioMessageCodec"), "MCP prober should not own stdio frame parsing.")
        XCTAssertFalse(proberText.contains("public struct MCPServerProbeResult"), "MCP prober should not own public probe models.")
        XCTAssertFalse(proberText.contains("public extension ToolDefinition"), "MCP prober should not own static tool definitions.")
        XCTAssertFalse(proberText.contains("private static func schemaArguments"), "MCP prober should not own JSON schema summary formatting.")
        XCTAssertFalse(proberText.contains("private static func toolResult"), "MCP prober should not own ToolResult conversion.")
        XCTAssertFalse(proberText.contains("private static func promptMessageContent"), "MCP prober should not own prompt content flattening.")
    }

    func testWorkspaceSurfaceDelegatesRuntimeIssueBuilding() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceRuntimeIssueBuilder.swift")

        XCTAssertTrue(builderText.contains("struct WorkspaceRuntimeIssueBuilder"), "Runtime issue classification should live in a focused builder.")
        XCTAssertTrue(builderText.contains("static func issue(from error:"), "Runtime error classification should be directly testable.")
        XCTAssertTrue(builderText.contains("static func rateLimitDiagnostics"), "Rate-limit diagnostics should be directly testable.")
        XCTAssertTrue(builderText.contains("static func redactedDiagnosticError"), "Secret redaction should be directly testable.")
        XCTAssertTrue(surfaceText.contains("WorkspaceRuntimeIssueBuilder("), "WorkspaceSurface should delegate runtime issue construction.")
        XCTAssertFalse(surfaceText.contains("static func issue(from error:"), "WorkspaceSurface should not own runtime error classification.")
        XCTAssertFalse(surfaceText.contains("rateLimitDiagnostics(from error:"), "WorkspaceSurface should not own rate-limit diagnostics.")
        XCTAssertFalse(surfaceText.contains("redactedDiagnosticError"), "WorkspaceSurface should not own secret redaction.")
    }

    func testWorkspaceSurfaceDelegatesRuntimeAndExecutionContextContracts() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let runtimeText = try Self.appSourceText(named: "QuillCodeRuntimeSurface.swift")
        let runtimeBuilderText = try Self.appSourceText(named: "WorkspaceRuntimeIssueBuilder.swift")
        let executionBuilderText = try Self.appSourceText(named: "WorkspaceExecutionContextSurfaceBuilder.swift")

        XCTAssertTrue(runtimeText.contains("public enum RuntimeIssueSeverity"), "Runtime issue severity should live with the runtime surface contract.")
        XCTAssertTrue(runtimeText.contains("public enum ExecutionContextKind"), "Execution context kind should live with the runtime surface contract.")
        XCTAssertTrue(runtimeText.contains("public struct ExecutionContextSurface"), "Execution context surface should live beside runtime surface contracts.")
        XCTAssertTrue(runtimeText.contains("public struct RuntimeIssueSurface"), "Runtime issue surface should live beside runtime surface contracts.")
        XCTAssertTrue(runtimeText.contains("public struct RuntimeDiagnosticSurface"), "Runtime diagnostics should live beside runtime surface contracts.")
        XCTAssertTrue(runtimeText.contains("static func local(path:"), "Local execution-context fallback should be directly testable.")
        XCTAssertTrue(runtimeText.contains("static func project"), "Project execution-context mapping should be directly testable.")
        XCTAssertTrue(runtimeText.contains("func withDiagnostics"), "Runtime diagnostics copy semantics should be directly testable.")
        XCTAssertTrue(runtimeBuilderText.contains("RuntimeIssueSurface("), "Runtime issue builder should consume the shared runtime surface contract.")
        XCTAssertTrue(executionBuilderText.contains("ExecutionContextSurface"), "Execution-context builder should consume the shared runtime surface contract.")
        XCTAssertFalse(surfaceText.contains("public enum RuntimeIssueSeverity"), "WorkspaceSurface should not own runtime issue enum contracts.")
        XCTAssertFalse(surfaceText.contains("public enum ExecutionContextKind"), "WorkspaceSurface should not own execution context enum contracts.")
        XCTAssertFalse(surfaceText.contains("public struct ExecutionContextSurface"), "WorkspaceSurface should not own execution context surface contracts.")
        XCTAssertFalse(surfaceText.contains("public struct RuntimeIssueSurface"), "WorkspaceSurface should not own runtime issue surface contracts.")
        XCTAssertFalse(surfaceText.contains("public struct RuntimeDiagnosticSurface"), "WorkspaceSurface should not own runtime diagnostic surface contracts.")
    }

    func testWorkspaceViewDelegatesRuntimeIssueRecoveryPlanning() throws {
        let viewText = try Self.appSourceText(named: "WorkspaceSwiftUIView.swift")
        let mainPaneText = try Self.appSourceText(named: "QuillCodeWorkspaceMainPaneView.swift")
        let plannerText = try Self.appSourceText(named: "QuillCodeRuntimeIssueRecoveryPlanner.swift")

        XCTAssertTrue(plannerText.contains("struct RuntimeIssueRecoveryPlanner"), "Runtime issue recovery routing should live in a focused planner.")
        XCTAssertTrue(plannerText.contains("enum RuntimeIssueRecoveryAction"), "Recovery actions should be explicit instead of view-local closures.")
        XCTAssertTrue(plannerText.contains("case \"Open Settings\", \"Add key\", \"Fix key\""), "Settings recovery labels should be directly testable.")
        XCTAssertTrue(plannerText.contains("case \"Retry\""), "Retry recovery routing should be directly testable.")
        XCTAssertTrue(plannerText.contains("case \"Switch model\""), "Model-switch recovery routing should be directly testable.")
        XCTAssertTrue(viewText.contains("QuillCodeWorkspaceMainPaneView"), "WorkspaceSwiftUIView should delegate center-pane layout and recovery wiring.")
        XCTAssertTrue(mainPaneText.contains("RuntimeIssueRecoveryPlanner(commands:"), "Workspace main pane should delegate runtime issue recovery planning.")
        XCTAssertFalse(viewText.contains("[\"Open Settings\", \"Add key\", \"Fix key\"]"), "WorkspaceSwiftUIView should not own settings recovery labels.")
        XCTAssertFalse(viewText.contains("actionLabel == \"Retry\""), "WorkspaceSwiftUIView should not own retry recovery labels.")
        XCTAssertFalse(viewText.contains("actionLabel == \"Switch model\""), "WorkspaceSwiftUIView should not own model-picker recovery labels.")
    }

    func testWorkspaceViewDelegatesCommandPlanning() throws {
        let viewText = try Self.appSourceText(named: "WorkspaceSwiftUIView.swift")
        let plannerText = try Self.appSourceText(named: "QuillCodeWorkspaceViewCommandPlanner.swift")

        XCTAssertTrue(plannerText.contains("struct WorkspaceViewCommandPlanner"), "Workspace command presentation routing should live in a focused planner.")
        XCTAssertTrue(plannerText.contains("enum WorkspaceViewCommandAction"), "Workspace view command outcomes should be typed and directly testable.")
        XCTAssertTrue(plannerText.contains("case \"settings\", \"computer-use-setup\""), "Settings command routing should be directly testable.")
        XCTAssertTrue(plannerText.contains("case \"thread-rename\""), "Thread rename command routing should be directly testable.")
        XCTAssertTrue(plannerText.contains("case \"project-rename\""), "Project rename command routing should be directly testable.")
        XCTAssertTrue(plannerText.contains("shouldFocusComposer(afterDispatching:"), "Composer focus routing should be directly testable.")
        XCTAssertTrue(viewText.contains("WorkspaceViewCommandPlanner("), "WorkspaceSwiftUIView should delegate command planning.")
        XCTAssertFalse(viewText.contains("command.id == \"settings\""), "WorkspaceSwiftUIView should not own settings command routing.")
        XCTAssertFalse(viewText.contains("command.id == \"computer-use-setup\""), "WorkspaceSwiftUIView should not own Computer Use command routing.")
        XCTAssertFalse(viewText.contains("command.id == \"thread-rename\""), "WorkspaceSwiftUIView should not own thread rename command routing.")
        XCTAssertFalse(viewText.contains("command.id == \"project-rename\""), "WorkspaceSwiftUIView should not own project rename command routing.")
        XCTAssertFalse(viewText.contains("SlashCommandCatalog.insertText(forCommandPaletteID:"), "WorkspaceSwiftUIView should not own command composer-focus routing.")
    }

    func testWorkspaceSurfaceDelegatesSidebarSurfaceContracts() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let projectListText = try Self.appSourceText(named: "QuillCodeProjectListSurface.swift")
        let sidebarText = try Self.appSourceText(named: "QuillCodeThreadSidebarSurface.swift")
        let threadListBuilderText = try Self.appSourceText(named: "QuillCodeSidebarThreadListBuilder.swift")

        XCTAssertTrue(projectListText.contains("public struct ProjectListSurface"), "Project list aggregate records should live in project-list contracts.")
        XCTAssertTrue(projectListText.contains("public struct ProjectItemSurface"), "Project rows should live in project-list contracts.")
        XCTAssertTrue(projectListText.contains("public enum ProjectItemActionKind"), "Project action labels should live in project-list contracts.")
        XCTAssertTrue(projectListText.contains("public struct ProjectItemActionSurface"), "Project action records should live in project-list contracts.")
        XCTAssertTrue(sidebarText.contains("public struct SidebarSurface"), "Thread sidebar aggregate records should live in thread-sidebar contracts.")
        XCTAssertTrue(sidebarText.contains("public struct SidebarItemSurface"), "Thread sidebar item rows should live in thread-sidebar contracts.")
        XCTAssertTrue(sidebarText.contains("public enum SidebarBulkActionKind"), "Thread bulk action labels should live in thread-sidebar contracts.")
        XCTAssertTrue(sidebarText.contains("public struct SidebarBulkActionSurface"), "Thread bulk action command IDs should live in thread-sidebar contracts.")
        XCTAssertTrue(sidebarText.contains("public enum SidebarItemActionKind"), "Thread action labels should live in thread-sidebar contracts.")
        XCTAssertTrue(sidebarText.contains("public struct SidebarItemActionSurface"), "Thread action records should live in thread-sidebar contracts.")
        XCTAssertTrue(sidebarText.contains("filteredItems"), "Sidebar search filtering should be directly testable outside the aggregate workspace surface.")
        XCTAssertTrue(sidebarText.contains("selectionLabel"), "Sidebar selection copy should be directly testable outside the aggregate workspace surface.")
        XCTAssertTrue(sidebarText.contains("SidebarThreadListBuilder(items: items)"), "Sidebar aggregate should delegate thread list derivation.")
        XCTAssertTrue(threadListBuilderText.contains("struct SidebarThreadListBuilder"), "Sidebar list filtering and sectioning should live in a focused helper.")
        XCTAssertTrue(threadListBuilderText.contains("private enum SidebarThreadDateBucket"), "Sidebar date buckets should live with list sectioning.")
        XCTAssertFalse(projectListText.contains("public struct SidebarSurface"), "Project-list contracts should not own thread sidebar records.")
        XCTAssertFalse(projectListText.contains("public struct SidebarItemSurface"), "Project-list contracts should not own thread rows.")
        XCTAssertFalse(projectListText.contains("SidebarThreadListBuilder"), "Project-list contracts should not own thread filtering or sectioning.")
        XCTAssertFalse(sidebarText.contains("public struct ProjectListSurface"), "Thread-sidebar contracts should not own project list records.")
        XCTAssertFalse(sidebarText.contains("public struct ProjectItemSurface"), "Thread-sidebar contracts should not own project rows.")
        XCTAssertFalse(sidebarText.contains("ProjectItemActionSurface"), "Thread-sidebar contracts should not own project actions.")
        XCTAssertFalse(surfaceText.contains("public struct ProjectListSurface"), "WorkspaceSurface should not own project list surface records.")
        XCTAssertFalse(surfaceText.contains("public struct ProjectItemSurface"), "WorkspaceSurface should not own project row records.")
        XCTAssertFalse(surfaceText.contains("public enum ProjectItemActionKind"), "WorkspaceSurface should not own project action labels.")
        XCTAssertFalse(surfaceText.contains("public struct ProjectItemActionSurface"), "WorkspaceSurface should not own project action records.")
        XCTAssertFalse(surfaceText.contains("public struct SidebarSurface"), "WorkspaceSurface should not own sidebar aggregate records.")
        XCTAssertFalse(surfaceText.contains("public struct SidebarItemSurface"), "WorkspaceSurface should not own sidebar item rows.")
        XCTAssertFalse(surfaceText.contains("public enum SidebarBulkActionKind"), "WorkspaceSurface should not own bulk action labels.")
        XCTAssertFalse(surfaceText.contains("public struct SidebarBulkActionSurface"), "WorkspaceSurface should not own bulk action records.")
        XCTAssertFalse(surfaceText.contains("public enum SidebarItemActionKind"), "WorkspaceSurface should not own thread action labels.")
        XCTAssertFalse(surfaceText.contains("public struct SidebarItemActionSurface"), "WorkspaceSurface should not own thread action records.")
        XCTAssertFalse(surfaceText.contains("filteredItems"), "WorkspaceSurface should not own sidebar search filtering.")
        XCTAssertFalse(surfaceText.contains("selectionLabel(count:"), "WorkspaceSurface should not own sidebar selection copy.")
        XCTAssertFalse(sidebarText.contains("private enum SidebarThreadDateBucket"), "Sidebar aggregate should not own date bucketing.")
    }

    func testWorkspaceSurfaceDelegatesNavigationSurfaceBuilding() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceNavigationSurfaceBuilder.swift")

        XCTAssertTrue(surfaceText.contains("WorkspaceNavigationSurfaceBuilder("), "WorkspaceSurface should delegate navigation surface assembly.")
        XCTAssertTrue(builderText.contains("struct WorkspaceNavigationSurfaceBuilder"), "Navigation surface assembly should live in a focused builder.")
        XCTAssertTrue(builderText.contains("ProjectListSurface("), "Project list construction should live in the navigation builder.")
        XCTAssertTrue(builderText.contains("SidebarSurface("), "Sidebar construction should live in the navigation builder.")
        XCTAssertTrue(builderText.contains("SidebarBulkActionSurface"), "Sidebar bulk-action projection should live in the navigation builder.")
        XCTAssertFalse(surfaceText.contains("private func sidebarBulkActions"), "WorkspaceSurface should not own sidebar bulk-action projection.")
        XCTAssertFalse(surfaceText.contains("private func projectItems"), "WorkspaceSurface should not own project row projection.")
        XCTAssertFalse(surfaceText.contains("ProjectListSurface("), "WorkspaceSurface should not construct project lists directly.")
        XCTAssertFalse(surfaceText.contains("SidebarSurface("), "WorkspaceSurface should not construct sidebars directly.")
    }

    func testWorkspaceSurfaceDelegatesCommandSurfaceBuilding() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceCommandSurfaceBuilder.swift")
        let staticCatalogText = try Self.appSourceText(named: "WorkspaceCommandStaticCatalog.swift")
        let threadCatalogText = try Self.appSourceText(named: "WorkspaceThreadCommandCatalog.swift")
        let gitCatalogText = try Self.appSourceText(named: "WorkspaceGitCommandCatalog.swift")
        let projectCatalogText = try Self.appSourceText(named: "WorkspaceProjectCommandCatalog.swift")

        XCTAssertTrue(builderText.contains("struct WorkspaceCommandSurfaceBuilder"), "Command palette construction should live in a focused builder.")
        XCTAssertTrue(builderText.contains("var commands: [WorkspaceCommandSurface]"), "Command builder should expose directly testable command rows.")
        XCTAssertTrue(builderText.contains("WorkspaceThreadCommandCatalog.commands"), "Thread command rows should live in the focused thread catalog.")
        XCTAssertTrue(builderText.contains("WorkspaceGitCommandCatalog.commands"), "Git command rows should live in the focused git catalog.")
        XCTAssertTrue(builderText.contains("WorkspaceProjectCommandCatalog.localActionCommands"), "Project-derived command rows should live in the focused project catalog.")
        XCTAssertTrue(builderText.contains("WorkspaceCommandStaticCatalog.workspaceCommands"), "Static command rows should live in the focused static catalog.")
        XCTAssertTrue(staticCatalogText.contains("enum WorkspaceCommandStaticCatalog"), "Static command rows should live in a focused catalog.")
        XCTAssertTrue(threadCatalogText.contains("enum WorkspaceThreadCommandCatalog"), "Thread command rows should live in a focused catalog.")
        XCTAssertTrue(threadCatalogText.contains("struct WorkspaceThreadCommandAvailability"), "Thread command availability should be a directly testable value.")
        XCTAssertTrue(gitCatalogText.contains("enum WorkspaceGitCommandCatalog"), "Git command rows should live in a focused catalog.")
        XCTAssertTrue(projectCatalogText.contains("enum WorkspaceProjectCommandCatalog"), "Project-derived command rows should live in a focused catalog.")
        XCTAssertTrue(projectCatalogText.contains("static func localActionCommands"), "Local environment action command construction should be isolated in the project catalog.")
        XCTAssertTrue(projectCatalogText.contains("static func mcpLifecycleCommands"), "MCP lifecycle command construction should be isolated in the project catalog.")
        XCTAssertTrue(projectCatalogText.contains("static func extensionUpdateCommands"), "Extension update command construction should be isolated in the project catalog.")
        XCTAssertFalse(builderText.contains("private var localActionCommands"), "Command builder should not own local-action command construction.")
        XCTAssertFalse(builderText.contains("private var mcpLifecycleCommands"), "Command builder should not own MCP lifecycle command construction.")
        XCTAssertFalse(builderText.contains("private var gitCommands"), "Command builder should not own Git command construction.")
        XCTAssertTrue(surfaceText.contains("WorkspaceCommandSurfaceBuilder("), "WorkspaceSurface should delegate command construction.")
        XCTAssertFalse(surfaceText.contains("private func commands() -> [WorkspaceCommandSurface]"), "WorkspaceSurface should not own the command catalog.")
        XCTAssertFalse(surfaceText.contains("let localActionCommands ="), "WorkspaceSurface should not own local-action command construction.")
        XCTAssertFalse(surfaceText.contains("let mcpLifecycleCommands ="), "WorkspaceSurface should not own MCP lifecycle command construction.")
        XCTAssertFalse(surfaceText.contains("let extensionUpdateCommands ="), "WorkspaceSurface should not own extension update command construction.")
    }

    func testWorkspaceSurfaceDelegatesCommandPaletteContract() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let paletteText = try Self.appSourceText(named: "WorkspaceCommandPaletteSurface.swift")
        let rankerText = try Self.appSourceText(named: "WorkspaceCommandPaletteRanker.swift")

        XCTAssertTrue(paletteText.contains("public struct WorkspaceCommandSurface"), "Command surface records should live beside command palette API types.")
        XCTAssertTrue(paletteText.contains("public enum TopBarOverflowCommandCatalog"), "Top-bar overflow command projection should live beside command surfaces.")
        XCTAssertTrue(paletteText.contains("public enum WorkspaceCommandPalette"), "Command palette API should stay in the focused command surface file.")
        XCTAssertTrue(paletteText.contains("WorkspaceCommandPaletteRanker.rankedCommands"), "Public palette ranking should delegate to the focused ranker.")
        XCTAssertTrue(paletteText.contains("WorkspaceCommandPaletteRanker.groupedCommands"), "Public palette grouping should delegate to the focused ranker.")
        XCTAssertTrue(rankerText.contains("enum WorkspaceCommandPaletteRanker"), "Palette ranking/search should live in its own focused helper.")
        XCTAssertTrue(rankerText.contains("private static func score"), "Palette scoring should be directly guarded in the ranker.")
        XCTAssertTrue(rankerText.contains("private struct QueryRequest"), "Palette query scoping should stay with the ranker.")
        XCTAssertFalse(paletteText.contains("private static func score"), "Command surface API should not own palette scoring internals.")
        XCTAssertFalse(paletteText.contains("private struct QueryRequest"), "Command surface API should not own query scoping internals.")
        XCTAssertFalse(surfaceText.contains("public struct WorkspaceCommandSurface"), "WorkspaceSurface should not own command surface records.")
        XCTAssertFalse(surfaceText.contains("public enum TopBarOverflowCommandCatalog"), "WorkspaceSurface should not own top-bar overflow projection.")
        XCTAssertFalse(surfaceText.contains("public enum WorkspaceCommandPalette"), "WorkspaceSurface should not own command palette ranking.")
        XCTAssertFalse(surfaceText.contains("private struct QueryRequest"), "WorkspaceSurface should not own command palette query scoping.")
    }

    func testWorkspaceSurfaceDelegatesSettingsSurfaceContract() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let settingsText = try Self.appSourceText(named: "QuillCodeSettingsSurface.swift")

        XCTAssertTrue(settingsText.contains("public struct WorkspaceSettingsSurface"), "Settings surface records should live beside settings-specific copy and compatibility behavior.")
        XCTAssertTrue(settingsText.contains("public struct WorkspaceSettingsUpdate"), "Settings update records should live beside the settings surface contract.")
        XCTAssertTrue(settingsText.contains("public struct ComputerUseRequirementSurface"), "Computer Use requirement rows should live beside settings permission copy.")
        XCTAssertTrue(settingsText.contains("private static func computerUseStatusLabel"), "Computer Use status copy should be directly guarded outside the aggregate surface file.")
        XCTAssertTrue(settingsText.contains("TrustedRouterDefaults.loopbackCallbackURL"), "TrustedRouter sign-in copy should stay with the settings contract.")
        XCTAssertFalse(surfaceText.contains("public struct WorkspaceSettingsSurface"), "WorkspaceSurface should not own settings surface records.")
        XCTAssertFalse(surfaceText.contains("public struct WorkspaceSettingsUpdate"), "WorkspaceSurface should not own settings update records.")
        XCTAssertFalse(surfaceText.contains("public struct ComputerUseRequirementSurface"), "WorkspaceSurface should not own Computer Use requirement rows.")
        XCTAssertFalse(surfaceText.contains("private static func computerUseStatusLabel"), "WorkspaceSurface should not own Computer Use settings copy.")
        XCTAssertFalse(surfaceText.contains("TrustedRouterDefaults.loopbackCallbackURL"), "WorkspaceSurface should not own TrustedRouter sign-in copy.")
    }


}
