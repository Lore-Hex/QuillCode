import XCTest

final class ParityWorkspaceModelGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesToolCardSurfaceTypes() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let toolCardSurfaceText = try Self.appSourceText(named: "QuillCodeToolCardSurface.swift")
        let toolArtifactSurfaceText = try Self.appSourceText(named: "QuillCodeToolArtifactSurface.swift")
        let artifactValueClassifierText = try Self.appSourceText(named: "ToolArtifactValueClassifier.swift")
        let artifactImagePreviewText = try Self.appSourceText(named: "ToolArtifactImagePreviewBuilder.swift")
        let artifactDocumentPreviewText = try Self.appSourceText(named: "ToolArtifactDocumentPreviewBuilder.swift")
        let artifactTextPreviewText = try Self.appSourceText(named: "ToolArtifactTextPreviewBuilder.swift")
        let transcriptBuilderText = try Self.appSourceText(named: "WorkspaceTranscriptSurfaceBuilder.swift")
        let toolCardReducerText = try Self.appSourceText(named: "WorkspaceToolCardEventReducer.swift")
        let toolCardProjectionText = try Self.appSourceText(named: "WorkspaceToolCardProjection.swift")

        XCTAssertTrue(toolCardSurfaceText.contains("public struct ToolCardState"), "Tool card surface state should live in a focused surface file.")
        XCTAssertTrue(toolArtifactSurfaceText.contains("public struct ToolArtifactState"), "Tool artifact surface state should live in a focused artifact surface file.")
        XCTAssertTrue(toolArtifactSurfaceText.contains("ToolArtifactValueClassifier.kind"), "Tool artifact state should delegate value classification.")
        XCTAssertTrue(toolArtifactSurfaceText.contains("ToolArtifactImagePreviewBuilder.imagePreview"), "Tool artifact state should delegate image previews.")
        XCTAssertTrue(toolArtifactSurfaceText.contains("ToolArtifactDocumentPreviewBuilder.documentPreview"), "Tool artifact state should delegate document previews.")
        XCTAssertTrue(artifactValueClassifierText.contains("enum ToolArtifactValueClassifier"), "Artifact value classification should have a focused owner.")
        XCTAssertTrue(artifactImagePreviewText.contains("enum ToolArtifactImagePreviewBuilder"), "Image preview construction should have a focused owner.")
        XCTAssertTrue(artifactDocumentPreviewText.contains("enum ToolArtifactDocumentPreviewBuilder"), "Document preview construction should have a focused owner.")
        XCTAssertTrue(artifactTextPreviewText.contains("enum ToolArtifactTextPreviewBuilder"), "Artifact text-preview file reading should have a focused owner.")
        XCTAssertTrue(toolCardReducerText.contains("struct WorkspaceToolCardEventReducer"), "Tool-card event state should live in a focused reducer.")
        XCTAssertTrue(toolCardProjectionText.contains("enum WorkspaceToolCardProjection"), "Tool-card projection copy and formatting should live in a focused projection helper.")
        XCTAssertTrue(transcriptBuilderText.contains("WorkspaceToolCardEventReducer"), "Transcript projection should delegate tool-card lifecycle state.")
        XCTAssertTrue(toolCardReducerText.contains("WorkspaceToolCardProjection"), "Tool-card event reduction should delegate card projection details.")
        XCTAssertTrue(toolCardProjectionText.contains("ToolArtifactTextPreviewBuilder.textPreview"), "Tool-card projection should request artifact text previews through the extracted builder.")
        XCTAssertTrue(toolArtifactSurfaceText.contains("public struct ToolArtifactDocumentPreview"), "Document preview contracts should live beside artifact state.")
        XCTAssertTrue(toolArtifactSurfaceText.contains("public struct ToolArtifactImagePreview"), "Image preview contracts should live beside artifact state.")
        XCTAssertFalse(modelText.contains("public struct ToolCardState"), "WorkspaceModel should not own tool card surface state.")
        XCTAssertFalse(modelText.contains("public enum ToolCardStatus"), "WorkspaceModel should not own tool card status.")
        XCTAssertFalse(modelText.contains("public struct ToolArtifactState"), "WorkspaceModel should not own tool artifact surface state.")
        XCTAssertFalse(modelText.contains("ToolArtifactTextPreviewBuilder.textPreview"), "WorkspaceModel should not own artifact-preview requests.")
        XCTAssertFalse(transcriptBuilderText.contains("ToolArtifactTextPreviewBuilder.textPreview"), "Transcript projection should not own artifact-preview requests.")
        XCTAssertFalse(toolCardReducerText.contains("ToolArtifactTextPreviewBuilder.textPreview"), "Tool-card event reduction should not own artifact-preview requests.")
        XCTAssertFalse(transcriptBuilderText.contains("private static func approvalReviewCard"), "Transcript projection should not own tool-card approval rendering state.")
        XCTAssertFalse(toolArtifactSurfaceText.contains("private static func documentPreview"), "Tool artifact state should not own document-preview classification.")
        XCTAssertFalse(toolArtifactSurfaceText.contains("private static func isImagePreview"), "Tool artifact state should not own image-preview classification.")
        XCTAssertFalse(toolArtifactSurfaceText.contains("private static func localArtifactFileURL"), "Tool artifact state should not own text-preview file reading.")
        XCTAssertFalse(toolCardSurfaceText.contains("ToolArtifactTextPreviewBuilder"), "Tool-card state should not own artifact preview construction.")
        XCTAssertFalse(toolCardSurfaceText.contains("public enum ToolArtifactDocumentKind"), "Tool-card state should not own artifact document metadata.")
    }

    func testWorkspaceModelDelegatesUIStateContracts() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let composerText = try Self.appSourceText(named: "WorkspaceModelComposer.swift")
        let stateText = try Self.appSourceText(named: "WorkspaceUIState.swift")
        let sendLifecycleText = try Self.appSourceText(named: "WorkspaceComposerSendLifecycle.swift")
        let sendStartText = try Self.appSourceText(named: "WorkspaceAgentSendStartPlanner.swift")
        let sendProgressText = try Self.appSourceText(named: "WorkspaceAgentSendProgressPlanner.swift")
        let sendTerminalText = try Self.appSourceText(named: "WorkspaceAgentSendTerminalPlanner.swift")

        XCTAssertTrue(stateText.contains("public struct ComposerState"), "Composer UI state should live in a focused state contract file.")
        XCTAssertTrue(stateText.contains("public struct MemoriesState"), "Memory-pane UI state should live in a focused state contract file.")
        XCTAssertTrue(stateText.contains("public struct ActivityState"), "Activity-pane UI state should live in a focused state contract file.")
        XCTAssertTrue(sendLifecycleText.contains("enum WorkspaceComposerSendLifecycle"), "Composer send lifecycle transitions should live in a focused helper.")
        XCTAssertTrue(sendStartText.contains("WorkspaceComposerSendLifecycle.started"), "Agent send start should choose started lifecycle through the start planner.")
        XCTAssertTrue(sendProgressText.contains("WorkspaceAgentStatusBuilder.status"), "Agent send progress should choose progress status through the progress planner.")
        XCTAssertTrue(composerText.contains("WorkspaceAgentSendStartPlanner.started"), "WorkspaceModel composer APIs should delegate composer send start transitions.")
        XCTAssertTrue(composerText.contains("WorkspaceAgentSendProgressPlanner.progress"), "WorkspaceModel composer APIs should delegate composer send progress transitions.")
        XCTAssertTrue(sendTerminalText.contains("WorkspaceComposerSendLifecycle.completed"), "Successful send completion should choose completed lifecycle through the terminal planner.")
        XCTAssertTrue(sendTerminalText.contains("WorkspaceComposerSendLifecycle.cancelled"), "Cancelled send completion should choose cancelled lifecycle through the terminal planner.")
        XCTAssertTrue(sendTerminalText.contains("WorkspaceComposerSendLifecycle.failed"), "Failed send completion should choose failed lifecycle through the terminal planner.")
        XCTAssertTrue(composerText.contains("WorkspaceAgentSendTerminalPlanner.completed"), "WorkspaceModel composer APIs should delegate composer send completion transitions.")
        XCTAssertTrue(composerText.contains("WorkspaceAgentSendTerminalPlanner.cancelled"), "WorkspaceModel composer APIs should delegate composer send cancellation transitions.")
        XCTAssertTrue(composerText.contains("WorkspaceAgentSendTerminalPlanner.failed"), "WorkspaceModel composer APIs should delegate composer send failure transitions.")
        XCTAssertTrue(modelText.contains("public internal(set) var composer: ComposerState"), "WorkspaceModel should own live composer state while focused same-module extensions may apply state transitions.")
        XCTAssertFalse(modelText.contains("public struct ComposerState"), "WorkspaceModel should not define composer UI state contracts.")
        XCTAssertFalse(modelText.contains("public struct MemoriesState"), "WorkspaceModel should not define memory-pane UI state contracts.")
        XCTAssertFalse(modelText.contains("public struct ActivityState"), "WorkspaceModel should not define activity-pane UI state contracts.")
    }

    func testActionableReviewCardsStayWiredThroughSurfaces() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let reviewExtensionText = try Self.appSourceText(named: "WorkspaceModelReview.swift")
        let toolCardSurfaceText = try Self.appSourceText(named: "QuillCodeToolCardSurface.swift")
        let toolCardViewText = try Self.appSourceText(named: "QuillCodeToolCardView.swift")
        let toolCardControlsText = try Self.appSourceText(named: "QuillCodeToolCardControls.swift")
        let toolArtifactViewsText = try Self.appSourceText(named: "QuillCodeToolArtifactViews.swift")
        let toolCardDetailsText = try Self.appSourceText(named: "QuillCodeToolCardDetailsView.swift")
        let transcriptViewText = try Self.appSourceText(named: "QuillCodeTranscriptView.swift")
        let workspaceViewText = try Self.appSourceText(named: "WorkspaceSwiftUIView.swift")
        let approvalPlannerText = try Self.appSourceText(named: "WorkspaceApprovalActionPlanner.swift")
        let htmlRendererText = try Self.appSourceText(named: "WorkspaceHTMLToolCardRenderer.swift")
        let desktopAppText = try Self.desktopSourceText(named: "QuillCodeDesktopApp.swift")
        let desktopControllerText = try Self.desktopSourceText(named: "QuillCodeDesktopController.swift")

        XCTAssertTrue(toolCardSurfaceText.contains("public struct ToolCardActionSurface"), "Tool-card actions should be first-class surface state.")
        XCTAssertTrue(toolCardSurfaceText.contains("public enum ToolCardReviewState"), "Tool-card review substates should be explicit surface state.")
        XCTAssertTrue(toolCardSurfaceText.contains("case edit"), "Approval-card actions should include an edit path for near-correct tool calls.")
        XCTAssertTrue(toolCardSurfaceText.contains("public var actions: [ToolCardActionSurface]"), "Tool-card state should carry available user actions.")
        XCTAssertTrue(toolCardSurfaceText.contains("public var reviewState: ToolCardReviewState"), "Tool-card state should carry semantic review state separately from subtitle copy.")
        XCTAssertTrue(toolCardSurfaceText.contains("statusDisplayLabel"), "Tool-card human-facing status copy should live on the surface state.")
        XCTAssertTrue(toolCardSurfaceText.contains("statusAccessibilityLabel"), "Tool-card accessibility status copy should live on the surface state.")
        XCTAssertTrue(transcriptViewText.contains("onToolCardAction"), "Transcript should route action taps out of row rendering.")
        XCTAssertTrue(toolCardViewText.contains("QuillCodeToolCardActionRow"), "Native cards should render action buttons directly on review cards.")
        XCTAssertTrue(toolCardViewText.contains("card.statusDisplayLabel"), "Native cards should not expose raw review status labels to users.")
        XCTAssertTrue(toolCardControlsText.contains("struct QuillCodeToolCardActionRow"), "Native tool-card action controls should live in the focused controls file.")
        XCTAssertTrue(toolCardControlsText.contains("struct QuillCodeToolStatusBadge"), "Native tool-card status controls should live in the focused controls file.")
        XCTAssertTrue(toolCardControlsText.contains("struct QuillCodeExecutionContextChip"), "Shared execution chips should live with tool-card controls.")
        XCTAssertTrue(toolCardControlsText.contains("struct QuillCodeExecutionRail"), "Shared execution rails should live with tool-card controls.")
        XCTAssertTrue(toolArtifactViewsText.contains("struct QuillCodeArtifactChip"), "Artifact chips should live in the focused artifact view file.")
        XCTAssertTrue(toolArtifactViewsText.contains("struct QuillCodeArtifactTextPreview"), "Text previews should live in the focused artifact view file.")
        XCTAssertTrue(toolArtifactViewsText.contains("struct QuillCodeArtifactDocumentPreview"), "Document previews should live in the focused artifact view file.")
        XCTAssertTrue(toolArtifactViewsText.contains("struct QuillCodeArtifactImagePreview"), "Image previews should live in the focused artifact view file.")
        XCTAssertTrue(toolCardDetailsText.contains("struct QuillCodeCodeBlock"), "Raw tool detail blocks should live in the focused details file.")
        XCTAssertFalse(toolCardViewText.contains("struct QuillCodeToolCardActionRow"), "Tool-card composition should not own action-control implementation.")
        XCTAssertFalse(toolCardViewText.contains("struct QuillCodeArtifactImagePreview"), "Tool-card composition should not own artifact-preview implementation.")
        XCTAssertFalse(toolCardViewText.contains("struct QuillCodeCodeBlock"), "Tool-card composition should not own raw details implementation.")
        XCTAssertTrue(workspaceViewText.contains("onToolCardAction"), "Workspace view should expose review-card actions to the host app.")
        XCTAssertTrue(reviewExtensionText.contains("func runToolCardAction"), "Workspace review extension should execute approved review-card actions.")
        XCTAssertTrue(htmlRendererText.contains("data-testid=\"tool-card-actions\""), "HTML harness should expose action buttons for Playwright.")
        XCTAssertTrue(htmlRendererText.contains("card.statusDisplayLabel"), "HTML cards should use the same human-facing status labels as native cards.")
        XCTAssertTrue(htmlRendererText.contains("card.reviewState.rawValue"), "HTML cards should expose review substate for E2E checks without parsing copy.")
        XCTAssertTrue(approvalPlannerText.contains("enum WorkspaceApprovalActionPlanner"), "Approval-card action planning should live in a focused helper.")
        XCTAssertTrue(approvalPlannerText.contains("static func pendingRequest"), "Approval request lookup should be directly testable outside the workspace model.")
        XCTAssertTrue(approvalPlannerText.contains("WorkspaceApprovalEditDraftBuilder"), "Approval-card edit draft generation should stay in the pure planner layer.")
        XCTAssertTrue(approvalPlannerText.contains("composerDraft"), "Approval-card edit actions should preload the composer instead of approving or skipping.")
        XCTAssertTrue(reviewExtensionText.contains("WorkspaceApprovalActionPlanner.plan"), "Workspace review extension should delegate approval-card action planning.")
        XCTAssertFalse(modelText.contains("func runToolCardAction"), "WorkspaceModel should not own review-card action APIs.")
        XCTAssertFalse(modelText.contains("private func pendingApprovalRequest"), "Workspace model should not own approval-request lookup.")
        XCTAssertFalse(modelText.contains("private func appendApprovalDecision"), "Workspace model should not own approval-decision event construction.")
        XCTAssertFalse(modelText.contains("approvalVerdict"), "Workspace model should not own tool-card action verdict mapping.")
        XCTAssertTrue(desktopAppText.contains("controller.runToolCardAction"), "Desktop app should connect UI actions to the controller.")
        XCTAssertTrue(desktopControllerText.contains("model.runToolCardAction"), "Desktop controller should forward review-card actions to the model.")
    }

    func testWorkspaceModelDelegatesExecutionContextSurfaceBuilding() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceExecutionContextSurfaceBuilder.swift")

        XCTAssertTrue(builderText.contains("struct WorkspaceExecutionContextSurfaceBuilder"), "Execution context enrichment should live in a focused builder.")
        XCTAssertTrue(builderText.contains("func enrichToolCards("), "Tool-card context enrichment should be directly testable.")
        XCTAssertTrue(builderText.contains("func enrichTimelineItems("), "Timeline context enrichment should be directly testable.")
        XCTAssertTrue(builderText.contains("static func isProjectExecutionTool"), "Project-execution tool classification should be directly testable.")
        XCTAssertTrue(modelText.contains("WorkspaceExecutionContextSurfaceBuilder("), "WorkspaceModel should delegate execution-context enrichment.")
        XCTAssertFalse(modelText.contains("private func enrichToolCards"), "WorkspaceModel should not own tool-card context enrichment.")
        XCTAssertFalse(modelText.contains("private func enrichTimelineItems"), "WorkspaceModel should not own timeline context enrichment.")
        XCTAssertFalse(modelText.contains("private static func isProjectExecutionTool"), "WorkspaceModel should not own project-execution tool classification.")
    }

    func testWorkspaceModelDelegatesProjectContextRefresh() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let composerText = try Self.appSourceText(named: "WorkspaceModelComposer.swift")
        let threadExtensionText = try Self.appSourceText(named: "WorkspaceModelThreads.swift")
        let worktreeExtensionText = try Self.appSourceText(named: "WorkspaceModelWorktrees.swift")
        let refresherText = try Self.appSourceText(named: "WorkspaceProjectContextRefresher.swift")

        XCTAssertTrue(refresherText.contains("enum WorkspaceProjectContextRefresher"), "Project context refresh should have a focused owner.")
        XCTAssertTrue(refresherText.contains("refreshLocalProjectMetadata"), "Local project metadata refresh should be directly testable.")
        XCTAssertTrue(refresherText.contains("refreshRemoteProjectContext"), "Remote project metadata refresh should be directly testable.")
        XCTAssertTrue(refresherText.contains("syncThreadContext"), "Thread instruction and memory sync should be directly testable.")
        XCTAssertTrue(refresherText.contains("syncThreadMemories"), "Saved-memory refresh should be directly testable.")
        XCTAssertTrue(refresherText.contains("threadCreationContext"), "Thread creation context assembly should be directly testable.")
        XCTAssertTrue(refresherText.contains("worktreeOpenContext"), "Worktree open context assembly should be directly testable.")
        XCTAssertTrue(refresherText.contains("static func globalMemories"), "Global memory loading should be directly testable.")
        XCTAssertTrue(modelText.contains("WorkspaceProjectContextRefresher.refreshLocalProjectMetadata"), "WorkspaceModel should delegate local project metadata refresh.")
        XCTAssertTrue(modelText.contains("WorkspaceProjectContextRefresher.refreshRemoteProjectContext"), "WorkspaceModel should delegate remote project metadata refresh.")
        XCTAssertTrue(composerText.contains("WorkspaceProjectContextRefresher.syncThreadContext"), "WorkspaceModel composer APIs should delegate thread context sync.")
        XCTAssertTrue(threadExtensionText.contains("WorkspaceProjectContextRefresher.threadCreationContext"), "WorkspaceModel thread APIs should delegate thread creation context assembly.")
        XCTAssertTrue(worktreeExtensionText.contains("WorkspaceProjectContextRefresher.worktreeOpenContext"), "WorkspaceModel worktree APIs should delegate worktree open context assembly.")
        XCTAssertFalse(modelText.contains("WorkspaceProjectContextRefresher.syncThreadContext"), "WorkspaceModel.swift should not own agent-send thread context sync.")
        XCTAssertFalse(modelText.contains("WorkspaceProjectContextRefresher.worktreeOpenContext"), "WorkspaceModel.swift should not own worktree open context assembly.")
        XCTAssertFalse(modelText.contains("WorkspaceProjectMetadataLoader.loadLocal(from: rootURL)"), "WorkspaceModel should not own refresh-time local project metadata loading.")
        XCTAssertFalse(modelText.contains("WorkspaceProjectMetadataLoader.loadRemote"), "WorkspaceModel should not own remote project metadata loading.")
        XCTAssertFalse(modelText.contains("WorkspaceMemoryEngine.loadGlobal(from:"), "WorkspaceModel should not own global memory loading.")
        XCTAssertFalse(modelText.contains("contextResolver.instructions(for:"), "WorkspaceModel should not read instruction snapshots directly from the context resolver.")
        XCTAssertFalse(modelText.contains("contextResolver.memoryNotes(for:"), "WorkspaceModel should not read memory snapshots directly from the context resolver.")
        XCTAssertFalse(modelText.contains("thread.instructions = contextResolver.instructions"), "WorkspaceModel should not directly sync thread instructions from the resolver.")
        XCTAssertFalse(modelText.contains("thread.memories = contextResolver.memoryNotes"), "WorkspaceModel should not directly sync thread memories from the resolver.")
    }

    func testWorkspaceModelDelegatesThreadSeedBuilding() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let seedBuilderText = try Self.appSourceText(named: "WorkspaceThreadSeedBuilder.swift")
        let creationText = try Self.appSourceText(named: "WorkspaceThreadCreationEngine.swift")

        XCTAssertTrue(seedBuilderText.contains("struct WorkspaceThreadSeedBuilder"), "Fork and compact seed construction should live in a focused builder.")
        XCTAssertTrue(seedBuilderText.contains("static func title(fromUserPrompt"), "Thread title seeding should be directly testable.")
        XCTAssertTrue(seedBuilderText.contains("static func forkSeedMessages"), "Fork seed construction should be directly testable.")
        XCTAssertTrue(seedBuilderText.contains("static func compactSeedMessages"), "Compact seed construction should be directly testable.")
        XCTAssertTrue(creationText.contains("WorkspaceThreadSeedBuilder.forkSeedMessages"), "Thread creation should delegate fork seeding.")
        XCTAssertTrue(creationText.contains("WorkspaceThreadSeedBuilder.compactSeedMessages"), "Thread creation should delegate context compaction seeding.")
        XCTAssertFalse(modelText.contains("private static func forkSeedMessages"), "WorkspaceModel should not own fork seed construction.")
        XCTAssertFalse(modelText.contains("private static func compactSeedMessages"), "WorkspaceModel should not own compact seed construction.")
        XCTAssertFalse(modelText.contains("private static func compactSummaryMessage"), "WorkspaceModel should not own compact summary formatting.")
    }

    func testWorkspaceModelDelegatesThreadCreationRecords() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let threadExtensionText = try Self.appSourceText(named: "WorkspaceModelThreads.swift")
        let creationText = try Self.appSourceText(named: "WorkspaceThreadCreationEngine.swift")

        XCTAssertTrue(threadExtensionText.contains("extension QuillCodeWorkspaceModel"), "Thread APIs should live in a focused WorkspaceModel extension.")
        XCTAssertTrue(creationText.contains("struct WorkspaceThreadCreationContext"), "New-thread context should live beside the focused creation engine.")
        XCTAssertTrue(creationText.contains("struct WorkspaceThreadCreationEngine"), "Thread record construction should live in a focused engine.")
        XCTAssertTrue(creationText.contains("static func newThread"), "New chat construction should be directly testable.")
        XCTAssertTrue(creationText.contains("static func forkThread"), "Fork thread construction should be directly testable.")
        XCTAssertTrue(creationText.contains("static func compactThread"), "Compact thread construction should be directly testable.")
        XCTAssertTrue(creationText.contains("static func duplicateThread"), "Duplicate thread construction should be directly testable.")
        XCTAssertTrue(threadExtensionText.contains("WorkspaceThreadCreationEngine.newThread"), "WorkspaceModel thread APIs should delegate new chat construction.")
        XCTAssertTrue(threadExtensionText.contains("WorkspaceThreadCreationEngine.forkThread"), "WorkspaceModel thread APIs should delegate fork construction.")
        XCTAssertTrue(threadExtensionText.contains("WorkspaceThreadCreationEngine.compactThread"), "WorkspaceModel thread APIs should delegate compact construction.")
        XCTAssertTrue(threadExtensionText.contains("WorkspaceThreadCreationEngine.duplicateThread"), "WorkspaceModel thread APIs should delegate duplicate construction.")
        XCTAssertFalse(modelText.contains("public func newChat"), "WorkspaceModel.swift should not own thread creation API bodies.")
        XCTAssertFalse(modelText.contains("public func forkFromLast"), "WorkspaceModel.swift should not own fork API bodies.")
        XCTAssertFalse(modelText.contains("public func compactContext"), "WorkspaceModel.swift should not own compact API bodies.")
        XCTAssertFalse(modelText.contains("public func duplicateThread"), "WorkspaceModel.swift should not own duplicate API bodies.")
        XCTAssertFalse(modelText.contains("title: \"Fork:"), "WorkspaceModel should not own fork title copy.")
        XCTAssertFalse(modelText.contains("title: \"Compact:"), "WorkspaceModel should not own compact title copy.")
        XCTAssertFalse(modelText.contains("title: \"Copy:"), "WorkspaceModel should not own duplicate title copy.")
    }

    func testWorkspaceModelDelegatesThreadLifecycleTransitions() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let threadExtensionText = try Self.appSourceText(named: "WorkspaceModelThreads.swift")
        let lifecycleText = try Self.appSourceText(named: "WorkspaceThreadLifecycleEngine.swift")
        let persistenceText = try Self.appSourceText(named: "WorkspaceThreadPersistence.swift")

        XCTAssertTrue(lifecycleText.contains("struct WorkspaceThreadLifecycleEngine"), "Thread lifecycle transitions should live in a focused engine.")
        XCTAssertTrue(persistenceText.contains("struct WorkspaceThreadPersistence"), "Thread persistence and timestamped mutation should live in a focused helper.")
        XCTAssertTrue(persistenceText.contains("func mutate("), "Timestamped thread mutation should be directly testable outside WorkspaceModel.")
        XCTAssertTrue(persistenceText.contains("func saveOrThrow"), "Throwing save semantics should stay isolated from direct JSONThreadStore calls.")
        XCTAssertTrue(lifecycleText.contains("static func renameThread"), "Thread rename mutation should be directly testable.")
        XCTAssertTrue(lifecycleText.contains("static func archiveThread"), "Thread archive fallback selection should be directly testable.")
        XCTAssertTrue(lifecycleText.contains("static func unarchiveThread"), "Thread unarchive mutation should be directly testable.")
        XCTAssertTrue(lifecycleText.contains("static func deleteThread"), "Thread delete fallback selection should be directly testable.")
        XCTAssertTrue(lifecycleText.contains("static func applyAgentRunThreadUpdate"), "Agent-run thread upsert and fallback selection should be directly testable.")
        XCTAssertTrue(threadExtensionText.contains("WorkspaceThreadLifecycleEngine.renameThread"), "WorkspaceModel thread APIs should delegate thread rename mutation.")
        XCTAssertTrue(threadExtensionText.contains("WorkspaceThreadLifecycleEngine.archiveThread"), "WorkspaceModel thread APIs should delegate thread archive mutation.")
        XCTAssertTrue(threadExtensionText.contains("WorkspaceThreadLifecycleEngine.deleteThread"), "WorkspaceModel thread APIs should delegate thread delete mutation.")
        XCTAssertTrue(modelText.contains("WorkspaceThreadLifecycleEngine.applyAgentRunThreadUpdate"), "WorkspaceModel should delegate agent-run thread upsert and fallback selection.")
        XCTAssertTrue(modelText.contains("WorkspaceThreadPersistence(store: threadStore)"), "WorkspaceModel should bridge its existing initializer to the thread persistence helper.")
        XCTAssertTrue(modelText.contains("threadPersistence.mutate"), "WorkspaceModel should delegate timestamped thread mutation.")
        XCTAssertFalse(modelText.contains("public func renameThread"), "WorkspaceModel.swift should not own thread rename API bodies.")
        XCTAssertFalse(modelText.contains("public func archiveThread"), "WorkspaceModel.swift should not own thread archive API bodies.")
        XCTAssertFalse(modelText.contains("public func unarchiveThread"), "WorkspaceModel.swift should not own thread unarchive API bodies.")
        XCTAssertFalse(modelText.contains("public func deleteThread"), "WorkspaceModel.swift should not own thread delete API bodies.")
        XCTAssertFalse(modelText.contains("thread.title = trimmed"), "WorkspaceModel should not own thread rename mutation.")
        XCTAssertFalse(modelText.contains("thread.isArchived = true"), "WorkspaceModel should not own thread archive mutation.")
        XCTAssertFalse(modelText.contains("thread.isArchived = false"), "WorkspaceModel should not own thread unarchive mutation.")
        XCTAssertFalse(modelText.contains("private func upsertThread"), "WorkspaceModel should not own generic thread upsert mutation.")
        XCTAssertFalse(modelText.contains("private func selectUpdatedThread"), "WorkspaceModel should not own agent-run fallback selection mutation.")
        XCTAssertFalse(modelText.contains("threadStore?.save"), "WorkspaceModel should not call JSONThreadStore save directly.")
        XCTAssertFalse(modelText.contains("threadStore?.delete"), "WorkspaceModel should not call JSONThreadStore delete directly.")
    }

    func testWorkspaceModelDelegatesConfigurationTransitions() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let configurationExtensionText = try Self.appSourceText(named: "WorkspaceModelConfiguration.swift")
        let configurationText = try Self.appSourceText(named: "WorkspaceConfigurationEngine.swift")

        XCTAssertTrue(configurationText.contains("struct WorkspaceConfigurationEngine"), "Workspace configuration transitions should live in a focused engine.")
        XCTAssertTrue(configurationText.contains("static func setModel"), "Model selection should be directly testable.")
        XCTAssertTrue(configurationText.contains("static func setMode"), "Mode selection should be directly testable.")
        XCTAssertTrue(configurationText.contains("static func toggleFavorite"), "Favorite model mutation should be directly testable.")
        XCTAssertTrue(configurationText.contains("static func normalizedCatalog"), "Catalog replacement should be directly testable.")
        XCTAssertTrue(configurationText.contains("static func applySettings"), "Settings application should be directly testable.")
        XCTAssertTrue(configurationText.contains("static func syncThread"), "Selected-thread config syncing should be directly testable.")
        XCTAssertTrue(configurationExtensionText.contains("public func setMode"), "Mode selection should live in the focused configuration extension.")
        XCTAssertTrue(configurationExtensionText.contains("public func setModel"), "Model selection should live in the focused configuration extension.")
        XCTAssertTrue(configurationExtensionText.contains("public func toggleModelFavorite"), "Favorite model mutation should live in the focused configuration extension.")
        XCTAssertTrue(configurationExtensionText.contains("public func setModelCatalog"), "Catalog replacement should live in the focused configuration extension.")
        XCTAssertTrue(configurationExtensionText.contains("public func applySettings"), "Settings application should live in the focused configuration extension.")
        XCTAssertTrue(configurationExtensionText.contains("public func applyRuntime"), "Runtime application should live in the focused configuration extension.")
        XCTAssertTrue(configurationExtensionText.contains("public func setAgentStatus"), "Agent status overrides should live in the focused configuration extension.")
        XCTAssertTrue(configurationExtensionText.contains("WorkspaceConfigurationEngine.setModel"), "WorkspaceModelConfiguration should delegate model selection.")
        XCTAssertTrue(configurationExtensionText.contains("WorkspaceConfigurationEngine.setMode"), "WorkspaceModelConfiguration should delegate mode selection.")
        XCTAssertTrue(configurationExtensionText.contains("WorkspaceConfigurationEngine.toggleFavorite"), "WorkspaceModelConfiguration should delegate favorite mutation.")
        XCTAssertTrue(configurationExtensionText.contains("WorkspaceConfigurationEngine.normalizedCatalog"), "WorkspaceModelConfiguration should delegate catalog normalization.")
        XCTAssertTrue(configurationExtensionText.contains("WorkspaceConfigurationEngine.applySettings"), "WorkspaceModelConfiguration should delegate settings application.")
        XCTAssertFalse(modelText.contains("public func setMode"), "WorkspaceModel.swift should not own mode selection API bodies.")
        XCTAssertFalse(modelText.contains("public func setModel"), "WorkspaceModel.swift should not own model selection API bodies.")
        XCTAssertFalse(modelText.contains("public func toggleModelFavorite"), "WorkspaceModel.swift should not own favorite model API bodies.")
        XCTAssertFalse(modelText.contains("public func setModelCatalog"), "WorkspaceModel.swift should not own model catalog API bodies.")
        XCTAssertFalse(modelText.contains("public func applySettings"), "WorkspaceModel.swift should not own settings application API bodies.")
        XCTAssertFalse(modelText.contains("public func applyRuntime"), "WorkspaceModel.swift should not own runtime application API bodies.")
        XCTAssertFalse(modelText.contains("public func setAgentStatus"), "WorkspaceModel.swift should not own agent status override API bodies.")
        XCTAssertFalse(modelText.contains("TrustedRouterDefaults.normalizedDefaultModelID(model)"), "WorkspaceModel should not own model ID normalization.")
        XCTAssertFalse(modelText.contains("root.config.favoriteModels.append"), "WorkspaceModel should not mutate favorite-model arrays directly.")
        XCTAssertFalse(modelText.contains("TrustedRouterDefaults.normalizedModelCatalog(models)"), "WorkspaceModel should not own catalog normalization.")
        XCTAssertFalse(modelText.contains("root.trustedRouterAPIKeyConfigured = trustedRouterAPIKeyConfigured"), "WorkspaceModel should not own settings application details.")
    }

    func testWorkspaceConfigurationIntegrationTestsOwnModelConfigurationFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let configurationIntegrationTests = try Self.appTestSourceText(named: "WorkspaceConfigurationIntegrationTests.swift")

        XCTAssertTrue(configurationIntegrationTests.contains("testModeAndModelUpdateSelectedThreadAndTopBar"), "Mode/model top-bar integration should live in focused configuration integration tests.")
        XCTAssertTrue(configurationIntegrationTests.contains("testToggleModelFavoriteUpdatesConfigAndSurface"), "Favorite model config/surface integration should live in focused configuration integration tests.")
        XCTAssertTrue(configurationIntegrationTests.contains("testApplySettingsUpdatesConfigThreadAndSettingsSurface"), "Settings config/thread/surface integration should live in focused configuration integration tests.")
        XCTAssertTrue(configurationIntegrationTests.contains("testBootstrapLoadsConfigAndPersistedThreads"), "Bootstrap config/thread/project/automation persistence integration should live in focused configuration integration tests.")
        XCTAssertTrue(configurationIntegrationTests.contains("testBootstrapPersistsAndClearsTrustedRouterAPIKey"), "TrustedRouter API key persistence integration should live in focused configuration integration tests.")

        XCTAssertFalse(modelTests.contains("testModeAndModelUpdateSelectedThreadAndTopBar"), "WorkspaceModelTests should not own mode/model surface integration flows.")
        XCTAssertFalse(modelTests.contains("testToggleModelFavoriteUpdatesConfigAndSurface"), "WorkspaceModelTests should not own favorite model config/surface integration flows.")
        XCTAssertFalse(modelTests.contains("testApplySettingsUpdatesConfigThreadAndSettingsSurface"), "WorkspaceModelTests should not own settings config/thread/surface integration flows.")
        XCTAssertFalse(modelTests.contains("testBootstrapLoadsConfigAndPersistedThreads"), "WorkspaceModelTests should not own bootstrap config/thread/project/automation persistence integration.")
        XCTAssertFalse(modelTests.contains("testBootstrapPersistsAndClearsTrustedRouterAPIKey"), "WorkspaceModelTests should not own TrustedRouter API key persistence integration.")
    }

    func testWorkspaceModelDelegatesRetryPlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let composerText = try Self.appSourceText(named: "WorkspaceModelComposer.swift")
        let retryPlannerText = try Self.appSourceText(named: "WorkspaceRetryPlanner.swift")
        let retryPlannerTests = try Self.appTestSourceText(named: "WorkspaceRetryPlannerTests.swift")

        XCTAssertTrue(retryPlannerText.contains("enum WorkspaceRetryPlanner"), "Retry planning should live in a focused helper.")
        XCTAssertTrue(retryPlannerText.contains("static func canRetryLastUserTurn"), "Retry availability should be directly testable.")
        XCTAssertTrue(retryPlannerText.contains("static func retryDraft"), "Retry draft selection should be directly testable.")
        XCTAssertTrue(composerText.contains("WorkspaceRetryPlanner.canRetryLastUserTurn"), "WorkspaceModel composer APIs should delegate retry availability.")
        XCTAssertTrue(composerText.contains("WorkspaceRetryPlanner.retryDraft"), "WorkspaceModel composer APIs should delegate retry draft selection.")
        XCTAssertTrue(retryPlannerTests.contains("testRetryDraftUsesLatestNonEmptyUserMessageAndPreservesOriginalText"), "Retry draft behavior should have focused coverage.")
        XCTAssertTrue(retryPlannerTests.contains("testRetryRequiresUserMessageAndIdleComposer"), "Retry availability should have focused coverage.")
        XCTAssertFalse(modelText.contains("messages.last(where:"), "WorkspaceModel should not scan transcript messages for retry drafts.")
        XCTAssertFalse(modelText.contains("messages.contains {"), "WorkspaceModel should not own retry availability scans.")
        XCTAssertFalse(modelText.contains("WorkspaceRetryPlanner.canRetryLastUserTurn"), "WorkspaceModel.swift should not own retry availability APIs.")
    }

    func testWorkspaceActivityIntegrationTestsOwnModelActivityFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let activityIntegrationTests = try Self.appTestSourceText(named: "WorkspaceActivityIntegrationTests.swift")

        XCTAssertTrue(activityIntegrationTests.contains("testPlanUpdateToolRecordsNormalizedActivityPlan"), "Plan-update activity integration should live in focused activity tests.")
        XCTAssertTrue(activityIntegrationTests.contains("testPlanUpdateToolRejectsMultipleRunningSteps"), "Plan-update rejection integration should live in focused activity tests.")
        XCTAssertFalse(modelTests.contains("testPlanUpdateToolRecordsNormalizedActivityPlan"), "WorkspaceModelTests should not own plan-update activity integration flows.")
        XCTAssertFalse(modelTests.contains("testPlanUpdateToolRejectsMultipleRunningSteps"), "WorkspaceModelTests should not own plan-update rejection integration flows.")
    }

    func testWorkspaceActivitySurfaceUsesFocusedBuilderAndSectionTypes() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceActivitySurface.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceActivitySurfaceBuilder.swift")
        let sectionText = try Self.appSourceText(named: "WorkspaceActivitySectionSurface.swift")
        let planBuilderText = try Self.appSourceText(named: "WorkspaceActivityPlanSurfaceBuilder.swift")
        let eventBuilderText = try Self.appSourceText(named: "WorkspaceActivityEventSurfaceBuilder.swift")
        let sourceBuilderText = try Self.appSourceText(named: "WorkspaceActivitySourceSurfaceBuilder.swift")
        let handoffBuilderText = try Self.appSourceText(named: "WorkspaceActivityHandoffSummaryBuilder.swift")
        let textHelperText = try Self.appSourceText(named: "WorkspaceActivityText.swift")
        let statusText = try Self.appSourceText(named: "WorkspaceActivityStatusLabel.swift")

        XCTAssertTrue(surfaceText.contains("public struct WorkspaceActivitySurface"), "Activity surface payload should keep the public DTO entry point.")
        XCTAssertTrue(surfaceText.contains("WorkspaceActivitySurfaceBuilder.sections"), "Activity surface should delegate section construction.")
        XCTAssertTrue(surfaceText.contains("WorkspaceActivitySurfaceBuilder.planItems"), "Activity surface should delegate derived task-plan rows.")
        XCTAssertTrue(builderText.contains("enum WorkspaceActivitySurfaceBuilder"), "Activity derivation should live in a focused builder.")
        XCTAssertTrue(builderText.contains("WorkspaceActivityPlanSurfaceBuilder.fallbackItems"), "Activity builder should delegate fallback plan rows.")
        XCTAssertTrue(builderText.contains("WorkspaceActivityPlanSurfaceBuilder.authoredItems"), "Activity builder should delegate authored plan rows.")
        XCTAssertTrue(builderText.contains("WorkspaceActivityEventSurfaceBuilder.recentSteps"), "Activity builder should delegate event-row projection.")
        XCTAssertTrue(builderText.contains("WorkspaceActivitySourceSurfaceBuilder.items"), "Activity builder should delegate source-row projection.")
        XCTAssertTrue(builderText.contains("WorkspaceActivityHandoffSummaryBuilder.summary"), "Activity builder should delegate handoff summary copy.")
        XCTAssertTrue(planBuilderText.contains("enum WorkspaceActivityPlanSurfaceBuilder"), "Plan-row derivation should have a focused owner.")
        XCTAssertTrue(planBuilderText.contains("static func authoredItems"), "Authored plan rows should stay beside fallback plan rows.")
        XCTAssertTrue(planBuilderText.contains("private static func reviewState"), "Fallback plan review-state copy should stay in the plan builder.")
        XCTAssertTrue(eventBuilderText.contains("enum WorkspaceActivityEventSurfaceBuilder"), "Event-row projection should have a focused owner.")
        XCTAssertTrue(eventBuilderText.contains("private static func eventKindLabel"), "Event labeling should stay beside event-row projection.")
        XCTAssertTrue(sourceBuilderText.contains("enum WorkspaceActivitySourceSurfaceBuilder"), "Instruction and memory source rows should have a focused owner.")
        XCTAssertTrue(handoffBuilderText.contains("enum WorkspaceActivityHandoffSummaryBuilder"), "Handoff summary copy should have a focused owner.")
        XCTAssertTrue(textHelperText.contains("enum WorkspaceActivityText"), "Shared activity text formatting should not be copied between builders.")
        XCTAssertTrue(statusText.contains("enum ActivityStatusLabel"), "Activity status labels should be shared by focused builders.")
        XCTAssertTrue(sectionText.contains("public enum ActivitySectionKind"), "Activity section metadata should live beside section DTOs.")
        XCTAssertTrue(sectionText.contains("public struct ActivitySectionSurface"), "Activity section DTOs should live outside the root surface file.")
        XCTAssertTrue(sectionText.contains("public struct ActivityItemSurface"), "Activity item DTOs should live outside the root surface file.")
        XCTAssertFalse(surfaceText.contains("private static func planItems"), "Activity surface should not own plan derivation.")
        XCTAssertFalse(surfaceText.contains("private static func recentSteps"), "Activity surface should not own event-row derivation.")
        XCTAssertFalse(surfaceText.contains("public enum ActivitySectionKind"), "Activity surface should not own section metadata.")
        XCTAssertFalse(builderText.contains("private static func eventKindLabel"), "Top-level activity builder should not own event labeling.")
        XCTAssertFalse(builderText.contains("private static func reviewState"), "Top-level activity builder should not own fallback plan review state.")
        XCTAssertFalse(builderText.contains("Latest answer:"), "Top-level activity builder should not own handoff summary prose.")
    }

    func testWorkspaceToolCardIntegrationTestsOwnModelToolCardFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let toolCardIntegrationTests = try Self.appTestSourceText(named: "WorkspaceToolCardIntegrationTests.swift")

        XCTAssertTrue(toolCardIntegrationTests.contains("testToolCardsRepresentActionableApprovalReview"), "Tool-card review projection should live in focused tool-card integration tests.")
        XCTAssertTrue(toolCardIntegrationTests.contains("testToolCardApprovalActionRecordsDecisionAndRunsTool"), "Tool-card approval execution should live in focused tool-card integration tests.")
        XCTAssertTrue(toolCardIntegrationTests.contains("testToolCardsRepresentStoppedActiveToolAsFailed"), "Stopped tool-card projection should live in focused tool-card integration tests.")
        XCTAssertFalse(modelTests.contains("testToolCardsRepresentActionableApprovalReview"), "WorkspaceModelTests should not own actionable approval-card projection.")
        XCTAssertFalse(modelTests.contains("testToolCardApprovalActionRecordsDecisionAndRunsTool"), "WorkspaceModelTests should not own approval-card execution integration.")
        XCTAssertFalse(modelTests.contains("testToolCardsRepresentStoppedActiveToolAsFailed"), "WorkspaceModelTests should not own stopped tool-card projection.")
    }

    func testWorkspaceModelTestsRemainRetired() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")

        XCTAssertTrue(modelTests.contains("Intentionally empty"), "WorkspaceModelTests should stay as a visible retirement marker.")
        XCTAssertFalse(modelTests.contains("func test"), "New workspace integration coverage should use a focused feature test suite, not WorkspaceModelTests.")
    }

    func testFocusedWorkspaceUnitSuitesUseSharedTemporaryDirectorySupport() throws {
        let supportText = try Self.appTestSourceText(named: "WorkspaceModelIntegrationTestSupport.swift")
        XCTAssertTrue(supportText.contains("extension XCTestCase"), "App integration temp helpers should live on XCTestCase so they can register teardown cleanup.")
        XCTAssertTrue(supportText.contains("func makeTempDirectory() throws -> URL"), "Legacy app integration tests should route through the shared temp-directory wrapper.")
        XCTAssertTrue(supportText.contains("makeQuillCodeTestDirectory()"), "App integration temp helpers should delegate to the teardown-backed helper.")

        let suiteNames = [
            "WorkspaceAgentRunContextBuilderTests.swift",
            "WorkspaceAgentSendSessionFactoryTests.swift",
            "WorkspaceAgentSendSessionTests.swift",
            "WorkspaceMemoryEngineTests.swift",
            "WorkspaceTerminalEngineTests.swift",
            "WorkspaceToolCallExecutorTests.swift"
        ]

        for suiteName in suiteNames {
            let suiteText = try Self.appTestSourceText(named: suiteName)
            XCTAssertTrue(
                suiteText.contains("makeQuillCodeTestDirectory()"),
                "\(suiteName) should use the shared teardown-backed test directory helper."
            )
            XCTAssertFalse(
                suiteText.contains("private func temporaryDirectory"),
                "\(suiteName) should not reintroduce a private temp-directory helper."
            )
            XCTAssertFalse(
                suiteText.contains("FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)"),
                "\(suiteName) should not build untracked temp directories inline."
            )
        }

        let integrationSuiteNames = [
            "WorkspaceBrowserIntegrationTests.swift",
            "WorkspaceBrowserLocationResolverTests.swift",
            "WorkspaceCommandPlanExecutorTests.swift",
            "WorkspaceRemoteProjectToolExecutorTests.swift",
            "WorkspaceSlashCommandIntegrationTests.swift",
            "WorkspaceSurfaceTests.swift"
        ]
        for suiteName in integrationSuiteNames {
            let suiteText = try Self.appTestSourceText(named: suiteName)
            XCTAssertFalse(
                suiteText.contains("private func makeTempDirectory()"),
                "\(suiteName) should use WorkspaceModelIntegrationTestSupport.makeTempDirectory()."
            )
            XCTAssertFalse(
                suiteText.contains("NSTemporaryDirectory()"),
                "\(suiteName) should not build untracked temp directories inline."
            )
            XCTAssertFalse(
                suiteText.contains("FileManager.default.temporaryDirectory"),
                "\(suiteName) should not build untracked temp directories inline."
            )
        }
    }

    func testWorkspaceModelDelegatesStatusTextAndLabels() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let composerText = try Self.appSourceText(named: "WorkspaceModelComposer.swift")
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceStatusTextBuilder.swift")
        let contextBuilderText = try Self.appSourceText(named: "WorkspaceStatusContextBuilder.swift")
        let topBarBuilderText = try Self.appSourceText(named: "WorkspaceTopBarSurfaceBuilder.swift")
        let topBarStateBuilderText = try Self.appSourceText(named: "WorkspaceTopBarStateBuilder.swift")
        let slashTranscriptText = try Self.appSourceText(named: "WorkspaceSlashCommandTranscriptPlanner.swift")

        XCTAssertTrue(builderText.contains("struct WorkspaceStatusTextBuilder"), "Workspace status text and labels should live in a focused builder.")
        XCTAssertTrue(contextBuilderText.contains("enum WorkspaceStatusContextBuilder"), "Workspace status context assembly should live in a focused builder.")
        XCTAssertTrue(contextBuilderText.contains("static func context"), "Workspace status context assembly should be directly testable.")
        XCTAssertTrue(builderText.contains("static func statusText"), "Slash status copy should be directly testable.")
        XCTAssertTrue(builderText.contains("static func topBarSubtitle"), "Top-bar subtitle copy should be directly testable.")
        XCTAssertTrue(builderText.contains("static func instructionLabel"), "Instruction status labels should be directly testable.")
        XCTAssertTrue(builderText.contains("static func memoryLabel"), "Memory status labels should be directly testable.")
        XCTAssertTrue(builderText.contains("static func modeLabel"), "Mode labels should be shared by status and UI surfaces.")
        XCTAssertTrue(composerText.contains("WorkspaceStatusTextBuilder.statusText"), "WorkspaceModel composer APIs should delegate /status copy.")
        XCTAssertTrue(composerText.contains("WorkspaceStatusContextBuilder.context"), "WorkspaceModel composer APIs should delegate /status context assembly.")
        XCTAssertTrue(slashTranscriptText.contains("WorkspaceStatusTextBuilder.modeLabel"), "Slash mode transcript copy should delegate shared mode labels.")
        XCTAssertTrue(topBarBuilderText.contains("WorkspaceStatusTextBuilder.topBarSubtitle"), "Top-bar builder should delegate top-bar subtitles.")
        XCTAssertTrue(topBarBuilderText.contains("WorkspaceStatusTextBuilder.instructionLabel"), "Top-bar builder should delegate instruction labels.")
        XCTAssertTrue(topBarBuilderText.contains("WorkspaceStatusTextBuilder.memoryLabel"), "Top-bar builder should delegate memory labels.")
        XCTAssertTrue(topBarStateBuilderText.contains("enum WorkspaceTopBarStateBuilder"), "Top-bar state assembly should live in a focused builder.")
        XCTAssertTrue(modelText.contains("WorkspaceTopBarStateBuilder.state"), "WorkspaceModel should delegate top-bar state assembly.")
        XCTAssertFalse(modelText.contains("root.topBar = TopBarState("), "WorkspaceModel should not assemble top-bar state inline.")
        XCTAssertFalse(modelText.contains("WorkspaceStatusContext("), "WorkspaceModel should not assemble /status context inline.")
        XCTAssertFalse(modelText.contains("WorkspaceStatusTextBuilder.statusText"), "WorkspaceModel.swift should not own slash status text assembly.")
        XCTAssertFalse(surfaceText.contains("WorkspaceStatusTextBuilder.topBarSubtitle"), "WorkspaceSurface should not own top-bar subtitles.")
        XCTAssertFalse(surfaceText.contains("WorkspaceStatusTextBuilder.instructionLabel"), "WorkspaceSurface should not own instruction labels.")
        XCTAssertFalse(surfaceText.contains("WorkspaceStatusTextBuilder.memoryLabel"), "WorkspaceSurface should not own memory labels.")
        XCTAssertFalse(modelText.contains("No project instructions"), "WorkspaceModel should not own instruction status copy.")
        XCTAssertFalse(modelText.contains("No memories"), "WorkspaceModel should not own memory status copy.")
        XCTAssertFalse(modelText.contains("static func instructionStatusLabel"), "WorkspaceModel should not own instruction status labels.")
        XCTAssertFalse(modelText.contains("static func memoryStatusLabel"), "WorkspaceModel should not own memory status labels.")
        XCTAssertFalse(surfaceText.contains("static func modeLabel"), "WorkspaceSurface should not own mode label copy.")
    }

    func testWorkspaceModelDelegatesContextResolving() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let resolverText = try Self.appSourceText(named: "WorkspaceContextResolver.swift")
        let refresherText = try Self.appSourceText(named: "WorkspaceProjectContextRefresher.swift")
        let matcherText = try Self.appSourceText(named: "LocalEnvironmentActionMatcher.swift")

        XCTAssertTrue(resolverText.contains("struct WorkspaceActiveContextSources"), "Active workspace context source records should live beside the resolver.")
        XCTAssertTrue(resolverText.contains("struct WorkspaceContextResolver"), "Workspace context lookup should live in a focused resolver.")
        XCTAssertTrue(matcherText.contains("enum LocalEnvironmentActionMatcher"), "Local environment action alias matching should live in a focused matcher.")
        XCTAssertTrue(resolverText.contains("func instructions(for projectID:"), "Project instruction lookup should be directly testable.")
        XCTAssertTrue(resolverText.contains("func memoryNotes(for projectID:"), "Global/project memory merging should be directly testable.")
        XCTAssertTrue(resolverText.contains("func activeSources(for thread:"), "Active instruction and memory fallback should be directly testable.")
        XCTAssertTrue(resolverText.contains("func selectedLocalAction(withID"), "Local action ID lookup should be directly testable.")
        XCTAssertTrue(resolverText.contains("func selectedLocalAction(matching"), "Local action alias matching should be directly testable.")
        XCTAssertTrue(resolverText.contains("LocalEnvironmentActionMatcher.action(withID"), "Workspace context resolver should delegate local action ID matching.")
        XCTAssertTrue(resolverText.contains("LocalEnvironmentActionMatcher.action(matching"), "Workspace context resolver should delegate local action alias matching.")
        XCTAssertTrue(surfaceText.contains("WorkspaceContextResolver("), "WorkspaceSurface should delegate active context-source lookup through the resolver.")
        XCTAssertTrue(refresherText.contains("WorkspaceContextResolver("), "Project context refresher should delegate thread context snapshots through the resolver.")
        XCTAssertFalse(modelText.contains("WorkspaceContextResolver("), "WorkspaceModel should not retain a dead context resolver property.")
        XCTAssertFalse(modelText.contains("private func instructions(for projectID"), "WorkspaceModel should not own project instruction lookup.")
        XCTAssertFalse(modelText.contains("private func memoryNotes(for projectID"), "WorkspaceModel should not own memory merging.")
        XCTAssertFalse(modelText.contains("private func localAction(withID"), "WorkspaceModel should not own local action ID lookup.")
        XCTAssertFalse(modelText.contains("private func localAction(matching"), "WorkspaceModel should not own local action matching.")
        XCTAssertFalse(modelText.contains("private static func normalizedActionName"), "WorkspaceModel should not own local action alias normalization.")
        XCTAssertFalse(surfaceText.contains("thread.instructions.isEmpty"), "WorkspaceSurface should not own thread/project instruction fallback.")
        XCTAssertFalse(surfaceText.contains("thread.memories.isEmpty"), "WorkspaceSurface should not own thread/project memory fallback.")
        XCTAssertFalse(surfaceText.contains("selectedProject?.instructions ?? []"), "WorkspaceSurface should not own project instruction fallback.")
        XCTAssertFalse(surfaceText.contains("root.globalMemories +"), "WorkspaceSurface should not own global/project memory merging.")
    }

    func testWorkspaceModelDelegatesAgentProgressStatusCopy() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let composerText = try Self.appSourceText(named: "WorkspaceModelComposer.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceAgentStatusBuilder.swift")
        let progressPlannerText = try Self.appSourceText(named: "WorkspaceAgentSendProgressPlanner.swift")

        XCTAssertTrue(builderText.contains("struct WorkspaceAgentStatusBuilder"), "Agent progress status copy should live in a focused builder.")
        XCTAssertTrue(builderText.contains("static func status(for thread: ChatThread)"), "Thread-level progress status should be directly testable.")
        XCTAssertTrue(builderText.contains("static func status(for event: ThreadEvent?)"), "Event-level progress status should be directly testable.")
        XCTAssertTrue(builderText.contains("AgentRunner.streamingNotice"), "Streaming status should remain tied to the agent streaming notice contract.")
        XCTAssertTrue(progressPlannerText.contains("struct WorkspaceAgentSendProgressPlan"), "Live agent progress should have a typed plan.")
        XCTAssertTrue(progressPlannerText.contains("enum WorkspaceAgentSendProgressPlanner"), "Live agent progress planning should live in a focused planner.")
        XCTAssertTrue(progressPlannerText.contains("WorkspaceAgentStatusBuilder.status(for: thread)"), "Progress planning should delegate status copy to the focused status builder.")
        XCTAssertTrue(composerText.contains("WorkspaceAgentSendProgressPlanner.progress"), "WorkspaceModel composer APIs should delegate live send progress planning.")
        XCTAssertFalse(modelText.contains("private func agentStatus"), "WorkspaceModel should not own agent progress status copy.")
        XCTAssertFalse(modelText.contains("WorkspaceAgentStatusBuilder.status(for: thread)"), "WorkspaceModel should not choose live progress status inline.")
        XCTAssertFalse(modelText.contains("case .toolQueued:"), "WorkspaceModel should not switch over progress event kinds for top-bar status.")
        XCTAssertFalse(modelText.contains("AgentRunner.streamingNotice"), "WorkspaceModel should not know the streaming notice string.")
    }

    func testWorkspaceModelDelegatesThreadNoticeMutation() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let reviewExtensionText = try Self.appSourceText(named: "WorkspaceModelReview.swift")
        let appenderText = try Self.appSourceText(named: "WorkspaceThreadNoticeAppender.swift")

        XCTAssertTrue(appenderText.contains("enum WorkspaceThreadNoticeAppender"), "Thread notice mutation should live in a focused helper.")
        XCTAssertTrue(appenderText.contains("static func appendNotice"), "Notice event mutation should be directly testable.")
        XCTAssertTrue(appenderText.contains("static func appendAssistantNotice"), "Assistant notice mutation should be directly testable.")
        XCTAssertTrue(modelText.contains("WorkspaceThreadNoticeAppender.appendNotice"), "WorkspaceModel should delegate notice event mutation.")
        XCTAssertTrue(reviewExtensionText.contains("WorkspaceThreadNoticeAppender.appendAssistantNotice"), "Workspace review extension should delegate assistant notice mutation.")
        XCTAssertFalse(modelText.contains("WorkspaceThreadNoticeAppender.appendAssistantNotice"), "WorkspaceModel should not own assistant notice mutation for review-card actions.")
        XCTAssertFalse(modelText.contains("thread.events.append(.init(kind: .notice"), "WorkspaceModel should not append notice events inline.")
        XCTAssertFalse(modelText.contains("thread.events.append(.init(kind: .message"), "WorkspaceModel should not append message events inline.")
        XCTAssertFalse(modelText.contains("thread.messages.append(.init(role: .assistant"), "WorkspaceModel should not append assistant notice messages inline.")
    }

    func testWorkspaceModelDelegatesPaneVisibilityMutations() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let paneVisibilityText = try Self.appSourceText(named: "WorkspaceModelPaneVisibility.swift")

        XCTAssertTrue(paneVisibilityText.contains("extension QuillCodeWorkspaceModel"), "Pane visibility APIs should live in a focused model extension.")
        XCTAssertTrue(paneVisibilityText.contains("public func toggleExtensions"), "Extension-pane visibility should live in the focused extension.")
        XCTAssertTrue(paneVisibilityText.contains("public func toggleMemories"), "Memory-pane visibility should live in the focused extension.")
        XCTAssertTrue(paneVisibilityText.contains("public func toggleActivity"), "Activity-pane visibility should live in the focused extension.")
        XCTAssertTrue(paneVisibilityText.contains("public func toggleAutomations"), "Automation-pane visibility should live in the focused extension.")
        XCTAssertTrue(paneVisibilityText.contains("public func toggleActivitySection"), "Activity section visibility should live in the focused extension.")
        XCTAssertFalse(modelText.contains("public func toggleExtensions"), "WorkspaceModel.swift should not own pane visibility APIs.")
        XCTAssertFalse(modelText.contains("public func toggleMemories"), "WorkspaceModel.swift should not own pane visibility APIs.")
        XCTAssertFalse(modelText.contains("public func toggleActivity"), "WorkspaceModel.swift should not own pane visibility APIs.")
        XCTAssertFalse(modelText.contains("public func toggleAutomations"), "WorkspaceModel.swift should not own pane visibility APIs.")
        XCTAssertFalse(modelText.contains("public func toggleActivitySection"), "WorkspaceModel.swift should not own activity-section visibility APIs.")
        XCTAssertFalse(modelText.contains("activity.collapsedSectionIDs"), "WorkspaceModel.swift should not mutate activity section visibility inline.")
    }

    func testWorkspaceModelUsesExplicitAgentRunThreadUpdates() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let composerText = try Self.appSourceText(named: "WorkspaceModelComposer.swift")

        XCTAssertTrue(modelText.contains("func updateThreadFromAgentRun"), "Agent-run thread updates should use a named helper that documents focus preservation.")
        XCTAssertTrue(composerText.contains("updateThreadFromAgentRun(thread)"), "Agent progress and completion should route through the explicit async-update helper.")
        XCTAssertFalse(modelText.contains("preservingSelection"), "WorkspaceModel should not hide async navigation behavior behind a boolean flag.")
        XCTAssertFalse(modelText.contains("replaceThread("), "WorkspaceModel should not route async run updates through an ambiguous generic replacement helper.")
    }

}
