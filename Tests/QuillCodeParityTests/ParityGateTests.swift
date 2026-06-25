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
            "ParityWorkspaceIntegrationGateTests.swift",
            "ParityWorkspaceSidebarGateTests.swift",
            "ParityMCPGateTests.swift",
            "ParityAutomationGateTests.swift",
            "ParityWorkspaceRuntimeReviewGateTests.swift",
            "ParityWorkspaceCommandGateTests.swift",
            "ParityWorkspaceSettingsSheetGateTests.swift"
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
            ]),
            ("ParityWorkspaceSidebarGateTests", [
                "testWorkspaceModelDelegatesSidebarSelectionTransitions",
                "testSidebarRowActionsUseSharedPlannerAndExecutor",
                "testSidebarCommandPresentationIsSharedByNativeAndHTMLSurfaces",
                "testNativeSidebarDelegatesProjectListRendering",
                "testWorkspaceSurfaceDelegatesSidebarSurfaceContracts",
                "testWorkspaceSurfaceDelegatesNavigationSurfaceBuilding"
            ]),
            ("ParityMCPGateTests", [
                "testWorkspaceModelDelegatesMCPSupportTypes",
                "testMCPStdioProberDelegatesCodecAndResultMapping"
            ]),
            ("ParityAutomationGateTests", [
                "testAutomationModelsLiveOutsideGeneralDomainModels",
                "testWorkspaceModelDelegatesAutomationStateMutations",
                "testWorkspaceSurfaceDelegatesAutomationsSurfaceBuilding"
            ]),
            ("ParityWorkspaceRuntimeReviewGateTests", [
                "testNativeReviewPaneDelegatesFileHunkAndLineRendering",
                "testWorkspaceSurfaceDelegatesRuntimeIssueBuilding",
                "testWorkspaceSurfaceDelegatesRuntimeAndExecutionContextContracts",
                "testWorkspaceViewDelegatesRuntimeIssueRecoveryPlanning"
            ]),
            ("ParityWorkspaceCommandGateTests", [
                "testWorkspaceViewDelegatesCommandPlanning",
                "testWorkspaceSurfaceDelegatesCommandSurfaceBuilding",
                "testWorkspaceSurfaceDelegatesCommandPaletteContract"
            ]),
            ("ParityWorkspaceSettingsSheetGateTests", [
                "testWorkspaceSwiftUIViewDelegatesSheetPresentation",
                "testNativeSettingsDelegatesFocusedViewsAndDraftState",
                "testWorkspaceSurfaceDelegatesSettingsSurfaceContract"
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

}
