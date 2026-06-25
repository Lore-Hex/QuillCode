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
            "ParityWorkspaceSettingsSheetGateTests.swift",
            "ParityWorkspaceTranscriptGateTests.swift",
            "ParityAgentGateTests.swift",
            "ParityTrustedRouterGateTests.swift"
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
            ]),
            ("ParityWorkspaceTranscriptGateTests", [
                "testWorkspaceSwiftUIViewDelegatesTranscriptFindAndContextBanner"
            ]),
            ("ParityAgentGateTests", [
                "testAgentRunnerDelegatesFinalAnswerFormatting",
                "testMockLLMClientLivesOutsideAgentRunnerFile",
                "testAgentStreamingHelpersLiveOutsideAgentRunnerFile",
                "testAgentToolStepRunnerLivesOutsideAgentRunnerFile"
            ]),
            ("ParityTrustedRouterGateTests", [
                "testTrustedRouterActionParserLivesOutsideTransportClient",
                "testTrustedRouterPromptBuilderLivesOutsideTransportClient",
                "testTrustedRouterAPIKeyResolutionLivesInFocusedResolver",
                "testTrustedRouterSafetyClientLivesOutsideActionTransportFile",
                "testTrustedRouterChatParametersLiveOutsideTransportClients"
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

}
