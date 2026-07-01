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
        Suite(fileName: "ParityTerminalRendererGateTests.swift", testNames: [
            "testTerminalRendererKeepsEscapeSemanticsInFocusedFiles",
            "testTerminalRendererBehaviorTestsCoverScrollAndAlternateScreenParity"
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
            "testWorkspaceSurfaceDelegatesSecondaryPaneSurfaceContracts",
            "testPlaywrightTerminalFlowsStayInFocusedSpec",
            "testPlaywrightSearchFlowsStayInFocusedSpec",
            "testPlaywrightExtensionsFlowsStayInFocusedSpec",
            "testPlaywrightArtifactFlowsStayInFocusedSpec",
            "testPlaywrightComposerFlowsStayInFocusedSpec",
            "testPlaywrightWorkspaceChromeFlowsStayInFocusedSpec",
            "testPlaywrightWorkspaceStateFlowsStayInFocusedSpec",
            "testPlaywrightStatusFlowsStayInFocusedSpec",
            "testPlaywrightRealWorldActionFlowsStayInFocusedSpec",
            "testPlaywrightShortcutFlowsStayInFocusedSpec",
            "testPlaywrightReviewFlowsStayInFocusedSpec"
        ]),
        Suite(fileName: "ParityBrowserGateTests.swift", testNames: [
            "testWorkspaceModelDelegatesBrowserSurfaceTypes",
            "testBrowserArchitectureGatesStayOutOfBroadSuite"
        ]),
        Suite(fileName: "ParityBrowserSnapshotGateTests.swift", testNames: [
            "testBrowserInspectorDelegatesStaticHTMLSnapshotExtraction",
            "testBrowserLiveDOMCaptureStaysBehindAdapterContract"
        ]),
        Suite(fileName: "ParityBrowserSessionSyncGateTests.swift", testNames: [
            "testVisibleBrowserSessionSyncStaysBehindSnapshotContract"
        ]),
        Suite(fileName: "ParityBrowserWorkflowGateTests.swift", testNames: [
            "testWorkspaceModelDelegatesBrowserStateTransitions",
            "testWorkspaceModelDelegatesBrowserLocationResolving",
            "testWorkspaceBrowserIntegrationTestsOwnModelBrowserFlows"
        ]),
        Suite(fileName: "ParityBrowserToolRendererGateTests.swift", testNames: [
            "testBrowserAgentToolsShareFocusedExecutor",
            "testWorkspaceHTMLRendererDelegatesBrowserRendering",
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
            "testWorkspaceModelDelegatesPaneVisibilityMutations",
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
            "testWorkspaceMemoryIntegrationTestsOwnModelMemoryFlows",
            "testPlaywrightMemoryFlowsStayInFocusedSpec"
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
            "testWorkspaceSurfaceDelegatesNavigationSurfaceBuilding",
            "testPlaywrightSidebarAndProjectFlowsStayInFocusedSpec"
        ]),
        Suite(fileName: "ParityMCPGateTests.swift", testNames: [
            "testWorkspaceModelDelegatesMCPSupportTypes",
            "testMCPStdioProberDelegatesCodecAndResultMapping"
        ]),
        Suite(fileName: "ParityAutomationGateTests.swift", testNames: [
            "testAutomationModelsLiveOutsideGeneralDomainModels",
            "testWorkspaceModelDelegatesAutomationStateMutations",
            "testWorkspaceSurfaceDelegatesAutomationsSurfaceBuilding",
            "testPlaywrightAutomationFlowsStayInFocusedSpec"
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
            "testWorkspaceSurfaceDelegatesCommandPaletteContract",
            "testPlaywrightCommandPaletteAndGitFlowsStayInFocusedSpec"
        ]),
        Suite(fileName: "ParityWorkspaceSettingsSheetGateTests.swift", testNames: [
            "testWorkspaceSwiftUIViewDelegatesSheetPresentation",
            "testNativeSettingsDelegatesFocusedViewsAndDraftState"
        ]),
        Suite(fileName: "ParityNativeCompactHitTargetGateTests.swift", testNames: [
            "testNativeCompactPlainControlsKeepExplicitHitTargets"
        ]),
        Suite(fileName: "ParityNativePrimaryChromeHitTargetGateTests.swift", testNames: [
            "testNativePrimaryChromeKeepsSemanticHitTargets"
        ]),
        Suite(fileName: "ParitySearchDialogGateTests.swift", testNames: [
            "testNativeSearchDialogsKeepLocalTypingState"
        ]),
        Suite(fileName: "ParityWorkspaceSettingsSurfaceGateTests.swift", testNames: [
            "testWorkspaceSurfaceDelegatesSettingsSurfaceContract"
        ]),
        Suite(fileName: "ParityPlaywrightSettingsRuntimeGateTests.swift", testNames: [
            "testPlaywrightSettingsAndRuntimeFlowsStayInFocusedSpec"
        ]),
        Suite(fileName: "ParityWorkspaceTranscriptGateTests.swift", testNames: [
            "testWorkspaceSwiftUIViewDelegatesTranscriptFindAndContextBanner"
        ]),
        Suite(fileName: "ParityAgentGateTests.swift", testNames: [
            "testAgentRunnerDelegatesFinalAnswerFormatting",
            "testMockLLMClientLivesOutsideAgentRunnerFile",
            "testAgentStreamingHelpersLiveOutsideAgentRunnerFile",
            "testAgentContractsAndActionResolutionLiveOutsideRunnerFile",
            "testAgentToolStepRunnerLivesOutsideAgentRunnerFile",
            "testAgentBehaviorTestsUseFocusedSuites"
        ]),
        Suite(fileName: "ParityTrustedRouterGateTests.swift", testNames: [
            "testTrustedRouterActionParserLivesOutsideTransportClient",
            "testTrustedRouterPromptBuilderLivesOutsideTransportClient",
            "testTrustedRouterAPIKeyResolutionLivesInFocusedResolver",
            "testTrustedRouterSafetyClientLivesOutsideActionTransportFile",
            "testTrustedRouterChatParametersLiveOutsideTransportClients",
            "testTrustedRouterAdapterTestsUseFocusedSuites"
        ]),
        Suite(fileName: "ParitySafetyGateTests.swift", testNames: [
            "testStaticSafetyPolicyLivesOutsideReviewerControlFlow"
        ]),
        Suite(fileName: "ParityCoreModelGateTests.swift", testNames: [
            "testCoreToolModelsLiveOutsideGeneralDomainModels",
            "testProjectModelsLiveOutsideGeneralDomainModels"
        ]),
        Suite(fileName: "ParityMergeTrainGateTests.swift", testNames: [
            "testBehindBranchesDoNotUseActionTokenUpdatesByDefault",
            "testBehindBranchUpdateRequiresExplicitOptIn"
        ])
    ]

    static var requiredFileNames: [String] {
        [supportFileName, manifestFileName] + suites.map(\.fileName)
    }
}
