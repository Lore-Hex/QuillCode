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
            "testDesktopDefinesNativeMenuBarWidgetAndUnifiedCommandRouting"
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
            "testTrustedRouterModelCatalogLivesOutsideGeneralDomainModels",
            "testTrustedRouterRecommendedModelsKeepCapabilityTaxonomy"
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
        Suite(fileName: "ParityWorkspaceStatusModelGateTests.swift", testNames: [
            "testWorkspaceModelDelegatesStatusTextAndLabels"
        ]),
        Suite(fileName: "ParityWorkspaceContextResolverGateTests.swift", testNames: [
            "testWorkspaceModelDelegatesContextResolving"
        ]),
        Suite(fileName: "ParityWorkspaceAgentProgressModelGateTests.swift", testNames: [
            "testWorkspaceModelDelegatesAgentProgressStatusCopy"
        ]),
        Suite(fileName: "ParityWorkspaceThreadMutationModelGateTests.swift", testNames: [
            "testWorkspaceModelDelegatesThreadNoticeMutation",
            "testWorkspaceModelUsesExplicitAgentRunThreadUpdates"
        ]),
        Suite(fileName: "ParityWorkspacePaneVisibilityModelGateTests.swift", testNames: [
            "testWorkspaceModelDelegatesPaneVisibilityMutations"
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
        Suite(fileName: "ParityWorkspaceSlashTranscriptGateTests.swift", testNames: [
            "testWorkspaceModelDelegatesSlashCommandTranscriptPlanning"
        ]),
        Suite(fileName: "ParityWorkspaceCommandActionPlannerGateTests.swift", testNames: [
            "testWorkspaceModelDelegatesCommandActionPlanning"
        ]),
        Suite(fileName: "ParityWorkspaceCommandPlanExecutorGateTests.swift", testNames: [
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
        Suite(fileName: "ParityWorkspaceMemorySupportGateTests.swift", testNames: [
            "testWorkspaceMemorySupportOwnsStoragePolicyAndCopyBoundaries"
        ]),
        Suite(fileName: "ParityWorkspaceMemoryModelGateTests.swift", testNames: [
            "testWorkspaceModelDelegatesMemoryCommandOrchestration",
        ]),
        Suite(fileName: "ParityWorkspaceMemoryIntegrationGateTests.swift", testNames: [
            "testWorkspaceMemoryIntegrationTestsOwnModelMemoryFlows"
        ]),
        Suite(fileName: "ParityWorkspacePlaywrightMemoryGateTests.swift", testNames: [
            "testPlaywrightMemoryFlowsStayInFocusedSpec"
        ]),
        Suite(fileName: "ParityWorkspaceMCPReviewIntegrationGateTests.swift", testNames: [
            "testWorkspaceMCPIntegrationTestsOwnModelMCPFlows",
            "testWorkspaceReviewIntegrationTestsOwnModelReviewFlows"
        ]),
        Suite(fileName: "ParityWorkspaceFeedbackRuntimeIntegrationGateTests.swift", testNames: [
            "testFocusedArtifactTestsOwnSurfaceSpecificFlows",
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
            "testSidebarSavedFiltersUseProgressiveDisclosureWithoutHorizontalChrome",
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
        Suite(fileName: "ParityAppServerMCPStartupGateTests.swift", testNames: [
            "testMCPStartupLifecycleStaysWiredThroughProtocolTestsAndDocs"
        ]),
        Suite(fileName: "ParityAppServerClientConfigurationGateTests.swift", testNames: [
            "testClientConfigurationDiscoveryStaysWiredThroughPolicyTestsSmokeAndDocs"
        ]),
        Suite(fileName: "ParityAppServerMemoryResetGateTests.swift", testNames: [
            "testMemoryResetStaysWiredThroughPersistenceRuntimeTestsSmokeAndDocs"
        ]),
        Suite(fileName: "ParityAutomationCoreModelGateTests.swift", testNames: [
            "testAutomationModelsLiveOutsideGeneralDomainModels"
        ]),
        Suite(fileName: "ParityWorkspaceAutomationStateGateTests.swift", testNames: [
            "testWorkspaceAutomationDataFactoryAndReducerStayFocused",
            "testWorkspaceAutomationModelDelegatesStateMutations"
        ]),
        Suite(fileName: "ParityWorkspaceAutomationRunGateTests.swift", testNames: [
            "testWorkspaceAutomationRunsDelegateRunnerAndEventSources"
        ]),
        Suite(fileName: "ParityAutomationEventSourceGateTests.swift", testNames: [
            "testMonitorEventSourceWiringStaysImplemented"
        ]),
        Suite(fileName: "ParityWorkspaceAutomationSurfaceGateTests.swift", testNames: [
            "testWorkspaceSurfaceDelegatesAutomationsSurfaceBuilding"
        ]),
        Suite(fileName: "ParityPlaywrightAutomationGateTests.swift", testNames: [
            "testPlaywrightAutomationFlowsStayInFocusedSpec"
        ]),
        Suite(fileName: "ParityWorkspaceRuntimeReviewGateTests.swift", testNames: [
            "testNativeReviewPaneDelegatesFileHunkAndLineRendering",
            "testWorkspaceSurfaceDelegatesRuntimeIssueBuilding",
            "testWorkspaceSurfaceDelegatesRuntimeAndExecutionContextContracts",
            "testWorkspaceViewDelegatesRuntimeIssueRecoveryPlanning"
        ]),
        Suite(fileName: "ParityWorkspaceViewCommandPlannerGateTests.swift", testNames: [
            "testWorkspaceViewDelegatesCommandPlanning"
        ]),
        Suite(fileName: "ParityWorkspaceCommandSurfaceBuilderGateTests.swift", testNames: [
            "testWorkspaceSurfaceDelegatesCommandSurfaceBuilding"
        ]),
        Suite(fileName: "ParityWorkspaceCommandPaletteContractGateTests.swift", testNames: [
            "testWorkspaceSurfaceDelegatesCommandPaletteContract"
        ]),
        Suite(fileName: "ParityPlaywrightCommandPaletteGateTests.swift", testNames: [
            "testPlaywrightCommandPaletteFlowsStaySplitByWorkflow"
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
        Suite(fileName: "ParityHTMLInteractionAuditContractGateTests.swift", testNames: [
            "testHTMLInteractionAuditRequiresNamesControlsAndLayers",
            "testHTMLInteractionAuditRequiresClearanceRegistriesAndSamples",
            "testHTMLInteractionAuditRequiresSemanticAndTactileContracts"
        ]),
        Suite(fileName: "ParityHTMLPrimitiveHitTargetGateTests.swift", testNames: [
            "testHTMLButtonPrimitiveDefaultsToSharedHitTargetClass",
            "testHTMLPrimitivesExposeSemanticTargetVocabulary",
            "testHTMLPrimitivesEmitSemanticTargetAttributes",
            "testHTMLPrimitivesRecognizeEverySharedTargetClass"
        ]),
        Suite(fileName: "ParityRenderedCommandRoutingGateTests.swift", testNames: [
            "testHarnessAuditsVisibleCommandTargetsForRouting"
        ]),
        Suite(fileName: "ParityRenderedCriticalTargetRegistryGateTests.swift", testNames: [
            "testRenderedCriticalTargetRegistryCoversPrimarySurfaces",
            "testRenderedCriticalTargetRegistryCoversRiskySmallControls",
            "testRenderedCriticalTargetRegistryCoversNearEdgeFlows",
            "testRenderedCriticalTargetRegistryIncludesSemanticFixtures"
        ]),
        Suite(fileName: "ParityRenderedResponsiveTargetGateTests.swift", testNames: [
            "testRenderedHarnessUsesNamedClearanceTokensForDenseActionClusters",
            "testFindBarUsesResponsiveTargetPreservingLayout",
            "testHarnessNormalizesDynamicClickTargetContracts",
            "testHarnessDeclaresActivityTargetContracts"
        ]),
        Suite(fileName: "ParityHTMLSourceInteractionTargetGateTests.swift", testNames: [
            "testHTMLRenderersUseSharedClickTargetPrimitives",
            "testRenderedHTMLPrimitiveCallSitesDeclareExplicitHitTargetKinds",
            "testHTMLSourceAuditRequiresSemanticKindForRawSharedTargets",
            "testHTMLSourceAuditAcceptsRawSharedTargetsWithSemanticKind"
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
        Suite(fileName: "ParityTrustedRouterActionParsingGateTests.swift", testNames: [
            "testTrustedRouterActionParsingLivesOutsideTransportClient"
        ]),
        Suite(fileName: "ParityTrustedRouterPromptGateTests.swift", testNames: [
            "testTrustedRouterPromptBuilderLivesOutsideTransportClient",
        ]),
        Suite(fileName: "ParityTrustedRouterAPIKeyGateTests.swift", testNames: [
            "testTrustedRouterAPIKeyResolutionLivesInFocusedResolver"
        ]),
        Suite(fileName: "ParityTrustedRouterSafetyTransportGateTests.swift", testNames: [
            "testTrustedRouterSafetyClientLivesOutsideActionTransportFile"
        ]),
        Suite(fileName: "ParityTrustedRouterChatParametersGateTests.swift", testNames: [
            "testTrustedRouterChatParametersLiveOutsideTransportClients"
        ]),
        Suite(fileName: "ParityTrustedRouterAdapterSuiteGateTests.swift", testNames: [
            "testTrustedRouterAdapterCoverageUsesFocusedSuites"
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
