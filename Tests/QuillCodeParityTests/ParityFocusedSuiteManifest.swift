struct ParityFocusedSuiteManifest {
    struct Suite {
        let fileName: String
        let testNames: [String]
    }

    static let supportFileName = "ParityTestSupport.swift"
    static let manifestFileName = "ParityFocusedSuiteManifest.swift"

    static let suites: [Suite] = [
        Suite(fileName: "ParityToolGateTests.swift", testNames: [
            "testToolArgumentJSONSerializationLivesInCore"
        ]),
        Suite(fileName: "ParityDesktopGateTests.swift", testNames: [
            "testDesktopDefinesNativeMenuBarWidget"
        ]),
        Suite(fileName: "ParityTopBarGateTests.swift", testNames: [
            "testTopBarViewsDelegateStatusPresentationSemantics"
        ]),
        Suite(fileName: "ParitySlashGateTests.swift", testNames: [
            "testSlashParserDelegatesPullRequestSubcommands"
        ]),
        Suite(fileName: "ParityModelGateTests.swift", testNames: [
            "testTrustedRouterModelCatalogLivesOutsideGeneralDomainModels"
        ]),
        Suite(fileName: "ParityWorkspaceSurfaceGateTests.swift", testNames: [
            "testWorkspaceSurfaceDelegatesSecondaryPaneSurfaceContracts"
        ]),
        Suite(fileName: "ParityBrowserGateTests.swift", testNames: [
            "testWorkspaceModelDelegatesBrowserSurfaceTypes",
            "testBrowserInspectorDelegatesStaticHTMLSnapshotExtraction",
            "testBrowserLiveDOMCaptureStaysBehindAdapterContract",
            "testWorkspaceModelDelegatesBrowserStateTransitions",
            "testWorkspaceModelDelegatesBrowserLocationResolving",
            "testWorkspaceBrowserIntegrationTestsOwnModelBrowserFlows",
            "testBrowserAgentToolsShareFocusedExecutor",
            "testWorkspaceHTMLRendererDelegatesBrowserRendering",
            "testBrowserArchitectureGatesStayOutOfBroadSuite",
            "testPlaywrightBrowserFlowsStayInFocusedSpec"
        ]),
        Suite(fileName: "ParityWorkspaceModelGateTests.swift", testNames: [
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
        Suite(fileName: "ParityWorkspaceExecutionGateTests.swift", testNames: [
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
        Suite(fileName: "ParityWorkspaceProjectGateTests.swift", testNames: [
            "testWorkspaceModelDelegatesProjectMetadataLoading",
            "testWorkspaceModelTestsDoNotOwnPureProjectLoaderCoverage",
            "testWorkspaceProjectExtensionIntegrationTestsOwnModelExtensionFlows",
            "testWorkspaceProjectIntegrationTestsOwnModelProjectFlows",
            "testWorkspaceRemoteProjectIntegrationTestsOwnModelRemoteProjectFlows",
            "testWorkspacePullRequestIntegrationTestsOwnModelPullRequestFlows",
            "testWorkspaceWorktreeIntegrationTestsOwnModelWorktreeFlows",
            "testWorkspaceModelDelegatesWorktreeOpenRecords"
        ]),
        Suite(fileName: "ParityWorkspaceMemoryGateTests.swift", testNames: [
            "testWorkspaceModelDelegatesMemoryCommandOrchestration",
            "testWorkspaceMemoryIntegrationTestsOwnModelMemoryFlows"
        ]),
        Suite(fileName: "ParityWorkspaceIntegrationGateTests.swift", testNames: [
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
        Suite(fileName: "ParityWorkspaceSidebarGateTests.swift", testNames: [
            "testWorkspaceModelDelegatesSidebarSelectionTransitions",
            "testSidebarRowActionsUseSharedPlannerAndExecutor",
            "testSidebarCommandPresentationIsSharedByNativeAndHTMLSurfaces",
            "testNativeSidebarDelegatesProjectListRendering",
            "testWorkspaceSurfaceDelegatesSidebarSurfaceContracts",
            "testWorkspaceSurfaceDelegatesNavigationSurfaceBuilding"
        ]),
        Suite(fileName: "ParityMCPGateTests.swift", testNames: [
            "testWorkspaceModelDelegatesMCPSupportTypes",
            "testMCPStdioProberDelegatesCodecAndResultMapping"
        ]),
        Suite(fileName: "ParityAutomationGateTests.swift", testNames: [
            "testAutomationModelsLiveOutsideGeneralDomainModels",
            "testWorkspaceModelDelegatesAutomationStateMutations",
            "testWorkspaceSurfaceDelegatesAutomationsSurfaceBuilding"
        ]),
        Suite(fileName: "ParityWorkspaceRuntimeReviewGateTests.swift", testNames: [
            "testNativeReviewPaneDelegatesFileHunkAndLineRendering",
            "testWorkspaceSurfaceDelegatesRuntimeIssueBuilding",
            "testWorkspaceSurfaceDelegatesRuntimeAndExecutionContextContracts",
            "testWorkspaceViewDelegatesRuntimeIssueRecoveryPlanning"
        ]),
        Suite(fileName: "ParityWorkspaceCommandGateTests.swift", testNames: [
            "testWorkspaceViewDelegatesCommandPlanning",
            "testWorkspaceSurfaceDelegatesCommandSurfaceBuilding",
            "testWorkspaceSurfaceDelegatesCommandPaletteContract"
        ]),
        Suite(fileName: "ParityWorkspaceSettingsSheetGateTests.swift", testNames: [
            "testWorkspaceSwiftUIViewDelegatesSheetPresentation",
            "testNativeSettingsDelegatesFocusedViewsAndDraftState",
            "testWorkspaceSurfaceDelegatesSettingsSurfaceContract"
        ]),
        Suite(fileName: "ParityWorkspaceTranscriptGateTests.swift", testNames: [
            "testWorkspaceSwiftUIViewDelegatesTranscriptFindAndContextBanner"
        ]),
        Suite(fileName: "ParityAgentGateTests.swift", testNames: [
            "testAgentRunnerDelegatesFinalAnswerFormatting",
            "testMockLLMClientLivesOutsideAgentRunnerFile",
            "testAgentStreamingHelpersLiveOutsideAgentRunnerFile",
            "testAgentToolStepRunnerLivesOutsideAgentRunnerFile"
        ]),
        Suite(fileName: "ParityTrustedRouterGateTests.swift", testNames: [
            "testTrustedRouterActionParserLivesOutsideTransportClient",
            "testTrustedRouterPromptBuilderLivesOutsideTransportClient",
            "testTrustedRouterAPIKeyResolutionLivesInFocusedResolver",
            "testTrustedRouterSafetyClientLivesOutsideActionTransportFile",
            "testTrustedRouterChatParametersLiveOutsideTransportClients"
        ]),
        Suite(fileName: "ParitySafetyGateTests.swift", testNames: [
            "testStaticSafetyPolicyLivesOutsideReviewerControlFlow"
        ]),
        Suite(fileName: "ParityCoreModelGateTests.swift", testNames: [
            "testCoreToolModelsLiveOutsideGeneralDomainModels",
            "testProjectModelsLiveOutsideGeneralDomainModels"
        ])
    ]

    static var requiredFileNames: [String] {
        [supportFileName, manifestFileName] + suites.map(\.fileName)
    }
}
