enum ParityFocusedSuiteRegistry {
    static let requiredTestFiles = [
        "ParityTestSupport.swift",
        "ParityFocusedSuiteRegistry.swift",
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

    static let focusedSuiteTests: [(suiteName: String, testNames: [String])] = [
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
}
