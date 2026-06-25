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
            "ParityTrustedRouterGateTests.swift",
            "ParitySafetyGateTests.swift",
            "ParityCoreModelGateTests.swift"
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
            ]),
            ("ParitySafetyGateTests", [
                "testStaticSafetyPolicyLivesOutsideReviewerControlFlow"
            ]),
            ("ParityCoreModelGateTests", [
                "testCoreToolModelsLiveOutsideGeneralDomainModels",
                "testProjectModelsLiveOutsideGeneralDomainModels"
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

}
