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
        Suite(fileName: "ParityTopBarPresentationGateTests.swift", testNames: [
            "testTopBarViewsDelegateStatusPresentationSemantics",
            "testTopBarAgentStatusLabelsAreSharedByRuntimePaths",
            "testRuntimeStatusLabelsAreSharedByAuthAndIssuePaths"
        ]),
        Suite(fileName: "ParityNativeTopBarChromeGateTests.swift", testNames: [
            "testNativeTopBarKeepsCodexStyleChromeQuiet",
            "testNativeModePickerLivesBesideComposerAccessoryChrome"
        ]),
        Suite(fileName: "ParityTopBarSurfaceGateTests.swift", testNames: [
            "testWorkspaceSurfaceDelegatesModelCatalogBuilding",
            "testWorkspaceSurfaceDelegatesTopBarSurfaceContracts",
            "testWorkspaceSurfaceDelegatesTopBarSurfaceBuilding"
        ]),
        Suite(fileName: "ParityNativeModelPickerGateTests.swift", testNames: [
            "testNativeModelPickerKeepsRowsAndDetailsFocused"
        ]),
        Suite(fileName: "ParityModelPickerIntegrationGateTests.swift", testNames: [
            "testModelPickerWorkspaceIntegrationCoverageStaysFocused"
        ]),
        Suite(fileName: "ParitySlashRepositoryParserGateTests.swift", testNames: [
            "testSlashParserDelegatesPullRequestSubcommands",
            "testSlashParserDelegatesProjectSubcommands",
            "testSlashParserDelegatesRemoteProjectSubcommands"
        ]),
        Suite(fileName: "ParitySlashSessionParserGateTests.swift", testNames: [
            "testSlashParserDelegatesTerminalSubcommands",
            "testSlashParserDelegatesModeSubcommands",
            "testSlashParserDelegatesModelSubcommands"
        ]),
        Suite(fileName: "ParitySlashThreadMemoryParserGateTests.swift", testNames: [
            "testSlashParserDelegatesThreadLifecycleSubcommands",
            "testSlashParserDelegatesMemorySubcommands"
        ]),
        Suite(fileName: "ParitySlashWorkspaceParserGateTests.swift", testNames: [
            "testSlashParserDelegatesWorkspaceSubcommands",
            "testSlashParserDelegatesEnvironmentSubcommands",
            "testSlashParserDelegatesSchedulingSubcommands"
        ]),
        Suite(fileName: "ParityModelGateTests.swift", testNames: [
            "testTrustedRouterModelCatalogLivesOutsideGeneralDomainModels"
        ]),
        Suite(fileName: "ParityWorkspaceSecondaryPaneSurfaceGateTests.swift", testNames: [
            "testWorkspaceSurfaceDelegatesSecondaryPaneSurfaceContracts"
        ]),
        Suite(fileName: "ParityWorkspaceComposerSurfaceGateTests.swift", testNames: [
            "testComposerSeparatesModelAndApprovalModeControls"
        ]),
        Suite(fileName: "ParityWorkspaceTerminalBrowserSurfaceGateTests.swift", testNames: [
            "testNativeTerminalAndBrowserPanesUseFocusedViewFiles",
            "testWorkspaceSurfaceDelegatesTerminalSurfaceContracts",
            "testTerminalStateContractsLiveOutsideEngine"
        ]),
        Suite(fileName: "ParityWorkspacePlaywrightFocusedSpecGateTests.swift", testNames: [
            "testPlaywrightTerminalFlowsStayInFocusedSpec",
            "testPlaywrightSearchFlowsStayInFocusedSpec",
            "testPlaywrightExtensionsFlowsStayInFocusedSpec",
            "testPlaywrightArtifactFlowsStayInFocusedSpec",
            "testPlaywrightComposerFlowsStayInFocusedSpec"
        ]),
        Suite(fileName: "ParityWorkspacePlaywrightChromeSpecGateTests.swift", testNames: [
            "testPlaywrightWorkspaceChromeFlowsStayInFocusedSpec",
            "testPlaywrightWorkspaceStateFlowsStayInFocusedSpec",
            "testPlaywrightStatusFlowsStayInFocusedSpec"
        ]),
        Suite(fileName: "ParityWorkspacePlaywrightRealWorldSpecGateTests.swift", testNames: [
            "testPlaywrightRealWorldActionFlowsStayInFocusedSpec",
            "testDeterministicSmokeCollectsPlaywrightRealWorldActionEvidence"
        ]),
        Suite(fileName: "ParityWorkspacePlaywrightInteractionSpecGateTests.swift", testNames: [
            "testPlaywrightResponsivenessBudgetsStayInFocusedSpec",
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
        Suite(fileName: "ParityWorkspaceToolCardModelGateTests.swift", testNames: [
            "testWorkspaceModelDelegatesToolCardSurfaceTypes"
        ]),
        Suite(fileName: "ParityWorkspaceUIStateModelGateTests.swift", testNames: [
            "testWorkspaceModelDelegatesUIStateContracts"
        ]),
        Suite(fileName: "ParityWorkspaceReviewCardModelGateTests.swift", testNames: [
            "testActionableReviewCardsStayWiredThroughSurfaces"
        ]),
        Suite(fileName: "ParityWorkspaceExecutionContextModelGateTests.swift", testNames: [
            "testWorkspaceModelDelegatesExecutionContextSurfaceBuilding"
        ]),
        Suite(fileName: "ParityWorkspaceModelActivityGateTests.swift", testNames: [
            "testWorkspaceModelDelegatesRetryPlanning",
            "testWorkspaceActivityIntegrationTestsOwnModelActivityFlows",
            "testWorkspaceActivitySurfaceUsesFocusedBuilderAndSectionTypes",
            "testWorkspaceToolCardIntegrationTestsOwnModelToolCardFlows",
            "testWorkspaceModelTestsRemainRetired",
            "testFocusedWorkspaceUnitSuitesUseSharedTemporaryDirectorySupport"
        ]),
        Suite(fileName: "ParityWorkspaceModelStateGateTests.swift", testNames: [
            "testWorkspaceModelDelegatesStatusTextAndLabels",
            "testWorkspaceModelDelegatesContextResolving",
            "testWorkspaceModelDelegatesAgentProgressStatusCopy",
            "testWorkspaceModelDelegatesThreadNoticeMutation",
            "testWorkspaceModelDelegatesPaneVisibilityMutations",
            "testWorkspaceModelUsesExplicitAgentRunThreadUpdates"
        ]),
        Suite(fileName: "ParityWorkspaceContextRefreshGateTests.swift", testNames: [
            "testWorkspaceModelDelegatesProjectContextRefresh"
        ]),
        Suite(fileName: "ParityWorkspaceThreadSeedGateTests.swift", testNames: [
            "testWorkspaceModelDelegatesThreadSeedBuilding"
        ]),
        Suite(fileName: "ParityWorkspaceThreadCreationGateTests.swift", testNames: [
            "testWorkspaceModelDelegatesThreadCreationRecords"
        ]),
        Suite(fileName: "ParityWorkspaceThreadLifecycleGateTests.swift", testNames: [
            "testWorkspaceModelDelegatesThreadLifecycleTransitions"
        ]),
        Suite(fileName: "ParityWorkspaceConfigurationGateTests.swift", testNames: [
            "testWorkspaceModelDelegatesConfigurationTransitions",
            "testWorkspaceConfigurationIntegrationTestsOwnModelConfigurationFlows"
        ]),
        Suite(fileName: "ParityWorkspaceExecutionGateTests.swift", testNames: [
            "testWorkspaceModelDelegatesComposerCancellationPlanning",
            "testWorkspaceModelDelegatesComposerSubmissionPlanning",
            "testWorkspaceModelDelegatesAgentSendSessionExecution",
            "testWorkspaceModelDelegatesAgentSendStartPlanning",
            "testWorkspaceModelDelegatesAgentSendThreadPreparation",
            "testWorkspaceModelDelegatesAgentSendProgressPlanning",
            "testWorkspaceModelDelegatesAgentSendTerminalPlanning"
        ]),
        Suite(fileName: "ParityWorkspaceExecutionSlashGateTests.swift", testNames: [
            "testWorkspaceModelDelegatesSlashCommandTranscriptPlanning",
            "testWorkspaceModelDelegatesCommandActionPlanning",
            "testWorkspaceModelDelegatesCommandPlanExecution"
        ]),
        Suite(fileName: "ParityWorkspaceExecutionAgentContextGateTests.swift", testNames: [
            "testWorkspaceModelDelegatesAgentRunContextAssembly",
            "testWorkspaceModelDelegatesAgentSendSession"
        ]),
        Suite(fileName: "ParityWorkspaceExecutionIntegrationGateTests.swift", testNames: [
            "testWorkspaceComposerIntegrationTestsOwnModelComposerFlows",
            "testWorkspaceModelDelegatesSlashCommandDispatchPlanning",
            "testSubagentExecutionIsRealSchedulerNotDisplayOnly"
        ]),
        Suite(fileName: "ParityWorkspaceToolEventGateTests.swift", testNames: [
            "testWorkspaceModelDelegatesToolEventRecording"
        ]),
        Suite(fileName: "ParityWorkspaceToolRoutingGateTests.swift", testNames: [
            "testWorkspaceModelDelegatesToolCallExecutionRouting",
            "testWorkspaceModelDelegatesToolExecutionOverrideCombining"
        ]),
        Suite(fileName: "ParityWorkspaceToolRunLifecycleGateTests.swift", testNames: [
            "testWorkspaceModelDelegatesToolRunPreparation",
            "testWorkspaceModelDelegatesToolRunLifecyclePlanning"
        ]),
        Suite(fileName: "ParityWorkspaceRuntimeToolGateTests.swift", testNames: [
            "testWorkspaceModelDelegatesTerminalLifecyclePlanning",
            "testWorkspaceModelDelegatesActiveWorkStopPlanning",
            "testWorkspaceModelDelegatesShellToolCallPlanning"
        ]),
        Suite(fileName: "ParityWorkspaceProjectGateTests.swift", testNames: [
            "testWorkspaceModelDelegatesProjectMetadataLoading",
            "testWorkspaceModelProjectAPIsLiveInFocusedExtension",
            "testWorkspaceModelTestsDoNotOwnPureProjectLoaderCoverage",
            "testProjectInstructionScopesStayInCorePromptAndActivityContracts"
        ]),
        Suite(fileName: "ParityWorkspaceProjectIntegrationGateTests.swift", testNames: [
            "testWorkspaceProjectExtensionIntegrationTestsOwnModelExtensionFlows",
            "testWorkspaceProjectIntegrationTestsOwnModelProjectFlows",
            "testWorkspaceRemoteProjectIntegrationTestsOwnModelRemoteProjectFlows",
            "testWorkspacePullRequestIntegrationTestsOwnModelPullRequestFlows"
        ]),
        Suite(fileName: "ParityWorkspaceWorktreeGateTests.swift", testNames: [
            "testWorkspaceWorktreeIntegrationTestsOwnModelWorktreeFlows",
            "testWorkspaceModelDelegatesWorktreeOpenRecords"
        ]),
        Suite(fileName: "ParityWorkspaceMemoryGateTests.swift", testNames: [
            "testWorkspaceModelDelegatesMemoryCommandOrchestration",
            "testWorkspaceMemoryIntegrationTestsOwnModelMemoryFlows",
            "testPlaywrightMemoryFlowsStayInFocusedSpec"
        ]),
        Suite(fileName: "ParityWorkspaceMCPReviewIntegrationGateTests.swift", testNames: [
            "testWorkspaceMCPIntegrationTestsOwnModelMCPFlows",
            "testWorkspaceReviewIntegrationTestsOwnModelReviewFlows"
        ]),
        Suite(fileName: "ParityWorkspaceFeedbackRuntimeIntegrationGateTests.swift", testNames: [
            "testFocusedFeedbackAndArtifactTestsOwnSurfaceSpecificFlows",
            "testWorkspaceRuntimeIssueIntegrationTestsOwnModelRuntimeIssueFlows"
        ]),
        Suite(fileName: "ParityWorkspaceThreadCommandIntegrationGateTests.swift", testNames: [
            "testWorkspaceThreadLifecycleIntegrationTestsOwnModelLifecycleFlows",
            "testWorkspaceSlashCommandIntegrationTestsOwnCoreSlashFlows",
            "testWorkspaceLocalEnvironmentIntegrationTestsOwnModelLocalEnvironmentFlows"
        ]),
        Suite(fileName: "ParityWorkspaceAutomationTerminalIntegrationGateTests.swift", testNames: [
            "testWorkspaceAutomationIntegrationTestsOwnModelAutomationFlows",
            "testWorkspaceTerminalIntegrationTestsOwnModelTerminalFlows"
        ]),
        Suite(fileName: "ParityWorkspaceRuntimeFactoryGateTests.swift", testNames: [
            "testWorkspaceModelTestsDoNotOwnRuntimeFactoryCoverage"
        ]),
        Suite(fileName: "ParityWorkspaceSidebarGateTests.swift", testNames: [
            "testWorkspaceModelDelegatesSidebarSelectionTransitions"
        ]),
        Suite(fileName: "ParityWorkspaceSidebarRowActionGateTests.swift", testNames: [
            "testSidebarRowActionsUseSharedPlannerAndExecutor"
        ]),
        Suite(fileName: "ParitySidebarCommandPresentationGateTests.swift", testNames: [
            "testSidebarCommandPresentationIsSharedByNativeAndHTMLSurfaces",
            "testSidebarSavedFiltersWrapInsteadOfClippingHorizontally",
            "testNativeSidebarDelegatesProjectListRendering",
        ]),
        Suite(fileName: "ParityWorkspaceSidebarSurfaceGateTests.swift", testNames: [
            "testWorkspaceSurfaceDelegatesSidebarSurfaceContracts",
            "testWorkspaceSurfaceDelegatesNavigationSurfaceBuilding"
        ]),
        Suite(fileName: "ParityWorkspaceSidebarPlaywrightGateTests.swift", testNames: [
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
        Suite(fileName: "ParityAgentFinalAnswerGateTests.swift", testNames: [
            "testAgentRunnerDelegatesFinalAnswerFormatting"
        ]),
        Suite(fileName: "ParityAgentMockPlanningGateTests.swift", testNames: [
            "testMockLLMClientLivesOutsideAgentRunnerFile"
        ]),
        Suite(fileName: "ParityAgentStreamingGateTests.swift", testNames: [
            "testAgentStreamingHelpersLiveOutsideAgentRunnerFile",
            "testAgentCancellationTelemetryLivesInFocusedRecorder"
        ]),
        Suite(fileName: "ParityAgentContractsToolStepGateTests.swift", testNames: [
            "testAgentContractsAndActionResolutionLiveOutsideRunnerFile",
            "testAgentToolStepRunnerLivesOutsideAgentRunnerFile"
        ]),
        Suite(fileName: "ParityAgentBehaviorSuiteGateTests.swift", testNames: [
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
