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
            "ParitySlashGateTests.swift"
        ]
        for suiteFile in suiteFiles {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(suiteFile).path), suiteFile)
        }

        let mainText = try String(contentsOf: root.appendingPathComponent("ParityGateTests.swift"), encoding: .utf8)
        let mainLines = Set(mainText.components(separatedBy: .newlines))
        XCTAssertFalse(mainLines.contains("    private static func packageRoot() -> URL {"), "Shared source-reading helpers should live in ParityTestSupport.")
        XCTAssertFalse(mainLines.contains("    func testToolArgumentJSONSerializationLivesInCore() throws {"), "Tool/router gates should live in ParityToolGateTests.")
        XCTAssertFalse(mainLines.contains("    func testDesktopDefinesNativeMenuBarWidget() throws {"), "Desktop gates should live in ParityDesktopGateTests.")
        XCTAssertFalse(mainLines.contains("    func testTopBarViewsDelegateStatusPresentationSemantics() throws {"), "Top-bar/runtime gates should live in ParityTopBarGateTests.")
        XCTAssertFalse(mainLines.contains("    func testSlashParserDelegatesPullRequestSubcommands() throws {"), "Slash parser gates should live in ParitySlashGateTests.")
    }

    func testWorkspaceModelDelegatesToolCardSurfaceTypes() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let toolCardSurfaceText = try Self.appSourceText(named: "QuillCodeToolCardSurface.swift")
        let toolArtifactSurfaceText = try Self.appSourceText(named: "QuillCodeToolArtifactSurface.swift")
        let artifactValueClassifierText = try Self.appSourceText(named: "ToolArtifactValueClassifier.swift")
        let artifactImagePreviewText = try Self.appSourceText(named: "ToolArtifactImagePreviewBuilder.swift")
        let artifactDocumentPreviewText = try Self.appSourceText(named: "ToolArtifactDocumentPreviewBuilder.swift")
        let artifactTextPreviewText = try Self.appSourceText(named: "ToolArtifactTextPreviewBuilder.swift")
        let transcriptBuilderText = try Self.appSourceText(named: "WorkspaceTranscriptSurfaceBuilder.swift")

        XCTAssertTrue(toolCardSurfaceText.contains("public struct ToolCardState"), "Tool card surface state should live in a focused surface file.")
        XCTAssertTrue(toolArtifactSurfaceText.contains("public struct ToolArtifactState"), "Tool artifact surface state should live in a focused artifact surface file.")
        XCTAssertTrue(toolArtifactSurfaceText.contains("ToolArtifactValueClassifier.kind"), "Tool artifact state should delegate value classification.")
        XCTAssertTrue(toolArtifactSurfaceText.contains("ToolArtifactImagePreviewBuilder.imagePreview"), "Tool artifact state should delegate image previews.")
        XCTAssertTrue(toolArtifactSurfaceText.contains("ToolArtifactDocumentPreviewBuilder.documentPreview"), "Tool artifact state should delegate document previews.")
        XCTAssertTrue(artifactValueClassifierText.contains("enum ToolArtifactValueClassifier"), "Artifact value classification should have a focused owner.")
        XCTAssertTrue(artifactImagePreviewText.contains("enum ToolArtifactImagePreviewBuilder"), "Image preview construction should have a focused owner.")
        XCTAssertTrue(artifactDocumentPreviewText.contains("enum ToolArtifactDocumentPreviewBuilder"), "Document preview construction should have a focused owner.")
        XCTAssertTrue(artifactTextPreviewText.contains("enum ToolArtifactTextPreviewBuilder"), "Artifact text-preview file reading should have a focused owner.")
        XCTAssertTrue(toolArtifactSurfaceText.contains("public struct ToolArtifactDocumentPreview"), "Document preview contracts should live beside artifact state.")
        XCTAssertTrue(toolArtifactSurfaceText.contains("public struct ToolArtifactImagePreview"), "Image preview contracts should live beside artifact state.")
        XCTAssertTrue(transcriptBuilderText.contains("ToolArtifactTextPreviewBuilder.textPreview"), "Transcript projection should request artifact text previews through the extracted builder.")
        XCTAssertFalse(modelText.contains("public struct ToolCardState"), "WorkspaceModel should not own tool card surface state.")
        XCTAssertFalse(modelText.contains("public enum ToolCardStatus"), "WorkspaceModel should not own tool card status.")
        XCTAssertFalse(modelText.contains("public struct ToolArtifactState"), "WorkspaceModel should not own tool artifact surface state.")
        XCTAssertFalse(modelText.contains("ToolArtifactTextPreviewBuilder.textPreview"), "WorkspaceModel should not own artifact-preview requests.")
        XCTAssertFalse(toolArtifactSurfaceText.contains("private static func documentPreview"), "Tool artifact state should not own document-preview classification.")
        XCTAssertFalse(toolArtifactSurfaceText.contains("private static func isImagePreview"), "Tool artifact state should not own image-preview classification.")
        XCTAssertFalse(toolArtifactSurfaceText.contains("private static func localArtifactFileURL"), "Tool artifact state should not own text-preview file reading.")
        XCTAssertFalse(toolCardSurfaceText.contains("ToolArtifactTextPreviewBuilder"), "Tool-card state should not own artifact preview construction.")
        XCTAssertFalse(toolCardSurfaceText.contains("public enum ToolArtifactDocumentKind"), "Tool-card state should not own artifact document metadata.")
    }

    func testWorkspaceModelDelegatesUIStateContracts() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let stateText = try Self.appSourceText(named: "WorkspaceUIState.swift")

        XCTAssertTrue(stateText.contains("public struct ComposerState"), "Composer UI state should live in a focused state contract file.")
        XCTAssertTrue(stateText.contains("public struct MemoriesState"), "Memory-pane UI state should live in a focused state contract file.")
        XCTAssertTrue(stateText.contains("public struct ActivityState"), "Activity-pane UI state should live in a focused state contract file.")
        XCTAssertTrue(modelText.contains("public private(set) var composer: ComposerState"), "WorkspaceModel should still own live composer state.")
        XCTAssertFalse(modelText.contains("public struct ComposerState"), "WorkspaceModel should not define composer UI state contracts.")
        XCTAssertFalse(modelText.contains("public struct MemoriesState"), "WorkspaceModel should not define memory-pane UI state contracts.")
        XCTAssertFalse(modelText.contains("public struct ActivityState"), "WorkspaceModel should not define activity-pane UI state contracts.")
    }

    func testActionableReviewCardsStayWiredThroughSurfaces() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
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
        XCTAssertTrue(modelText.contains("public func runToolCardAction"), "Workspace model should execute approved review-card actions.")
        XCTAssertTrue(htmlRendererText.contains("data-testid=\"tool-card-actions\""), "HTML harness should expose action buttons for Playwright.")
        XCTAssertTrue(htmlRendererText.contains("card.statusDisplayLabel"), "HTML cards should use the same human-facing status labels as native cards.")
        XCTAssertTrue(htmlRendererText.contains("card.reviewState.rawValue"), "HTML cards should expose review substate for E2E checks without parsing copy.")
        XCTAssertTrue(approvalPlannerText.contains("enum WorkspaceApprovalActionPlanner"), "Approval-card action planning should live in a focused helper.")
        XCTAssertTrue(approvalPlannerText.contains("static func pendingRequest"), "Approval request lookup should be directly testable outside the workspace model.")
        XCTAssertTrue(modelText.contains("WorkspaceApprovalActionPlanner.plan"), "Workspace model should delegate approval-card action planning.")
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

    func testWorkspaceModelDelegatesBrowserSurfaceTypes() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let workspaceSurfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let browserSurfaceText = try Self.appSourceText(named: "QuillCodeBrowserSurface.swift")
        let browserEngineText = try Self.appSourceText(named: "WorkspaceBrowserEngine.swift")

        XCTAssertTrue(browserSurfaceText.contains("public struct BrowserState"), "Browser state should live in a focused surface file.")
        XCTAssertTrue(browserSurfaceText.contains("public struct BrowserSnapshotState"), "Browser snapshot state should live in a focused surface file.")
        XCTAssertTrue(browserSurfaceText.contains("public struct BrowserCommentState"), "Browser comment state should live in a focused surface file.")
        XCTAssertTrue(browserSurfaceText.contains("public struct BrowserSurface"), "Browser presentation surface should live in the browser surface file.")
        XCTAssertTrue(browserSurfaceText.contains("public struct BrowserSnapshotSurface"), "Browser snapshot presentation should live in the browser surface file.")
        XCTAssertTrue(browserSurfaceText.contains("public struct BrowserCommentSurface"), "Browser comment presentation should live in the browser surface file.")
        XCTAssertTrue(browserEngineText.contains("BrowserInspector.snapshot"), "Browser state transitions should own browser snapshot construction.")
        XCTAssertFalse(modelText.contains("public struct BrowserState"), "WorkspaceModel should not own browser surface state.")
        XCTAssertFalse(modelText.contains("public struct BrowserSnapshotState"), "WorkspaceModel should not own browser snapshot state.")
        XCTAssertFalse(modelText.contains("public struct BrowserCommentState"), "WorkspaceModel should not own browser comment state.")
        XCTAssertFalse(workspaceSurfaceText.contains("public struct BrowserSurface"), "WorkspaceSurface should not own browser presentation surfaces.")
        XCTAssertFalse(workspaceSurfaceText.contains("public struct BrowserSnapshotSurface"), "WorkspaceSurface should not own browser snapshot presentation.")
        XCTAssertFalse(workspaceSurfaceText.contains("public struct BrowserCommentSurface"), "WorkspaceSurface should not own browser comment presentation.")
    }

    func testBrowserInspectorDelegatesStaticHTMLSnapshotExtraction() throws {
        let inspectorText = try Self.appSourceText(named: "BrowserInspector.swift")
        let builderText = try Self.appSourceText(named: "BrowserHTMLSnapshotBuilder.swift")
        let builderTests = try Self.appTestSourceText(named: "BrowserHTMLSnapshotBuilderTests.swift")

        XCTAssertTrue(builderText.contains("enum BrowserHTMLSnapshotBuilder"), "Static HTML snapshot extraction should have a focused owner.")
        XCTAssertTrue(builderText.contains("static func snapshot("), "HTML snapshot extraction should be directly testable.")
        XCTAssertTrue(builderText.contains("private static func htmlOutline"), "HTML outline extraction should live with the HTML snapshot builder.")
        XCTAssertTrue(builderText.contains("private static func htmlTextSnippet"), "HTML text snippet extraction should live with the HTML snapshot builder.")
        XCTAssertTrue(inspectorText.contains("BrowserHTMLSnapshotBuilder.snapshot"), "BrowserInspector should delegate static HTML extraction.")
        XCTAssertFalse(inspectorText.contains("private static func htmlOutline"), "BrowserInspector should not own HTML outline extraction.")
        XCTAssertFalse(inspectorText.contains("private static func cleanHTMLText"), "BrowserInspector should not own HTML text cleanup.")
        XCTAssertTrue(builderTests.contains("testSnapshotExtractsDetailsOutlineAndReadableText"), "HTML snapshot builder behavior should have focused tests.")
        XCTAssertTrue(builderTests.contains("testSnapshotLimitsOutlineAndTruncatesSnippet"), "HTML snapshot limits should have focused tests.")
    }

    func testWorkspaceModelDelegatesBrowserStateTransitions() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let engineText = try Self.appSourceText(named: "WorkspaceBrowserEngine.swift")

        XCTAssertTrue(engineText.contains("struct WorkspaceBrowserEngine"), "Browser state transitions should live in a focused engine.")
        XCTAssertTrue(engineText.contains("static func openPage"), "Browser opening should be directly testable.")
        XCTAssertTrue(engineText.contains("static func goBack"), "Browser back navigation should be directly testable.")
        XCTAssertTrue(engineText.contains("static func goForward"), "Browser forward navigation should be directly testable.")
        XCTAssertTrue(engineText.contains("static func reload"), "Browser reload should be directly testable.")
        XCTAssertTrue(engineText.contains("static func applyFetchedPage"), "Fetched browser pages should update state through the engine.")
        XCTAssertTrue(engineText.contains("static func markSnapshotFetchFailure"), "Browser fetch failures should update state through the engine.")
        XCTAssertTrue(engineText.contains("static func addComment"), "Browser comments should be directly testable.")
        XCTAssertTrue(modelText.contains("WorkspaceBrowserEngine.openPage"), "WorkspaceModel should delegate browser opening.")
        XCTAssertTrue(modelText.contains("WorkspaceBrowserEngine.applyFetchedPage"), "WorkspaceModel should delegate fetched browser state updates.")
        XCTAssertTrue(modelText.contains("WorkspaceBrowserEngine.addComment"), "WorkspaceModel should delegate browser comments.")
        XCTAssertFalse(modelText.contains("private func setBrowserPage"), "WorkspaceModel should not own browser page mutation.")
        XCTAssertFalse(modelText.contains("private func appendBrowserHistory"), "WorkspaceModel should not own browser history mutation.")
        XCTAssertFalse(modelText.contains("private func replaceCurrentBrowserHistory"), "WorkspaceModel should not own browser history replacement.")
        XCTAssertFalse(modelText.contains("BrowserCommentState(url:"), "WorkspaceModel should not construct browser comments directly.")
        XCTAssertFalse(modelText.contains("Snapshot fetch: "), "WorkspaceModel should not own browser fetch-failure annotation copy.")
    }

    func testWorkspaceModelDelegatesBrowserLocationResolving() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let resolverText = try Self.appSourceText(named: "WorkspaceBrowserLocationResolver.swift")

        XCTAssertTrue(resolverText.contains("struct WorkspaceBrowserLocationResolver"), "Browser URL normalization should live in a focused resolver.")
        XCTAssertTrue(resolverText.contains("func resolve("), "Browser URL resolution should be directly testable.")
        XCTAssertTrue(resolverText.contains("static func canFetchSnapshot"), "Browser snapshot eligibility should be directly testable.")
        XCTAssertTrue(resolverText.contains("static func snapshotFetchMessage"), "Browser fetch failure copy should be directly testable.")
        XCTAssertTrue(modelText.contains("WorkspaceBrowserLocationResolver"), "WorkspaceModel should delegate browser URL resolution.")
        XCTAssertFalse(modelText.contains("private static func normalizedBrowserURL"), "WorkspaceModel should not own browser URL normalization.")
        XCTAssertFalse(modelText.contains("private static func canFetchBrowserSnapshot"), "WorkspaceModel should not own browser snapshot eligibility.")
        XCTAssertFalse(modelText.contains("private static func browserSnapshotFetchMessage"), "WorkspaceModel should not own browser fetch failure copy.")
        XCTAssertFalse(modelText.contains("private static func projectFileBrowserURL"), "WorkspaceModel should not own project file URL resolution.")
    }

    func testWorkspaceModelDelegatesProjectContextRefresh() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
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
        XCTAssertTrue(modelText.contains("WorkspaceProjectContextRefresher.syncThreadContext"), "WorkspaceModel should delegate thread context sync.")
        XCTAssertTrue(modelText.contains("WorkspaceProjectContextRefresher.threadCreationContext"), "WorkspaceModel should delegate thread creation context assembly.")
        XCTAssertTrue(modelText.contains("WorkspaceProjectContextRefresher.worktreeOpenContext"), "WorkspaceModel should delegate worktree open context assembly.")
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
        let creationText = try Self.appSourceText(named: "WorkspaceThreadCreationEngine.swift")

        XCTAssertTrue(creationText.contains("struct WorkspaceThreadCreationContext"), "New-thread context should live beside the focused creation engine.")
        XCTAssertTrue(creationText.contains("struct WorkspaceThreadCreationEngine"), "Thread record construction should live in a focused engine.")
        XCTAssertTrue(creationText.contains("static func newThread"), "New chat construction should be directly testable.")
        XCTAssertTrue(creationText.contains("static func forkThread"), "Fork thread construction should be directly testable.")
        XCTAssertTrue(creationText.contains("static func compactThread"), "Compact thread construction should be directly testable.")
        XCTAssertTrue(creationText.contains("static func duplicateThread"), "Duplicate thread construction should be directly testable.")
        XCTAssertTrue(modelText.contains("WorkspaceThreadCreationEngine.newThread"), "WorkspaceModel should delegate new chat construction.")
        XCTAssertTrue(modelText.contains("WorkspaceThreadCreationEngine.forkThread"), "WorkspaceModel should delegate fork construction.")
        XCTAssertTrue(modelText.contains("WorkspaceThreadCreationEngine.compactThread"), "WorkspaceModel should delegate compact construction.")
        XCTAssertTrue(modelText.contains("WorkspaceThreadCreationEngine.duplicateThread"), "WorkspaceModel should delegate duplicate construction.")
        XCTAssertFalse(modelText.contains("title: \"Fork:"), "WorkspaceModel should not own fork title copy.")
        XCTAssertFalse(modelText.contains("title: \"Compact:"), "WorkspaceModel should not own compact title copy.")
        XCTAssertFalse(modelText.contains("title: \"Copy:"), "WorkspaceModel should not own duplicate title copy.")
    }

    func testWorkspaceModelDelegatesThreadLifecycleTransitions() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
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
        XCTAssertTrue(modelText.contains("WorkspaceThreadLifecycleEngine.renameThread"), "WorkspaceModel should delegate thread rename mutation.")
        XCTAssertTrue(modelText.contains("WorkspaceThreadLifecycleEngine.archiveThread"), "WorkspaceModel should delegate thread archive mutation.")
        XCTAssertTrue(modelText.contains("WorkspaceThreadLifecycleEngine.deleteThread"), "WorkspaceModel should delegate thread delete mutation.")
        XCTAssertTrue(modelText.contains("WorkspaceThreadLifecycleEngine.applyAgentRunThreadUpdate"), "WorkspaceModel should delegate agent-run thread upsert and fallback selection.")
        XCTAssertTrue(modelText.contains("WorkspaceThreadPersistence(store: threadStore)"), "WorkspaceModel should bridge its existing initializer to the thread persistence helper.")
        XCTAssertTrue(modelText.contains("threadPersistence.mutate"), "WorkspaceModel should delegate timestamped thread mutation.")
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
        let configurationText = try Self.appSourceText(named: "WorkspaceConfigurationEngine.swift")

        XCTAssertTrue(configurationText.contains("struct WorkspaceConfigurationEngine"), "Workspace configuration transitions should live in a focused engine.")
        XCTAssertTrue(configurationText.contains("static func setModel"), "Model selection should be directly testable.")
        XCTAssertTrue(configurationText.contains("static func setMode"), "Mode selection should be directly testable.")
        XCTAssertTrue(configurationText.contains("static func toggleFavorite"), "Favorite model mutation should be directly testable.")
        XCTAssertTrue(configurationText.contains("static func normalizedCatalog"), "Catalog replacement should be directly testable.")
        XCTAssertTrue(configurationText.contains("static func applySettings"), "Settings application should be directly testable.")
        XCTAssertTrue(configurationText.contains("static func syncThread"), "Selected-thread config syncing should be directly testable.")
        XCTAssertTrue(modelText.contains("WorkspaceConfigurationEngine.setModel"), "WorkspaceModel should delegate model selection.")
        XCTAssertTrue(modelText.contains("WorkspaceConfigurationEngine.setMode"), "WorkspaceModel should delegate mode selection.")
        XCTAssertTrue(modelText.contains("WorkspaceConfigurationEngine.toggleFavorite"), "WorkspaceModel should delegate favorite mutation.")
        XCTAssertTrue(modelText.contains("WorkspaceConfigurationEngine.normalizedCatalog"), "WorkspaceModel should delegate catalog normalization.")
        XCTAssertTrue(modelText.contains("WorkspaceConfigurationEngine.applySettings"), "WorkspaceModel should delegate settings application.")
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
        let retryPlannerText = try Self.appSourceText(named: "WorkspaceRetryPlanner.swift")
        let retryPlannerTests = try Self.appTestSourceText(named: "WorkspaceRetryPlannerTests.swift")

        XCTAssertTrue(retryPlannerText.contains("enum WorkspaceRetryPlanner"), "Retry planning should live in a focused helper.")
        XCTAssertTrue(retryPlannerText.contains("static func canRetryLastUserTurn"), "Retry availability should be directly testable.")
        XCTAssertTrue(retryPlannerText.contains("static func retryDraft"), "Retry draft selection should be directly testable.")
        XCTAssertTrue(modelText.contains("WorkspaceRetryPlanner.canRetryLastUserTurn"), "WorkspaceModel should delegate retry availability.")
        XCTAssertTrue(modelText.contains("WorkspaceRetryPlanner.retryDraft"), "WorkspaceModel should delegate retry draft selection.")
        XCTAssertTrue(retryPlannerTests.contains("testRetryDraftUsesLatestNonEmptyUserMessageAndPreservesOriginalText"), "Retry draft behavior should have focused coverage.")
        XCTAssertTrue(retryPlannerTests.contains("testRetryRequiresUserMessageAndIdleComposer"), "Retry availability should have focused coverage.")
        XCTAssertFalse(modelText.contains("messages.last(where:"), "WorkspaceModel should not scan transcript messages for retry drafts.")
        XCTAssertFalse(modelText.contains("messages.contains {"), "WorkspaceModel should not own retry availability scans.")
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
        XCTAssertTrue(modelText.contains("WorkspaceStatusTextBuilder.statusText"), "WorkspaceModel should delegate /status copy.")
        XCTAssertTrue(modelText.contains("WorkspaceStatusContextBuilder.context"), "WorkspaceModel should delegate /status context assembly.")
        XCTAssertTrue(slashTranscriptText.contains("WorkspaceStatusTextBuilder.modeLabel"), "Slash mode transcript copy should delegate shared mode labels.")
        XCTAssertTrue(topBarBuilderText.contains("WorkspaceStatusTextBuilder.topBarSubtitle"), "Top-bar builder should delegate top-bar subtitles.")
        XCTAssertTrue(topBarBuilderText.contains("WorkspaceStatusTextBuilder.instructionLabel"), "Top-bar builder should delegate instruction labels.")
        XCTAssertTrue(topBarBuilderText.contains("WorkspaceStatusTextBuilder.memoryLabel"), "Top-bar builder should delegate memory labels.")
        XCTAssertTrue(topBarStateBuilderText.contains("enum WorkspaceTopBarStateBuilder"), "Top-bar state assembly should live in a focused builder.")
        XCTAssertTrue(modelText.contains("WorkspaceTopBarStateBuilder.state"), "WorkspaceModel should delegate top-bar state assembly.")
        XCTAssertFalse(modelText.contains("root.topBar = TopBarState("), "WorkspaceModel should not assemble top-bar state inline.")
        XCTAssertFalse(modelText.contains("WorkspaceStatusContext("), "WorkspaceModel should not assemble /status context inline.")
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
        XCTAssertTrue(modelText.contains("WorkspaceContextResolver("), "WorkspaceModel should delegate context lookup through the resolver.")
        XCTAssertTrue(surfaceText.contains("WorkspaceContextResolver("), "WorkspaceSurface should delegate active context-source lookup through the resolver.")
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
        let builderText = try Self.appSourceText(named: "WorkspaceAgentStatusBuilder.swift")

        XCTAssertTrue(builderText.contains("struct WorkspaceAgentStatusBuilder"), "Agent progress status copy should live in a focused builder.")
        XCTAssertTrue(builderText.contains("static func status(for thread: ChatThread)"), "Thread-level progress status should be directly testable.")
        XCTAssertTrue(builderText.contains("static func status(for event: ThreadEvent?)"), "Event-level progress status should be directly testable.")
        XCTAssertTrue(builderText.contains("AgentRunner.streamingNotice"), "Streaming status should remain tied to the agent streaming notice contract.")
        XCTAssertTrue(modelText.contains("WorkspaceAgentStatusBuilder.status(for: thread)"), "WorkspaceModel should delegate agent progress status copy.")
        XCTAssertFalse(modelText.contains("private func agentStatus"), "WorkspaceModel should not own agent progress status copy.")
        XCTAssertFalse(modelText.contains("case .toolQueued:"), "WorkspaceModel should not switch over progress event kinds for top-bar status.")
        XCTAssertFalse(modelText.contains("AgentRunner.streamingNotice"), "WorkspaceModel should not know the streaming notice string.")
    }

    func testWorkspaceModelDelegatesThreadNoticeMutation() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let appenderText = try Self.appSourceText(named: "WorkspaceThreadNoticeAppender.swift")

        XCTAssertTrue(appenderText.contains("enum WorkspaceThreadNoticeAppender"), "Thread notice mutation should live in a focused helper.")
        XCTAssertTrue(appenderText.contains("static func appendNotice"), "Notice event mutation should be directly testable.")
        XCTAssertTrue(appenderText.contains("static func appendAssistantNotice"), "Assistant notice mutation should be directly testable.")
        XCTAssertTrue(modelText.contains("WorkspaceThreadNoticeAppender.appendNotice"), "WorkspaceModel should delegate notice event mutation.")
        XCTAssertTrue(modelText.contains("WorkspaceThreadNoticeAppender.appendAssistantNotice"), "WorkspaceModel should delegate assistant notice mutation.")
        XCTAssertFalse(modelText.contains("thread.events.append(.init(kind: .notice"), "WorkspaceModel should not append notice events inline.")
        XCTAssertFalse(modelText.contains("thread.events.append(.init(kind: .message"), "WorkspaceModel should not append message events inline.")
        XCTAssertFalse(modelText.contains("thread.messages.append(.init(role: .assistant"), "WorkspaceModel should not append assistant notice messages inline.")
    }

    func testWorkspaceModelUsesExplicitAgentRunThreadUpdates() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")

        XCTAssertTrue(modelText.contains("private func updateThreadFromAgentRun"), "Agent-run thread updates should use a named helper that documents focus preservation.")
        XCTAssertTrue(modelText.contains("updateThreadFromAgentRun(thread)"), "Agent progress and completion should route through the explicit async-update helper.")
        XCTAssertFalse(modelText.contains("preservingSelection"), "WorkspaceModel should not hide async navigation behavior behind a boolean flag.")
        XCTAssertFalse(modelText.contains("replaceThread("), "WorkspaceModel should not route async run updates through an ambiguous generic replacement helper.")
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

    func testTrustedRouterModelCatalogLivesOutsideGeneralDomainModels() throws {
        let modelsText = try Self.coreSourceText(named: "Models.swift")
        let modelInfoText = try Self.coreSourceText(named: "ModelInfo.swift")
        let defaultsText = try Self.coreSourceText(named: "TrustedRouterDefaults.swift")

        XCTAssertTrue(modelInfoText.contains("public struct ModelInfo"), "Model catalog records should live in a focused core file.")
        XCTAssertTrue(modelInfoText.contains("public struct ModelSortKey"), "Model sort policy inputs should live beside model catalog records.")
        XCTAssertTrue(defaultsText.contains("public enum TrustedRouterDefaults"), "TrustedRouter defaults should live in their own named core file.")
        XCTAssertTrue(defaultsText.contains("Nike 1.0"), "User-facing default model branding should stay with TrustedRouter defaults.")
        XCTAssertTrue(defaultsText.contains("Synth"), "User-facing fallback model branding should stay with TrustedRouter defaults.")
        XCTAssertTrue(defaultsText.contains("normalizedModelCatalog"), "Model catalog normalization should stay with TrustedRouter defaults.")
        XCTAssertFalse(modelsText.contains("public struct ModelInfo"), "General domain models should not own model catalog records.")
        XCTAssertFalse(modelsText.contains("public struct ModelSortKey"), "General domain models should not own model sort records.")
        XCTAssertFalse(modelsText.contains("public enum TrustedRouterDefaults"), "General domain models should not own TrustedRouter defaults.")
        XCTAssertFalse(modelsText.contains("Nike 1.0"), "General domain models should not own model branding copy.")
        XCTAssertFalse(modelsText.contains("Synth"), "General domain models should not own model branding copy.")
    }

    func testAppConfigLivesOutsideGeneralDomainModels() throws {
        let modelsText = try Self.coreSourceText(named: "Models.swift")
        let configText = try Self.coreSourceText(named: "AppConfig.swift")

        XCTAssertTrue(configText.contains("public struct AppConfig"), "App config should live in a focused core file.")
        XCTAssertTrue(configText.contains("public enum TrustedRouterAuthMode"), "TrustedRouter auth mode belongs with app config.")
        XCTAssertTrue(configText.contains("public struct TrustedRouterAccountProfile"), "Signed-in account metadata belongs with app config.")
        XCTAssertTrue(configText.contains("normalizedModelIDs"), "Favorite/default model normalization should stay with app config.")
        XCTAssertTrue(configText.contains("developerOverrideEnabled ? .developerOverride"), "Developer override compatibility should stay with app config.")
        XCTAssertFalse(modelsText.contains("public struct AppConfig"), "General domain models should not own app configuration.")
        XCTAssertFalse(modelsText.contains("public enum TrustedRouterAuthMode"), "General domain models should not own TrustedRouter auth mode.")
        XCTAssertFalse(modelsText.contains("public struct TrustedRouterAccountProfile"), "General domain models should not own account profile metadata.")
        XCTAssertFalse(modelsText.contains("developerOverrideEnabled ? .developerOverride"), "General domain models should not own settings compatibility rules.")
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

    func testWorkspaceModelDelegatesComposerCancellationPlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceComposerCancellationPlanner.swift")

        XCTAssertTrue(plannerText.contains("struct WorkspaceComposerCancellationPlanner"), "Composer cancellation mutation should live in a focused planner.")
        XCTAssertTrue(plannerText.contains("static func applyCancelledSend"), "Cancelled-send thread mutation should be directly testable.")
        XCTAssertTrue(plannerText.contains("static let stoppedSummary"), "Cancelled-send copy should be shared through the planner.")
        XCTAssertTrue(modelText.contains("WorkspaceComposerCancellationPlanner.applyCancelledSend"), "WorkspaceModel should delegate cancelled-send transcript mutation.")
        XCTAssertFalse(modelText.contains(#""Stopped by user""#), "WorkspaceModel should not own cancelled-send copy.")
        XCTAssertFalse(modelText.contains(#"{"ok":false,"error":"Stopped by user"}"#), "WorkspaceModel should not own cancelled-send result payload copy.")
    }

    func testWorkspaceModelDelegatesComposerSubmissionPlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceComposerSubmissionPlanner.swift")

        XCTAssertTrue(
            plannerText.contains("struct WorkspaceComposerSubmissionPlanner"),
            "Composer submission planning should live in a focused pure planner."
        )
        XCTAssertTrue(
            modelText.contains("WorkspaceComposerSubmissionPlanner.plan"),
            "WorkspaceModel should delegate prompt trimming and slash-command classification."
        )
        XCTAssertFalse(
            modelText.contains("composer.draft.trimmingCharacters"),
            "WorkspaceModel should not own raw composer prompt normalization."
        )
        XCTAssertFalse(
            modelText.contains("SlashCommandParser.parse(prompt)"),
            "WorkspaceModel should not classify slash commands inline."
        )
    }

    func testWorkspaceModelDelegatesAgentSendSessionExecution() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let sessionText = try Self.appSourceText(named: "WorkspaceAgentSendSession.swift")

        XCTAssertTrue(
            sessionText.contains("struct WorkspaceAgentSendSession"),
            "Agent send execution should live in a focused session object."
        )
        XCTAssertTrue(
            modelText.contains("WorkspaceAgentSendSession("),
            "WorkspaceModel should delegate runner execution to an agent send session."
        )
        XCTAssertFalse(
            modelText.contains("activeRunner.send("),
            "WorkspaceModel should not call the runner directly from submitComposer."
        )
        XCTAssertFalse(
            modelText.contains("WorkspaceMemoryRememberToolExecutor.didSaveMemory(in: thread)"),
            "WorkspaceModel should not inspect completed run memory events inline."
        )
    }

    func testWorkspaceModelDelegatesSlashCommandTranscriptPlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let actionExecutorText = try Self.appSourceText(named: "WorkspaceSlashCommandActionExecutor.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceSlashCommandTranscriptPlanner.swift")
        let appenderText = try Self.appSourceText(named: "WorkspaceLocalCommandTranscriptAppender.swift")
        let environmentPlannerText = try Self.appSourceText(named: "WorkspaceEnvironmentSlashCommandPlanner.swift")
        let dispatchPlannerText = try Self.appSourceText(named: "WorkspaceSlashCommandDispatchPlanner.swift")

        XCTAssertTrue(plannerText.contains("struct WorkspaceLocalCommandTranscript"), "Local command transcript records should live beside the planner.")
        XCTAssertTrue(plannerText.contains("struct WorkspaceSlashCommandTranscriptPlanner"), "Slash command transcript copy should live in a focused planner.")
        XCTAssertTrue(appenderText.contains("enum WorkspaceLocalCommandTranscriptAppender"), "Local command transcript mutation should live in a focused appender.")
        XCTAssertTrue(environmentPlannerText.contains("struct WorkspaceEnvironmentSlashCommandPlanner"), "Local environment slash command planning should live in a focused planner.")
        XCTAssertTrue(environmentPlannerText.contains("WorkspaceSlashCommandTranscriptPlanner.environmentActions"), "Local environment list transcripts should be planned outside WorkspaceModel.")
        XCTAssertTrue(environmentPlannerText.contains("WorkspaceSlashCommandTranscriptPlanner.environmentActionNotFound"), "Local environment missing-action transcripts should be planned outside WorkspaceModel.")
        XCTAssertTrue(dispatchPlannerText.contains("WorkspaceSlashCommandTranscriptPlanner.help"), "Help transcripts should be selected by slash dispatch planning.")
        XCTAssertTrue(dispatchPlannerText.contains("WorkspaceSlashCommandTranscriptPlanner.status"), "Status transcripts should be selected by slash dispatch planning.")
        XCTAssertTrue(dispatchPlannerText.contains("WorkspaceSlashCommandTranscriptPlanner.invalid"), "Invalid-command transcripts should be selected by slash dispatch planning.")
        XCTAssertTrue(dispatchPlannerText.contains("WorkspaceSlashCommandTranscriptPlanner.unknown"), "Unknown-command transcripts should be selected by slash dispatch planning.")
        XCTAssertTrue(appenderText.contains("thread.messages.append(ChatMessage(role: .user"), "The transcript appender should own user-message insertion.")
        XCTAssertTrue(appenderText.contains("thread.messages.append(ChatMessage(role: .assistant"), "The transcript appender should own assistant-message insertion.")
        XCTAssertTrue(modelText.contains("WorkspaceLocalCommandTranscriptAppender.append"), "WorkspaceModel should delegate local command transcript mutation.")
        XCTAssertTrue(modelText.contains("WorkspaceEnvironmentSlashCommandPlanner.plan"), "WorkspaceModel should delegate /env list/run/not-found planning.")
        XCTAssertTrue(plannerText.contains("static func sshProjectAdded"), "SSH success copy should be directly testable.")
        XCTAssertTrue(plannerText.contains("static func workspaceCommandFailed"), "Slash command failure copy should be directly testable.")
        XCTAssertTrue(plannerText.contains("SlashCommandCatalog.helpText()"), "Slash help text should stay catalog-backed.")
        for actionExecutorOwnedCall in [
            "WorkspaceSlashCommandTranscriptPlanner.mode",
            "WorkspaceSlashCommandTranscriptPlanner.model",
            "WorkspaceSlashCommandTranscriptPlanner.renameThread",
            "WorkspaceSlashCommandTranscriptPlanner.renameProject",
            "WorkspaceSlashCommandTranscriptPlanner.sshProjectAdded",
            "WorkspaceSlashCommandTranscriptPlanner.workspaceCommandFailed"
        ] {
            XCTAssertTrue(actionExecutorText.contains(actionExecutorOwnedCall), "Slash action execution should delegate \(actionExecutorOwnedCall).")
            XCTAssertFalse(modelText.contains(actionExecutorOwnedCall), "WorkspaceModel should not directly choose \(actionExecutorOwnedCall).")
        }
        for modelOwnedScheduledCall in [
            "WorkspaceSlashCommandTranscriptPlanner.threadFollowUpScheduled",
            "WorkspaceSlashCommandTranscriptPlanner.workspaceScheduleScheduled"
        ] {
            XCTAssertTrue(modelText.contains(modelOwnedScheduledCall), "WorkspaceModel should keep schedule transcript delegation beside schedule persistence.")
        }
        for dispatchOwnedCall in [
            "WorkspaceSlashCommandTranscriptPlanner.help",
            "WorkspaceSlashCommandTranscriptPlanner.status",
            "WorkspaceSlashCommandTranscriptPlanner.invalid",
            "WorkspaceSlashCommandTranscriptPlanner.unknown"
        ] {
            XCTAssertFalse(modelText.contains(dispatchOwnedCall), "WorkspaceModel should let dispatch planning choose \(dispatchOwnedCall).")
        }
        XCTAssertFalse(modelText.contains("Could not rename this chat. Try /rename New chat title."), "WorkspaceModel should not own thread rename fallback copy.")
        XCTAssertFalse(modelText.contains("Could not rename this project. Try /project rename New project name."), "WorkspaceModel should not own project rename fallback copy.")
        XCTAssertFalse(modelText.contains("Use SSH format user@host:/path or ssh://user@host/path."), "WorkspaceModel should not own SSH fallback copy.")
        XCTAssertFalse(modelText.contains("Scheduled a thread follow-up for"), "WorkspaceModel should not own follow-up success copy.")
        XCTAssertFalse(modelText.contains("Scheduled a workspace check for"), "WorkspaceModel should not own workspace schedule success copy.")
        XCTAssertFalse(modelText.contains("WorkspaceSlashCommandTranscriptPlanner.environmentActions"), "WorkspaceModel should not choose /env list transcripts inline.")
        XCTAssertFalse(modelText.contains("WorkspaceSlashCommandTranscriptPlanner.environmentActionNotFound"), "WorkspaceModel should not choose /env missing-action transcripts inline.")
        XCTAssertFalse(modelText.contains("contextResolver.selectedLocalAction(matching:"), "WorkspaceModel should not own /env action matching.")
        XCTAssertFalse(modelText.contains("Local environment actions:"), "WorkspaceModel should not own /env list copy.")
        XCTAssertFalse(modelText.contains("No local environment action matches"), "WorkspaceModel should not own /env missing-action copy.")
        XCTAssertFalse(modelText.contains("Unknown slash command"), "WorkspaceModel should not own unknown slash command copy.")
        XCTAssertFalse(modelText.contains("thread.title = title"), "WorkspaceModel should not own local command title mutation.")
        XCTAssertFalse(modelText.contains("ChatMessage(role: .user, content: userText)"), "WorkspaceModel should not append local command user messages inline.")
        XCTAssertFalse(modelText.contains("ChatMessage(role: .assistant, content: assistantText)"), "WorkspaceModel should not append local command assistant messages inline.")
        XCTAssertFalse(plannerText.contains("memorySaved("), "Memory save copy should live in the memory command planner.")
        XCTAssertFalse(plannerText.contains("memoryNotSaved("), "Memory save failure copy should live in the memory command planner.")
        XCTAssertFalse(plannerText.contains("memorySavedSummary("), "Memory save event summaries should live in the memory command planner.")
    }

    func testWorkspaceModelDelegatesMemoryCommandOrchestration() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let engineText = try Self.appSourceText(named: "WorkspaceMemoryEngine.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceMemoryCommandTranscriptPlanner.swift")
        let errorText = try Self.appSourceText(named: "WorkspaceMemoryErrorMessageBuilder.swift")
        let contextUpdateText = try Self.appSourceText(named: "WorkspaceMemoryContextUpdatePlanner.swift")

        XCTAssertTrue(engineText.contains("enum WorkspaceMemoryEngine"), "Memory command orchestration should live in a focused engine.")
        XCTAssertTrue(engineText.contains("struct WorkspaceMemoryMutation"), "Memory command outcomes should use a typed mutation value.")
        XCTAssertTrue(modelText.contains("WorkspaceMemoryEngine.saveGlobal"), "WorkspaceModel should delegate global memory saves.")
        XCTAssertTrue(modelText.contains("WorkspaceMemoryEngine.deleteGlobal"), "WorkspaceModel should delegate global memory deletion.")
        XCTAssertTrue(modelText.contains("WorkspaceProjectContextRefresher.globalMemories"), "WorkspaceModel should delegate global memory reloads through the project context refresher.")
        XCTAssertTrue(modelText.contains("WorkspaceMemoryEngine.contextUpdate"), "WorkspaceModel should delegate memory context update construction.")
        XCTAssertTrue(plannerText.contains("struct WorkspaceMemoryCommandTranscriptPlanner"), "Memory command transcript copy should live in a focused planner.")
        XCTAssertTrue(errorText.contains("enum WorkspaceMemoryErrorMessageBuilder"), "Memory write and delete errors should share one user-facing formatter.")
        XCTAssertTrue(contextUpdateText.contains("struct WorkspaceMemoryContextUpdatePlanner"), "Memory thread context updates should live in a focused planner.")
        for delegatedCall in [
            "WorkspaceMemoryCommandTranscriptPlanner.memorySaved",
            "WorkspaceMemoryCommandTranscriptPlanner.memoryNotSaved",
            "WorkspaceMemoryCommandTranscriptPlanner.memorySavedSummary",
            "WorkspaceMemoryCommandTranscriptPlanner.memoryForgotten",
            "WorkspaceMemoryCommandTranscriptPlanner.memoryNotDeleted",
            "WorkspaceMemoryCommandTranscriptPlanner.memoryForgottenSummary",
            "WorkspaceMemoryErrorMessageBuilder.userFacingMessage",
            "WorkspaceMemoryContextUpdatePlanner.globalMemoryChanged"
        ] {
            XCTAssertTrue(engineText.contains(delegatedCall), "WorkspaceMemoryEngine should delegate \(delegatedCall).")
        }
        XCTAssertFalse(modelText.contains("It will be included as background context in future turns."), "WorkspaceModel should not own memory save success copy.")
        XCTAssertFalse(modelText.contains("Memory not saved"), "WorkspaceModel should not own memory save failure title copy.")
        XCTAssertFalse(modelText.contains("It will no longer be included as background context."), "WorkspaceModel should not own memory delete success copy.")
        XCTAssertFalse(modelText.contains("Memory not deleted"), "WorkspaceModel should not own memory delete failure title copy.")
        XCTAssertFalse(modelText.contains("Forgot memory:"), "WorkspaceModel should not own memory delete summary copy.")
        XCTAssertFalse(modelText.contains("MemoryNoteLoader.saveGlobal"), "WorkspaceModel should not write memory files directly.")
        XCTAssertFalse(modelText.contains("MemoryNoteLoader.deleteGlobal"), "WorkspaceModel should not delete memory files directly.")
        XCTAssertFalse(modelText.contains("MemoryNoteLoader.loadGlobal"), "WorkspaceModel should not reload global memories directly.")
        XCTAssertFalse(modelText.contains("MemoryNoteDeleteError.deleteFailed.localizedDescription"), "WorkspaceModel should not format memory delete errors directly.")
        XCTAssertFalse(modelText.contains("payloadJSON: note.relativePath"), "WorkspaceModel should not build memory change events inline.")
    }

    func testWorkspaceModelDelegatesCommandActionPlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceCommandActionPlanner.swift")
        let executorText = try Self.appSourceText(named: "WorkspaceCommandActionExecutor.swift")
        let planExecutorText = try Self.appSourceText(named: "WorkspaceCommandPlanExecutor.swift")

        XCTAssertTrue(plannerText.contains("enum WorkspaceCommandActionEffect"), "Workspace command action effects should live beside the focused planner.")
        XCTAssertTrue(plannerText.contains("struct WorkspaceCommandActionPlanner"), "Workspace command action routing should live in a focused planner.")
        XCTAssertTrue(plannerText.contains("func effect(for action: WorkspaceCommandAction)"), "Command action routing should be directly testable.")
        XCTAssertTrue(executorText.contains("WorkspaceCommandActionPlanner("), "Command action execution should ask the focused planner for typed effects.")
        XCTAssertTrue(executorText.contains("func runWorkspaceCommandAction("), "Command action execution should live in a focused executor.")
        XCTAssertTrue(executorText.contains("func runWorkspaceCommandActionEffect("), "Typed command action effect execution should live in the focused executor.")
        XCTAssertTrue(planExecutorText.contains("return runWorkspaceCommandAction(action)"), "Workspace command-plan execution should delegate typed actions to the focused action executor.")
        XCTAssertFalse(modelText.contains("WorkspaceCommandActionPlanner("), "WorkspaceModel should not own command action planning setup.")
        XCTAssertFalse(modelText.contains("runWorkspaceCommandAction(action)"), "WorkspaceModel should not own command action dispatch.")
        XCTAssertFalse(modelText.contains("runWorkspaceCommandActionEffect"), "WorkspaceModel should not own typed command action effect execution.")
        XCTAssertFalse(modelText.contains("case .toggleTerminal:"), "WorkspaceModel should not own command action effect switching.")
        XCTAssertFalse(modelText.contains("case .projectNewChat:"), "WorkspaceModel should not inline project command action routing.")
        XCTAssertFalse(modelText.contains("case .projectRename:"), "WorkspaceModel should not inline project rename draft routing.")
        XCTAssertFalse(modelText.contains("case .threadBulkArchive:"), "WorkspaceModel should not inline sidebar bulk command routing.")
        XCTAssertFalse(modelText.contains("setDraft(\"/project rename"), "WorkspaceModel should not build project rename drafts inline.")
        XCTAssertFalse(modelText.contains("setDraft(\"/rename"), "WorkspaceModel should not build thread rename drafts inline.")
    }

    func testWorkspaceModelDelegatesCommandPlanExecution() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let executorText = try Self.appSourceText(named: "WorkspaceCommandPlanExecutor.swift")

        XCTAssertTrue(executorText.contains("public func runWorkspaceCommand("), "Public workspace command execution should live in the focused command-plan executor.")
        XCTAssertTrue(executorText.contains("WorkspaceCommandPlan(commandID: commandID)"), "Command ID parsing should stay beside plan execution.")
        XCTAssertTrue(executorText.contains("func runWorkspaceCommandPlan("), "Parsed command-plan execution should be directly testable.")
        XCTAssertTrue(executorText.contains("switch plan"), "The command-plan switch should live in the focused executor.")
        XCTAssertTrue(executorText.contains("return runWorkspaceCommandAction(action)"), "Typed command actions should still delegate to the action executor.")
        XCTAssertFalse(modelText.contains("WorkspaceCommandPlan(commandID: commandID)"), "WorkspaceModel should not parse command IDs inline.")
        XCTAssertFalse(modelText.contains("case .localEnvironmentAction"), "WorkspaceModel should not own command-plan execution switching.")
        XCTAssertFalse(modelText.contains("case .startMCPServer"), "WorkspaceModel should not own MCP command-plan routing.")
        XCTAssertFalse(modelText.contains("case .runTool"), "WorkspaceModel should not own tool command-plan routing.")
    }

    func testWorkspaceModelDelegatesAgentRunContextAssembly() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceAgentRunContextBuilder.swift")
        let memoryExecutorText = try Self.appSourceText(named: "WorkspaceMemoryRememberToolExecutor.swift")

        XCTAssertTrue(modelText.contains("WorkspaceAgentRunContextBuilder("), "WorkspaceModel should delegate per-run tool assembly.")
        XCTAssertTrue(builderText.contains("configuredRunner(from runner: AgentRunner)"), "Agent run context builder should own runner configuration.")
        XCTAssertTrue(builderText.contains("ToolDefinition.planUpdate"), "Agent run context builder should attach the plan tool.")
        XCTAssertTrue(builderText.contains("ToolDefinition.browserInspect"), "Agent run context builder should attach the browser tool.")
        XCTAssertTrue(builderText.contains("ToolDefinition.computerUseDefinitions"), "Agent run context builder should attach Computer Use tools only when available.")
        XCTAssertTrue(builderText.contains("WorkspaceMemoryRememberToolExecutor.executionOverride"), "Agent run context builder should delegate memory tool execution.")
        XCTAssertTrue(memoryExecutorText.contains("didSaveMemory(in thread: ChatThread)"), "Memory save detection should live beside memory tool execution.")
        XCTAssertFalse(modelText.contains("activeRunner.additionalToolDefinitions"), "WorkspaceModel should not assemble per-run additional tool definitions inline.")
        XCTAssertFalse(modelText.contains("private func planToolExecutionOverride"), "WorkspaceModel should not own plan tool override assembly.")
        XCTAssertFalse(modelText.contains("private func browserToolExecutionOverride"), "WorkspaceModel should not own browser tool override assembly.")
        XCTAssertFalse(modelText.contains("private func memoryToolExecutionOverride"), "WorkspaceModel should not own memory tool override assembly.")
        XCTAssertFalse(modelText.contains("private nonisolated static func didSaveMemory"), "WorkspaceModel should not own memory-save event parsing.")
    }

    func testWorkspaceModelDelegatesAgentSendSession() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let sessionText = try Self.appSourceText(named: "WorkspaceAgentSendSession.swift")

        XCTAssertTrue(sessionText.contains("struct WorkspaceAgentSendSession"), "Agent send lifecycle should live in a focused session.")
        XCTAssertTrue(sessionText.contains("func run("), "Agent send lifecycle should be directly testable.")
        XCTAssertTrue(sessionText.contains("runner.send("), "The session should own the runner send call.")
        XCTAssertTrue(sessionText.contains("WorkspaceMemoryRememberToolExecutor.didSaveMemory"), "The session should report whether the run saved memory.")
        XCTAssertTrue(modelText.contains("WorkspaceAgentSendSession("), "WorkspaceModel should delegate agent send execution.")
        XCTAssertFalse(modelText.contains("activeRunner.send("), "WorkspaceModel should not own the low-level send call.")
        XCTAssertFalse(modelText.contains("WorkspaceMemoryRememberToolExecutor.didSaveMemory(in: thread)"), "WorkspaceModel should not inspect memory events after each send.")
    }

    func testWorkspaceModelDelegatesToolEventRecording() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let recorderText = try Self.appSourceText(named: "WorkspaceToolEventRecorder.swift")

        XCTAssertTrue(recorderText.contains("struct WorkspaceToolEventRecorder"), "Tool audit event construction should live in a focused recorder.")
        XCTAssertTrue(recorderText.contains("static func events"), "Tool event construction should be directly testable.")
        XCTAssertTrue(recorderText.contains("static func append"), "Thread mutation should be a thin append helper.")
        XCTAssertTrue(recorderText.contains("call.redactedForTranscript()"), "Tool call redaction should live beside queued-event construction.")
        XCTAssertTrue(recorderText.contains("result.ok ? .toolCompleted : .toolFailed"), "Completion/failure classification should live beside tool event construction.")
        XCTAssertTrue(modelText.contains("WorkspaceToolEventRecorder.append"), "WorkspaceModel should delegate tool audit event recording.")
        XCTAssertFalse(modelText.contains("call.redactedForTranscript()"), "WorkspaceModel should not own tool call redaction for transcript events.")
        XCTAssertFalse(modelText.contains("let resultJSON ="), "WorkspaceModel should not own tool result JSON payload construction.")
        XCTAssertFalse(modelText.contains("summary: \"\\(call.name) queued\""), "WorkspaceModel should not construct queued tool summaries directly.")
        XCTAssertFalse(modelText.contains("summary: \"\\(call.name) running\""), "WorkspaceModel should not construct running tool summaries directly.")
    }

    func testWorkspaceModelDelegatesToolCallExecutionRouting() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let executorText = try Self.appSourceText(named: "WorkspaceToolCallExecutor.swift")

        XCTAssertTrue(executorText.contains("struct WorkspaceToolCallExecutor"), "Tool-call routing should live in a focused executor.")
        XCTAssertTrue(executorText.contains("BrowserInspector.toolResult"), "The executor should own browser inspect routing.")
        XCTAssertTrue(executorText.contains("PlanUpdateToolExecutor.execute"), "The executor should own plan update routing.")
        XCTAssertTrue(executorText.contains("WorkspaceRemoteProjectToolExecutor.execute"), "The executor should own remote project routing.")
        XCTAssertTrue(executorText.contains("ToolDefinition.applyPatch.name"), "The executor should own apply-patch follow-up routing.")
        XCTAssertTrue(modelText.contains("workspaceToolCallExecutor(router:"), "WorkspaceModel should delegate tool execution routing.")
        XCTAssertFalse(modelText.contains("call.name == ToolDefinition.browserInspect.name"), "WorkspaceModel should not branch on browser inspect tool execution.")
        XCTAssertFalse(modelText.contains("call.name == ToolDefinition.planUpdate.name"), "WorkspaceModel should not branch on plan update tool execution.")
        XCTAssertFalse(modelText.contains("private func appendReviewDiffAfterPatchIfNeeded"), "WorkspaceModel should not own apply-patch review diff follow-up routing.")
        XCTAssertFalse(modelText.contains("private func executeReviewGitToolCall"), "WorkspaceModel should not own parallel review git routing.")
    }

    func testWorkspaceModelDelegatesShellToolCallPlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceShellToolCallPlanner.swift")

        XCTAssertTrue(plannerText.contains("enum WorkspaceShellToolCallPlanner"), "Local action shell tool-call planning should live in a focused planner.")
        XCTAssertTrue(plannerText.contains("static func localEnvironmentAction"), "Local environment action tool calls should be directly testable.")
        XCTAssertTrue(plannerText.contains("static func projectExtensionUpdate"), "Extension update tool calls should be directly testable.")
        XCTAssertTrue(plannerText.contains("ToolDefinition.shellRun.name"), "The planner should own the canonical shell tool name.")
        XCTAssertTrue(plannerText.contains("ToolArguments.json(arguments)"), "The planner should own shell argument JSON construction.")
        XCTAssertTrue(modelText.contains("WorkspaceShellToolCallPlanner.localEnvironmentAction"), "WorkspaceModel should delegate local action shell call construction.")
        XCTAssertTrue(modelText.contains("WorkspaceShellToolCallPlanner.projectExtensionUpdate"), "WorkspaceModel should delegate extension update shell call construction.")
        XCTAssertFalse(modelText.contains("arguments[\"environment\"] = environment"), "WorkspaceModel should not assemble local action environment arguments inline.")
        XCTAssertFalse(modelText.contains("arguments[\"timeoutSeconds\"] = timeoutSeconds"), "WorkspaceModel should not assemble local action timeout arguments inline.")
        XCTAssertFalse(modelText.contains("let command = manifest.updateCommand"), "WorkspaceModel should not parse extension update commands inline.")
    }

    func testWorkspaceModelDelegatesProjectMetadataLoading() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let loaderText = try Self.appSourceText(named: "WorkspaceProjectMetadataLoader.swift")

        XCTAssertTrue(loaderText.contains("enum WorkspaceProjectMetadataLoader"), "Project metadata loading should live in a focused loader.")
        XCTAssertTrue(loaderText.contains("ProjectInstructionLoader.load"), "Project instruction loading should stay with the metadata loader.")
        XCTAssertTrue(loaderText.contains("LocalEnvironmentActionLoader.load"), "Local environment action loading should stay with the metadata loader.")
        XCTAssertTrue(loaderText.contains("ProjectExtensionManifestLoader.load"), "Project extension loading should stay with the metadata loader.")
        XCTAssertTrue(loaderText.contains("MemoryNoteLoader.loadProject"), "Project memory loading should stay with the metadata loader.")
        XCTAssertTrue(loaderText.contains("SSHRemoteProjectContextLoader.load"), "SSH Remote context loading should stay with the metadata loader.")
        XCTAssertTrue(modelText.contains("WorkspaceProjectMetadataLoader.loadLocal"), "WorkspaceModel should delegate local project metadata loading.")
        XCTAssertTrue(modelText.contains("WorkspaceProjectContextRefresher.refreshRemoteProjectContext"), "WorkspaceModel should delegate SSH Remote project metadata refresh.")
        XCTAssertFalse(modelText.contains("ProjectInstructionLoader.load"), "WorkspaceModel should not load instruction files directly.")
        XCTAssertFalse(modelText.contains("LocalEnvironmentActionLoader.load"), "WorkspaceModel should not load local environment actions directly.")
        XCTAssertFalse(modelText.contains("ProjectExtensionManifestLoader.load"), "WorkspaceModel should not load project extensions directly.")
        XCTAssertFalse(modelText.contains("MemoryNoteLoader.loadProject"), "WorkspaceModel should not load project memories directly.")
        XCTAssertFalse(modelText.contains("SSHRemoteProjectContextLoader.load"), "WorkspaceModel should not load SSH Remote context directly.")
    }

    func testWorkspaceModelTestsDoNotOwnPureProjectLoaderCoverage() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let instructionTests = try Self.appTestSourceText(named: "ProjectInstructionLoaderTests.swift")
        let actionTests = try Self.appTestSourceText(named: "LocalEnvironmentActionLoaderTests.swift")
        let extensionTests = try Self.appTestSourceText(named: "ProjectExtensionManifestLoaderTests.swift")
        let memoryTests = try Self.appTestSourceText(named: "MemoryNoteLoaderTests.swift")

        XCTAssertTrue(instructionTests.contains("ProjectInstructionLoader.load"), "Project instruction loader coverage should live in its focused test file.")
        XCTAssertTrue(actionTests.contains("LocalEnvironmentActionLoader.load"), "Local environment loader coverage should live in its focused test file.")
        XCTAssertTrue(extensionTests.contains("ProjectExtensionManifestLoader.load"), "Project extension loader coverage should live in its focused test file.")
        XCTAssertTrue(memoryTests.contains("MemoryNoteLoader.loadProject"), "Project memory loader coverage should live in its focused test file.")
        XCTAssertFalse(modelTests.contains("ProjectInstructionLoader.load"), "WorkspaceModelTests should focus on model integration, not direct project instruction loader tests.")
        XCTAssertFalse(modelTests.contains("LocalEnvironmentActionLoader.load"), "WorkspaceModelTests should focus on model integration, not direct local environment loader tests.")
        XCTAssertFalse(modelTests.contains("ProjectExtensionManifestLoader.load"), "WorkspaceModelTests should focus on model integration, not direct extension loader tests.")
        XCTAssertFalse(modelTests.contains("MemoryNoteLoader.loadProject"), "WorkspaceModelTests should focus on model integration, not direct memory loader tests.")
    }

    func testWorkspaceMemoryIntegrationTestsOwnModelMemoryFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let memoryIntegrationTests = try Self.appTestSourceText(named: "WorkspaceMemoryIntegrationTests.swift")

        XCTAssertTrue(memoryIntegrationTests.contains("testMemoryNotesLoadGlobalAndProjectIntoThreadAndSurface"), "Workspace memory integration should live in a focused test file.")
        XCTAssertTrue(memoryIntegrationTests.contains("testSlashRememberWritesGlobalMemoryAndRefreshesThreadSurface"), "Slash remember integration should live in focused memory tests.")
        XCTAssertTrue(memoryIntegrationTests.contains("testAgentRememberToolWritesGlobalMemoryAndRefreshesThreadSurface"), "Agent memory tool integration should live in focused memory tests.")
        XCTAssertTrue(memoryIntegrationTests.contains("testMemoryDeleteWorkspaceCommandRemovesGlobalMemoryAndRefreshesThreadSurface"), "Memory delete integration should live in focused memory tests.")
        XCTAssertFalse(modelTests.contains("testMemoryNotesLoadGlobalAndProjectIntoThreadAndSurface"), "WorkspaceModelTests should not own memory integration flows.")
        XCTAssertFalse(modelTests.contains("testSlashRememberWritesGlobalMemoryAndRefreshesThreadSurface"), "WorkspaceModelTests should not own slash memory integration flows.")
        XCTAssertFalse(modelTests.contains("testAgentRememberToolWritesGlobalMemoryAndRefreshesThreadSurface"), "WorkspaceModelTests should not own agent memory integration flows.")
        XCTAssertFalse(modelTests.contains("testMemoryDeleteWorkspaceCommandRemovesGlobalMemoryAndRefreshesThreadSurface"), "WorkspaceModelTests should not own memory delete integration flows.")
    }

    func testWorkspaceMCPIntegrationTestsOwnModelMCPFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let mcpIntegrationTests = try Self.appTestSourceText(named: "WorkspaceMCPIntegrationTests.swift")

        XCTAssertTrue(mcpIntegrationTests.contains("testMCPServerLifecycleStartsStopsAndStopAllTerminatesProcesses"), "MCP lifecycle integration should live in a focused test file.")
        XCTAssertTrue(mcpIntegrationTests.contains("testReadyMCPServerCanBeCalledFromAgentTurn"), "MCP tool-call integration should live in focused MCP tests.")
        XCTAssertTrue(mcpIntegrationTests.contains("testReadyMCPResourceCanBeReadFromAgentTurn"), "MCP resource integration should live in focused MCP tests.")
        XCTAssertTrue(mcpIntegrationTests.contains("testReadyMCPPromptCanBeLoadedFromAgentTurn"), "MCP prompt integration should live in focused MCP tests.")
        XCTAssertTrue(mcpIntegrationTests.contains("testMCPToolCallRejectsUnadvertisedTools"), "MCP safety integration should live in focused MCP tests.")
        XCTAssertFalse(modelTests.contains("testMCPServerLifecycleStartsStopsAndStopAllTerminatesProcesses"), "WorkspaceModelTests should not own MCP lifecycle integration flows.")
        XCTAssertFalse(modelTests.contains("testReadyMCPServerCanBeCalledFromAgentTurn"), "WorkspaceModelTests should not own MCP tool-call integration flows.")
        XCTAssertFalse(modelTests.contains("testReadyMCPResourceCanBeReadFromAgentTurn"), "WorkspaceModelTests should not own MCP resource integration flows.")
        XCTAssertFalse(modelTests.contains("testReadyMCPPromptCanBeLoadedFromAgentTurn"), "WorkspaceModelTests should not own MCP prompt integration flows.")
        XCTAssertFalse(modelTests.contains("testMCPToolCallRejectsUnadvertisedTools"), "WorkspaceModelTests should not own MCP safety integration flows.")
    }

    func testWorkspaceProjectExtensionIntegrationTestsOwnModelExtensionFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let extensionIntegrationTests = try Self.appTestSourceText(named: "WorkspaceProjectExtensionIntegrationTests.swift")

        XCTAssertTrue(extensionIntegrationTests.contains("testProjectExtensionManifestsLoadIntoProjectSurface"), "Project extension manifest integration should live in focused extension integration tests.")
        XCTAssertTrue(extensionIntegrationTests.contains("testProjectExtensionUpdateCommandRunsAndRefreshesProjectMetadata"), "Project extension update integration should live in focused extension integration tests.")
        XCTAssertTrue(extensionIntegrationTests.contains("testProjectExtensionUpdateFailureKeepsManifestAndRecordsFailureNotice"), "Project extension update failure integration should live in focused extension integration tests.")
        XCTAssertFalse(modelTests.contains("testProjectExtensionManifestsLoadIntoProjectSurface"), "WorkspaceModelTests should not own project extension manifest integration flows.")
        XCTAssertFalse(modelTests.contains("testProjectExtensionUpdateCommandRunsAndRefreshesProjectMetadata"), "WorkspaceModelTests should not own project extension update integration flows.")
    }

    func testWorkspaceProjectIntegrationTestsOwnModelProjectFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let projectIntegrationTests = try Self.appTestSourceText(named: "WorkspaceProjectIntegrationTests.swift")

        XCTAssertTrue(projectIntegrationTests.contains("testModelPersistsProjectRegistryChanges"), "Project registry persistence should live in focused project integration tests.")
        XCTAssertTrue(projectIntegrationTests.contains("testSelectingProjectControlsNextChatAndWorkspaceRoot"), "Project selection workspace integration should live in focused project tests.")
        XCTAssertTrue(projectIntegrationTests.contains("testProjectLifecycleActionsRenameRefreshNewChatAndRemove"), "Project lifecycle command integration should live in focused project tests.")
        XCTAssertTrue(projectIntegrationTests.contains("testProjectInstructionsLoadIntoNewThreadsAndRefreshBeforeRun"), "Project instruction integration should live in focused project tests.")
        XCTAssertFalse(modelTests.contains("testModelPersistsProjectRegistryChanges"), "WorkspaceModelTests should not own project registry persistence integration flows.")
        XCTAssertFalse(modelTests.contains("testSelectingProjectControlsNextChatAndWorkspaceRoot"), "WorkspaceModelTests should not own project selection integration flows.")
        XCTAssertFalse(modelTests.contains("testProjectLifecycleActionsRenameRefreshNewChatAndRemove"), "WorkspaceModelTests should not own project lifecycle command integration flows.")
        XCTAssertFalse(modelTests.contains("testProjectInstructionsLoadIntoNewThreadsAndRefreshBeforeRun"), "WorkspaceModelTests should not own project instruction integration flows.")
    }

    func testWorkspaceRemoteProjectIntegrationTestsOwnModelRemoteProjectFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let remoteProjectIntegrationTests = try Self.appTestSourceText(named: "WorkspaceRemoteProjectIntegrationTests.swift")

        XCTAssertTrue(remoteProjectIntegrationTests.contains("testSlashSSHAddsRemoteProjectAndEnablesRemoteGitActions"), "SSH project setup should live in focused remote project integration tests.")
        XCTAssertTrue(remoteProjectIntegrationTests.contains("testRemoteProjectAgentRunsShellThroughSSH"), "Remote shell agent execution should live in focused remote project integration tests.")
        XCTAssertTrue(remoteProjectIntegrationTests.contains("testRemoteProjectAgentCreatesPullRequestThroughSSH"), "Remote PR creation should live in focused remote project integration tests.")
        XCTAssertTrue(remoteProjectIntegrationTests.contains("testRemoteProjectRejectsUnsafeWorktreePathBeforeSSH"), "Remote worktree safety coverage should live in focused remote project integration tests.")
        XCTAssertFalse(modelTests.contains("testSlashSSHAddsRemoteProjectAndEnablesRemoteGitActions"), "WorkspaceModelTests should not own SSH project setup integration flows.")
        XCTAssertFalse(modelTests.contains("testRemoteProjectAgentRunsShellThroughSSH"), "WorkspaceModelTests should not own remote shell agent integration flows.")
        XCTAssertFalse(modelTests.contains("testRemoteProjectAgentCreatesPullRequestThroughSSH"), "WorkspaceModelTests should not own remote PR creation integration flows.")
        XCTAssertFalse(modelTests.contains("testRemoteProjectRejectsUnsafeWorktreePathBeforeSSH"), "WorkspaceModelTests should not own remote worktree safety integration flows.")
    }

    func testWorkspacePullRequestIntegrationTestsOwnModelPullRequestFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let pullRequestIntegrationTests = try Self.appTestSourceText(named: "WorkspacePullRequestIntegrationTests.swift")

        XCTAssertTrue(pullRequestIntegrationTests.contains("testRemoteWorkspaceCommandsViewPullRequestAndChecksThroughSSH"), "Remote PR workspace commands should live in focused pull request integration tests.")
        XCTAssertTrue(pullRequestIntegrationTests.contains("testPullRequestSlashCommandsDispatchStructuredGitHubToolsThroughSSH"), "PR slash command dispatch should live in focused pull request integration tests.")
        XCTAssertTrue(pullRequestIntegrationTests.contains("testWorkspacePullRequestCommandsPrefillComposer"), "PR command prefills should live in focused pull request integration tests.")
        XCTAssertTrue(pullRequestIntegrationTests.contains("makeRemotePullRequestFixture"), "Repeated fake GitHub CLI plus SSH setup should stay centralized in the PR integration suite.")

        XCTAssertFalse(modelTests.contains("testRemoteWorkspaceCommandsViewPullRequestAndChecksThroughSSH"), "WorkspaceModelTests should not own remote PR workspace command integration.")
        XCTAssertFalse(modelTests.contains("testPullRequestSlashCommandsDispatchStructuredGitHubToolsThroughSSH"), "WorkspaceModelTests should not own PR slash command integration.")
        XCTAssertFalse(modelTests.contains("testWorkspacePullRequestCommandsPrefillComposer"), "WorkspaceModelTests should not own PR command prefill integration.")
        XCTAssertFalse(modelTests.contains("makeRemotePullRequestFixture"), "WorkspaceModelTests should not own PR integration fixture setup.")
    }

    func testWorkspaceWorktreeIntegrationTestsOwnModelWorktreeFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let worktreeIntegrationTests = try Self.appTestSourceText(named: "WorkspaceWorktreeIntegrationTests.swift")

        XCTAssertTrue(worktreeIntegrationTests.contains("testWorkspaceCommandListsGitWorktrees"), "Local worktree listing should live in focused worktree integration tests.")
        XCTAssertTrue(worktreeIntegrationTests.contains("testRemoteWorkspaceCommandListsGitWorktreesThroughSSH"), "SSH Remote worktree listing should live in focused worktree integration tests.")
        XCTAssertTrue(worktreeIntegrationTests.contains("testWorkspaceWorktreeCommandsPrefillComposer"), "Worktree command prefill should live in focused worktree integration tests.")
        XCTAssertTrue(worktreeIntegrationTests.contains("testWorkspaceCreateWorktreeOpensFocusedThreadAndKeepsToolAudit"), "Local worktree create/open integration should live in focused worktree integration tests.")
        XCTAssertTrue(worktreeIntegrationTests.contains("testRemoteWorkspaceCreateWorktreeOpensSSHProjectAndKeepsToolAudit"), "SSH Remote worktree create/open integration should live in focused worktree integration tests.")

        XCTAssertFalse(modelTests.contains("testWorkspaceCommandListsGitWorktrees"), "WorkspaceModelTests should not own local worktree listing integration.")
        XCTAssertFalse(modelTests.contains("testRemoteWorkspaceCommandListsGitWorktreesThroughSSH"), "WorkspaceModelTests should not own SSH Remote worktree listing integration.")
        XCTAssertFalse(modelTests.contains("testWorkspaceWorktreeCommandsPrefillComposer"), "WorkspaceModelTests should not own worktree command prefill integration.")
        XCTAssertFalse(modelTests.contains("testWorkspaceCreateWorktreeOpensFocusedThreadAndKeepsToolAudit"), "WorkspaceModelTests should not own local worktree create/open integration.")
        XCTAssertFalse(modelTests.contains("testRemoteWorkspaceCreateWorktreeOpensSSHProjectAndKeepsToolAudit"), "WorkspaceModelTests should not own SSH Remote worktree create/open integration.")
    }

    func testWorkspaceBrowserIntegrationTestsOwnModelBrowserFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let browserIntegrationTests = try Self.appTestSourceText(named: "WorkspaceBrowserIntegrationTests.swift")

        XCTAssertTrue(browserIntegrationTests.contains("testBrowserPreviewNormalizesURLsAndStoresComments"), "Browser preview URL and comment integration should live in focused browser integration tests.")
        XCTAssertTrue(browserIntegrationTests.contains("testBrowserPreviewSupportsHistoryNavigationAndReload"), "Browser history integration should live in focused browser integration tests.")
        XCTAssertTrue(browserIntegrationTests.contains("testBrowserPreviewFetchesReachableHTMLSnapshot"), "Browser HTML fetch integration should live in focused browser integration tests.")
        XCTAssertTrue(browserIntegrationTests.contains("testBrowserPreviewKeepsMetadataSnapshotWhenHTMLFetchFails"), "Browser fetch-failure fallback integration should live in focused browser integration tests.")
        XCTAssertTrue(browserIntegrationTests.contains("testComposerCanInspectCurrentBrowserPage"), "Composer browser inspection integration should live in focused browser integration tests.")
        XCTAssertFalse(modelTests.contains("testBrowserPreviewNormalizesURLsAndStoresComments"), "WorkspaceModelTests should not own browser preview URL and comment integration flows.")
        XCTAssertFalse(modelTests.contains("testBrowserPreviewSupportsHistoryNavigationAndReload"), "WorkspaceModelTests should not own browser history integration flows.")
        XCTAssertFalse(modelTests.contains("testBrowserPreviewFetchesReachableHTMLSnapshot"), "WorkspaceModelTests should not own browser HTML fetch integration flows.")
        XCTAssertFalse(modelTests.contains("testBrowserPreviewKeepsMetadataSnapshotWhenHTMLFetchFails"), "WorkspaceModelTests should not own browser fetch-failure fallback integration flows.")
        XCTAssertFalse(modelTests.contains("testComposerCanInspectCurrentBrowserPage"), "WorkspaceModelTests should not own composer browser inspection integration flows.")
    }

    func testWorkspaceReviewIntegrationTestsOwnModelReviewFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let reviewIntegrationTests = try Self.appTestSourceText(named: "WorkspaceReviewIntegrationTests.swift")

        XCTAssertTrue(reviewIntegrationTests.contains("testApplyPatchToolRunRefreshesReviewDiff"), "Apply-patch diff refresh integration should live in focused review integration tests.")
        XCTAssertTrue(reviewIntegrationTests.contains("testRunReviewStageActionStagesFileAndRefreshesDiff"), "Local review stage integration should live in focused review integration tests.")
        XCTAssertTrue(reviewIntegrationTests.contains("testRemoteProjectReviewStageActionRunsThroughSSHAndRefreshesDiff"), "Remote review stage integration should live in focused review integration tests.")
        XCTAssertTrue(reviewIntegrationTests.contains("testAddReviewCommentAppendsThreadEventForVisibleDiffFile"), "Review comment integration should live in focused review integration tests.")
        XCTAssertTrue(reviewIntegrationTests.contains("testRunReviewStageHunkActionStagesPatchAndRefreshesDiff"), "Review hunk integration should live in focused review integration tests.")
        XCTAssertFalse(modelTests.contains("testApplyPatchToolRunRefreshesReviewDiff"), "WorkspaceModelTests should not own apply-patch review diff refresh integration flows.")
        XCTAssertFalse(modelTests.contains("testRunReviewStageActionStagesFileAndRefreshesDiff"), "WorkspaceModelTests should not own local review stage integration flows.")
        XCTAssertFalse(modelTests.contains("testRemoteProjectReviewStageActionRunsThroughSSHAndRefreshesDiff"), "WorkspaceModelTests should not own remote review stage integration flows.")
        XCTAssertFalse(modelTests.contains("testAddReviewCommentAppendsThreadEventForVisibleDiffFile"), "WorkspaceModelTests should not own review comment integration flows.")
        XCTAssertFalse(modelTests.contains("testRunReviewStageHunkActionStagesPatchAndRefreshesDiff"), "WorkspaceModelTests should not own review hunk integration flows.")
    }

    func testWorkspaceComposerIntegrationTestsOwnModelComposerFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let composerIntegrationTests = try Self.appTestSourceText(named: "WorkspaceComposerIntegrationTests.swift")

        XCTAssertTrue(composerIntegrationTests.contains("testSubmitComposerRunsToolAndBuildsToolCard"), "Composer tool-card integration should live in focused composer integration tests.")
        XCTAssertTrue(composerIntegrationTests.contains("testSubmitComposerSurfacesToolArtifacts"), "Composer artifact integration should live in focused composer integration tests.")
        XCTAssertTrue(composerIntegrationTests.contains("testSubmitComposerDispatchesComputerUseToolThroughBackend"), "Composer Computer Use integration should live in focused composer integration tests.")
        XCTAssertTrue(composerIntegrationTests.contains("testSubmitComposerStreamsQueuedToolBeforeCompletion"), "Composer queued-tool streaming integration should live in focused composer integration tests.")
        XCTAssertTrue(composerIntegrationTests.contains("testCancellingComposerRunStopsStateAndRecordsNotice"), "Composer cancellation integration should live in focused composer integration tests.")
        XCTAssertTrue(composerIntegrationTests.contains("testCompletedComposerRunDoesNotStealSelectionAfterUserSwitchesThreads"), "Composer selection-race integration should live in focused composer integration tests.")
        XCTAssertFalse(modelTests.contains("testSubmitComposerRunsToolAndBuildsToolCard"), "WorkspaceModelTests should not own composer tool-card integration flows.")
        XCTAssertFalse(modelTests.contains("testSubmitComposerSurfacesToolArtifacts"), "WorkspaceModelTests should not own composer artifact integration flows.")
        XCTAssertFalse(modelTests.contains("testSubmitComposerDispatchesComputerUseToolThroughBackend"), "WorkspaceModelTests should not own composer Computer Use integration flows.")
        XCTAssertFalse(modelTests.contains("testSubmitComposerStreamsQueuedToolBeforeCompletion"), "WorkspaceModelTests should not own composer queued-tool streaming integration flows.")
        XCTAssertFalse(modelTests.contains("testCancellingComposerRunStopsStateAndRecordsNotice"), "WorkspaceModelTests should not own composer cancellation integration flows.")
        XCTAssertFalse(modelTests.contains("testCompletedComposerRunDoesNotStealSelectionAfterUserSwitchesThreads"), "WorkspaceModelTests should not own composer selection-race integration flows.")
    }

    func testFocusedFeedbackAndArtifactTestsOwnSurfaceSpecificFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let feedbackIntegrationTests = try Self.appTestSourceText(named: "WorkspaceFeedbackIntegrationTests.swift")
        let toolCardSurfaceTests = try Self.appTestSourceText(named: "QuillCodeToolCardSurfaceTests.swift")

        XCTAssertTrue(feedbackIntegrationTests.contains("testMessageFeedbackIsStoredAndSurfaced"), "Message feedback persistence and transcript surfacing should live in focused feedback integration tests.")
        XCTAssertTrue(toolCardSurfaceTests.contains("testArtifactStateDerivesLinksAndImagePreviews"), "Image artifact surface derivation should live in focused tool-card surface tests.")
        XCTAssertTrue(toolCardSurfaceTests.contains("testArtifactStateDerivesDocumentPreviews"), "Document artifact surface derivation should live in focused tool-card surface tests.")
        XCTAssertFalse(modelTests.contains("testMessageFeedbackIsStoredAndSurfaced"), "WorkspaceModelTests should not own message feedback integration flows.")
        XCTAssertFalse(modelTests.contains("testArtifactStateDerivesLinksAndImagePreviews"), "WorkspaceModelTests should not own image artifact surface derivation.")
        XCTAssertFalse(modelTests.contains("testArtifactStateDerivesDocumentPreviews"), "WorkspaceModelTests should not own document artifact surface derivation.")
    }

    func testWorkspaceRuntimeIssueIntegrationTestsOwnModelRuntimeIssueFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let runtimeIntegrationTests = try Self.appTestSourceText(named: "WorkspaceRuntimeIssueIntegrationTests.swift")

        XCTAssertTrue(runtimeIntegrationTests.contains("testApplyRuntimeRefreshesAgentStatus"), "Runtime status application should live in focused runtime issue integration tests.")
        XCTAssertTrue(runtimeIntegrationTests.contains("testRuntimeIssueSurfacesMissingTrustedRouterSignIn"), "Runtime sign-in issue surfacing should live in focused runtime issue integration tests.")
        XCTAssertTrue(runtimeIntegrationTests.contains("testRuntimeIssueNormalizesRejectedTrustedRouterKey"), "Runtime key rejection surfacing should live in focused runtime issue integration tests.")
        XCTAssertTrue(runtimeIntegrationTests.contains("testRuntimeIssueNormalizesTrustedRouterRateLimit"), "Runtime rate-limit surfacing should live in focused runtime issue integration tests.")
        XCTAssertTrue(runtimeIntegrationTests.contains("testRuntimeIssueIncludesRedactedDiagnostics"), "Runtime diagnostic redaction should live in focused runtime issue integration tests.")
        XCTAssertTrue(runtimeIntegrationTests.contains("testPrepareRetryLastUserTurnUsesLatestUserPromptAndClearsError"), "Retry recovery mutation should live in focused runtime issue integration tests.")
        XCTAssertFalse(modelTests.contains("testApplyRuntimeRefreshesAgentStatus"), "WorkspaceModelTests should not own runtime status application flows.")
        XCTAssertFalse(modelTests.contains("testRuntimeIssueSurfacesMissingTrustedRouterSignIn"), "WorkspaceModelTests should not own runtime sign-in issue surfacing.")
        XCTAssertFalse(modelTests.contains("testRuntimeIssueNormalizesRejectedTrustedRouterKey"), "WorkspaceModelTests should not own runtime key rejection surfacing.")
        XCTAssertFalse(modelTests.contains("testRuntimeIssueNormalizesTrustedRouterRateLimit"), "WorkspaceModelTests should not own runtime rate-limit surfacing.")
        XCTAssertFalse(modelTests.contains("testRuntimeIssueIncludesRedactedDiagnostics"), "WorkspaceModelTests should not own runtime diagnostic redaction.")
        XCTAssertFalse(modelTests.contains("testPrepareRetryLastUserTurnUsesLatestUserPromptAndClearsError"), "WorkspaceModelTests should not own retry recovery mutation flows.")
    }

    func testWorkspaceThreadLifecycleIntegrationTestsOwnModelLifecycleFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let lifecycleIntegrationTests = try Self.appTestSourceText(named: "WorkspaceThreadLifecycleIntegrationTests.swift")

        XCTAssertTrue(lifecycleIntegrationTests.contains("testNewChatSelectsThreadAndRefreshesTopBar"), "New chat selection and top-bar integration should live in focused thread lifecycle integration tests.")
        XCTAssertTrue(lifecycleIntegrationTests.contains("testForkFromLastCreatesBoundedThreadFromLatestUserTurn"), "Fork-from-last integration should live in focused thread lifecycle integration tests.")
        XCTAssertTrue(lifecycleIntegrationTests.contains("testWorkspaceCommandCompactContextCreatesBoundedThread"), "Compact-context integration should live in focused thread lifecycle integration tests.")
        XCTAssertTrue(lifecycleIntegrationTests.contains("testPinAndArchiveThreadByIDPersistChanges"), "Thread pin/archive persistence should live in focused thread lifecycle integration tests.")
        XCTAssertTrue(lifecycleIntegrationTests.contains("testRenameDuplicateUnarchiveAndDeleteThreadLifecycle"), "Thread rename/duplicate/unarchive/delete integration should live in focused thread lifecycle integration tests.")
        XCTAssertFalse(modelTests.contains("testNewChatSelectsThreadAndRefreshesTopBar"), "WorkspaceModelTests should not own new-chat lifecycle integration.")
        XCTAssertFalse(modelTests.contains("testForkFromLastCreatesBoundedThreadFromLatestUserTurn"), "WorkspaceModelTests should not own fork-from-last integration.")
        XCTAssertFalse(modelTests.contains("testWorkspaceCommandCompactContextCreatesBoundedThread"), "WorkspaceModelTests should not own compact-context integration.")
        XCTAssertFalse(modelTests.contains("testPinAndArchiveThreadByIDPersistChanges"), "WorkspaceModelTests should not own thread pin/archive persistence integration.")
        XCTAssertFalse(modelTests.contains("testRenameDuplicateUnarchiveAndDeleteThreadLifecycle"), "WorkspaceModelTests should not own thread rename/duplicate/unarchive/delete integration.")
    }

    func testWorkspaceSlashCommandIntegrationTestsOwnCoreSlashFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let slashIntegrationTests = try Self.appTestSourceText(named: "WorkspaceSlashCommandIntegrationTests.swift")

        XCTAssertTrue(slashIntegrationTests.contains("testSlashCommandsRouteToWorkspaceActions"), "Core slash-command dispatch should live in focused slash integration tests.")
        XCTAssertTrue(slashIntegrationTests.contains("testSlashEnvironmentActionListsAndRunsByName"), "Local environment slash integration should live in focused slash integration tests.")
        XCTAssertTrue(slashIntegrationTests.contains("testSlashThreadLifecycleCommands"), "Thread lifecycle slash integration should live in focused slash integration tests.")
        XCTAssertTrue(slashIntegrationTests.contains("testSlashStatusReportsWorkspaceState"), "Slash status integration should live in focused slash integration tests.")
        XCTAssertFalse(modelTests.contains("testSlashCommandsRouteToWorkspaceActions"), "WorkspaceModelTests should not own core slash-command dispatch flows.")
        XCTAssertFalse(modelTests.contains("testSlashEnvironmentActionListsAndRunsByName"), "WorkspaceModelTests should not own local environment slash integration flows.")
        XCTAssertFalse(modelTests.contains("testSlashThreadLifecycleCommands"), "WorkspaceModelTests should not own thread lifecycle slash integration flows.")
        XCTAssertFalse(modelTests.contains("testSlashStatusReportsWorkspaceState"), "WorkspaceModelTests should not own slash status integration flows.")
    }

    func testWorkspaceModelDelegatesSlashCommandDispatchPlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceSlashCommandDispatchPlanner.swift")
        let actionExecutorText = try Self.appSourceText(named: "WorkspaceSlashCommandActionExecutor.swift")
        let plannerTests = try Self.appTestSourceText(named: "WorkspaceSlashCommandDispatchPlannerTests.swift")

        XCTAssertTrue(plannerText.contains("enum WorkspaceSlashCommandDispatchAction"), "Slash dispatch actions should be typed values outside WorkspaceModel.")
        XCTAssertTrue(plannerText.contains("struct WorkspaceSlashCommandDispatchPlanner"), "Slash dispatch planning should live outside WorkspaceModel.")
        XCTAssertTrue(plannerText.contains("static func action("), "Slash dispatch mapping should be directly testable.")
        XCTAssertTrue(plannerText.contains("case .help:"), "Raw parsed slash-command cases should live in the planner.")
        XCTAssertTrue(plannerText.contains("case .environmentAction(let query):"), "Environment slash routing should live in the planner.")
        XCTAssertTrue(actionExecutorText.contains("extension QuillCodeWorkspaceModel"), "Slash action execution should live in a focused model extension.")
        XCTAssertTrue(actionExecutorText.contains("func runSlashCommandDispatchAction"), "Typed slash action application should live outside the main model file.")
        XCTAssertTrue(actionExecutorText.contains("switch action"), "The slash action executor should own the typed action switch.")
        XCTAssertTrue(modelText.contains("WorkspaceSlashCommandDispatchPlanner.action("), "WorkspaceModel should consume the slash dispatch planner.")
        XCTAssertTrue(modelText.contains("runSlashCommandDispatchAction(action, workspaceRoot: workspaceRoot)"), "WorkspaceModel should delegate typed slash action application.")
        XCTAssertTrue(plannerTests.contains("testExternalCommandFamiliesMapToTypedActions"), "Slash dispatch families should have focused planner coverage.")
        XCTAssertFalse(modelText.contains("switch command {\n        case .help:"), "WorkspaceModel should not switch directly over parsed slash commands.")
        XCTAssertFalse(modelText.contains("switch action {"), "WorkspaceModel should not own typed slash action application.")
        XCTAssertFalse(modelText.contains("case .appendTranscript"), "WorkspaceModel should not own typed slash transcript actions.")
        XCTAssertFalse(modelText.contains("case .setMode"), "WorkspaceModel should not own typed slash mode actions.")
        XCTAssertFalse(modelText.contains("WorkspaceSlashCommandTranscriptPlanner.workspaceCommandFailed"), "WorkspaceModel should not own slash workspace-command failure transcripts.")
        XCTAssertFalse(modelText.contains("case .unknown(let name):"), "WorkspaceModel should not own unknown slash-command transcripts.")
        XCTAssertFalse(modelText.contains("case .invalid(let message):"), "WorkspaceModel should not own invalid slash-command transcripts.")
    }

    func testWorkspaceLocalEnvironmentIntegrationTestsOwnModelLocalEnvironmentFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let localEnvironmentIntegrationTests = try Self.appTestSourceText(named: "WorkspaceLocalEnvironmentIntegrationTests.swift")

        XCTAssertTrue(localEnvironmentIntegrationTests.contains("testLocalEnvironmentActionsLoadAndRunFromCommandPaletteIDs"), "Local environment command-palette integration should live in focused local environment tests.")
        XCTAssertTrue(localEnvironmentIntegrationTests.contains("testLocalEnvironmentActionMetadataInjectsBoundedEnvironment"), "Local environment metadata integration should live in focused local environment tests.")
        XCTAssertTrue(localEnvironmentIntegrationTests.contains("testLocalEnvironmentActionMetadataRunsFromBoundedWorkingDirectory"), "Local environment working-directory integration should live in focused local environment tests.")
        XCTAssertTrue(localEnvironmentIntegrationTests.contains("testLocalEnvironmentActionMetadataPassesBoundedTimeout"), "Local environment timeout integration should live in focused local environment tests.")
        XCTAssertFalse(modelTests.contains("testLocalEnvironmentActionsLoadAndRunFromCommandPaletteIDs"), "WorkspaceModelTests should not own local environment command-palette integration flows.")
        XCTAssertFalse(modelTests.contains("testLocalEnvironmentActionMetadataInjectsBoundedEnvironment"), "WorkspaceModelTests should not own local environment metadata integration flows.")
        XCTAssertFalse(modelTests.contains("testLocalEnvironmentActionMetadataRunsFromBoundedWorkingDirectory"), "WorkspaceModelTests should not own local environment working-directory integration flows.")
        XCTAssertFalse(modelTests.contains("testLocalEnvironmentActionMetadataPassesBoundedTimeout"), "WorkspaceModelTests should not own local environment timeout integration flows.")
    }

    func testWorkspaceAutomationIntegrationTestsOwnModelAutomationFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let automationIntegrationTests = try Self.appTestSourceText(named: "WorkspaceAutomationIntegrationTests.swift")

        XCTAssertTrue(automationIntegrationTests.contains("testAutomationCommandsCreatePauseResumeAndDeletePersistedFollowUp"), "Automation command persistence should live in focused automation integration tests.")
        XCTAssertTrue(automationIntegrationTests.contains("testSlashFollowUpSchedulesCurrentThread"), "Slash follow-up scheduling should live in focused automation integration tests.")
        XCTAssertTrue(automationIntegrationTests.contains("testRunDueAutomationsRunsActiveDueThreadAndWorkspaceSchedules"), "Due automation runs should live in focused automation integration tests.")
        XCTAssertTrue(automationIntegrationTests.contains("testRunDueAutomationsHonorsLimit"), "Due automation limit integration should live in focused automation integration tests.")
        XCTAssertFalse(modelTests.contains("testAutomationCommandsCreatePauseResumeAndDeletePersistedFollowUp"), "WorkspaceModelTests should not own automation command persistence flows.")
        XCTAssertFalse(modelTests.contains("testSlashFollowUpSchedulesCurrentThread"), "WorkspaceModelTests should not own slash follow-up scheduling flows.")
        XCTAssertFalse(modelTests.contains("testRunDueAutomationsRunsActiveDueThreadAndWorkspaceSchedules"), "WorkspaceModelTests should not own due automation run flows.")
        XCTAssertFalse(modelTests.contains("testRunDueAutomationsHonorsLimit"), "WorkspaceModelTests should not own due automation limit integration flows.")
    }

    func testWorkspaceTerminalIntegrationTestsOwnModelTerminalFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let terminalIntegrationTests = try Self.appTestSourceText(named: "WorkspaceTerminalIntegrationTests.swift")

        XCTAssertTrue(terminalIntegrationTests.contains("testTerminalCommandRunsInWorkspaceRootAndRecordsOutput"), "Local terminal execution integration should live in focused terminal tests.")
        XCTAssertTrue(terminalIntegrationTests.contains("testTerminalCommandStreamsOutputBeforeCompletion"), "Terminal streaming integration should live in focused terminal tests.")
        XCTAssertTrue(terminalIntegrationTests.contains("testTerminalCommandPersistsCurrentDirectoryAcrossCommands"), "Terminal cwd persistence integration should live in focused terminal tests.")
        XCTAssertTrue(terminalIntegrationTests.contains("testTerminalCommandPersistsEnvironmentAcrossCommands"), "Terminal environment persistence integration should live in focused terminal tests.")
        XCTAssertTrue(terminalIntegrationTests.contains("testTerminalCommandRunsThroughSSHRemoteProject"), "SSH Remote terminal execution integration should live in focused terminal tests.")
        XCTAssertTrue(terminalIntegrationTests.contains("testTerminalCommandPersistsSSHRemoteCWDAndEnvironment"), "SSH Remote terminal cwd/environment integration should live in focused terminal tests.")
        XCTAssertTrue(terminalIntegrationTests.contains("testTerminalCancellationMarksRunningEntryStopped"), "Terminal cancellation integration should live in focused terminal tests.")
        XCTAssertFalse(modelTests.contains("testTerminalCommandRunsInWorkspaceRootAndRecordsOutput"), "WorkspaceModelTests should not own local terminal execution integration flows.")
        XCTAssertFalse(modelTests.contains("testTerminalCommandStreamsOutputBeforeCompletion"), "WorkspaceModelTests should not own terminal streaming integration flows.")
        XCTAssertFalse(modelTests.contains("testTerminalCommandPersistsCurrentDirectoryAcrossCommands"), "WorkspaceModelTests should not own terminal cwd persistence integration flows.")
        XCTAssertFalse(modelTests.contains("testTerminalCommandPersistsEnvironmentAcrossCommands"), "WorkspaceModelTests should not own terminal environment persistence integration flows.")
        XCTAssertFalse(modelTests.contains("testTerminalCommandRunsThroughSSHRemoteProject"), "WorkspaceModelTests should not own SSH Remote terminal execution integration flows.")
        XCTAssertFalse(modelTests.contains("testTerminalCommandPersistsSSHRemoteCWDAndEnvironment"), "WorkspaceModelTests should not own SSH Remote terminal cwd/environment integration flows.")
        XCTAssertFalse(modelTests.contains("testTerminalCancellationMarksRunningEntryStopped"), "WorkspaceModelTests should not own terminal cancellation integration flows.")
    }

    func testWorkspaceModelTestsDoNotOwnRuntimeFactoryCoverage() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let runtimeFactoryTests = try Self.appTestSourceText(named: "WorkspaceRuntimeFactoryTests.swift")

        XCTAssertTrue(runtimeFactoryTests.contains("QuillCodeRuntimeFactory("), "Runtime factory coverage should live in its focused test file.")
        XCTAssertTrue(runtimeFactoryTests.contains("fetchModelCatalog"), "Model catalog fallback coverage should stay with runtime factory tests.")
        XCTAssertTrue(runtimeFactoryTests.contains("QUILLCODE_USE_MOCK_LLM"), "Deterministic mock override coverage should stay with runtime factory tests.")
        XCTAssertFalse(modelTests.contains("QuillCodeRuntimeFactory("), "WorkspaceModelTests should focus on model integration, not runtime factory construction.")
        XCTAssertFalse(modelTests.contains("func testRuntimeFactory"), "WorkspaceModelTests should not own runtime factory test cases.")
    }

    func testWorkspaceModelDelegatesAutomationStateMutations() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let automationText = try Self.appSourceText(named: "WorkspaceAutomationEngine.swift")

        XCTAssertTrue(automationText.contains("enum WorkspaceAutomationStateReducer"), "Automation state mutation should live in a focused reducer.")
        XCTAssertTrue(automationText.contains("struct WorkspaceAutomationStateMutation"), "Automation state mutations should return typed mutation results.")
        XCTAssertTrue(automationText.contains("static func setItems"), "Automation sorting and visibility preservation should be reducer-owned.")
        XCTAssertTrue(automationText.contains("static func createThreadFollowUp"), "Thread follow-up creation should be reducer-owned.")
        XCTAssertTrue(automationText.contains("static func createWorkspaceSchedule"), "Workspace schedule creation should be reducer-owned.")
        XCTAssertTrue(automationText.contains("static func updateStatus"), "Automation status mutation should be reducer-owned.")
        XCTAssertTrue(automationText.contains("static func delete("), "Automation deletion should be reducer-owned.")
        XCTAssertTrue(automationText.contains("static func replace("), "Automation replacement should be reducer-owned.")
        XCTAssertTrue(modelText.contains("WorkspaceAutomationStateReducer.setItems"), "WorkspaceModel should delegate automation item setting.")
        XCTAssertTrue(modelText.contains("WorkspaceAutomationStateReducer.createThreadFollowUp"), "WorkspaceModel should delegate thread follow-up creation.")
        XCTAssertTrue(modelText.contains("WorkspaceAutomationStateReducer.createWorkspaceSchedule"), "WorkspaceModel should delegate workspace schedule creation.")
        XCTAssertTrue(modelText.contains("WorkspaceAutomationStateReducer.updateStatus"), "WorkspaceModel should delegate status changes.")
        XCTAssertTrue(modelText.contains("WorkspaceAutomationStateReducer.delete"), "WorkspaceModel should delegate deletion.")
        XCTAssertTrue(modelText.contains("WorkspaceAutomationStateReducer.replace"), "WorkspaceModel should delegate replacement.")
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

    func testWorkspaceModelDelegatesWorktreeOpenRecords() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let requestsText = try Self.appSourceText(named: "WorkspaceWorktreeRequests.swift")
        let engineText = try Self.appSourceText(named: "WorkspaceWorktreeOpenEngine.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceWorktreeToolCallPlanner.swift")

        XCTAssertTrue(requestsText.contains("public struct WorkspaceWorktreeCreateRequest"), "Worktree create requests should live outside WorkspaceModel.")
        XCTAssertTrue(requestsText.contains("public struct WorkspaceWorktreeRemoveRequest"), "Worktree remove requests should live outside WorkspaceModel.")
        XCTAssertTrue(engineText.contains("struct WorkspaceWorktreeOpenEngine"), "Opened-worktree thread construction should live in a focused engine.")
        XCTAssertTrue(engineText.contains("static func localThread"), "Local worktree handoff records should be directly testable.")
        XCTAssertTrue(engineText.contains("static func remoteThread"), "SSH Remote worktree handoff records should be directly testable.")
        XCTAssertTrue(plannerText.contains("enum WorkspaceWorktreeToolCallPlanner"), "Worktree tool-call JSON should live in a focused planner.")
        XCTAssertTrue(plannerText.contains("static func create"), "Worktree create tool calls should be directly testable.")
        XCTAssertTrue(plannerText.contains("static func remove"), "Worktree remove tool calls should be directly testable.")
        XCTAssertTrue(modelText.contains("WorkspaceWorktreeToolCallPlanner.create"), "WorkspaceModel should delegate worktree create tool-call construction.")
        XCTAssertTrue(modelText.contains("WorkspaceWorktreeToolCallPlanner.remove"), "WorkspaceModel should delegate worktree remove tool-call construction.")
        XCTAssertTrue(modelText.contains("WorkspaceWorktreeOpenEngine.localThread"), "WorkspaceModel should delegate local worktree handoff records.")
        XCTAssertTrue(modelText.contains("WorkspaceWorktreeOpenEngine.remoteThread"), "WorkspaceModel should delegate SSH Remote worktree handoff records.")
        XCTAssertTrue(modelText.contains("openCreatedWorktreeThread"), "WorkspaceModel should share selected-thread persistence for local and remote worktrees.")
        XCTAssertFalse(modelText.contains("ToolDefinition.gitWorktreeCreate.name"), "WorkspaceModel should not own worktree create tool-call details.")
        XCTAssertFalse(modelText.contains("ToolDefinition.gitWorktreeRemove.name"), "WorkspaceModel should not own worktree remove tool-call details.")
        XCTAssertFalse(modelText.contains("title: \"Worktree:"), "WorkspaceModel should not own worktree thread title copy.")
        XCTAssertFalse(modelText.contains("Opened remote worktree `"), "WorkspaceModel should not own remote worktree transcript copy.")
        XCTAssertFalse(modelText.contains("Opened worktree `"), "WorkspaceModel should not own local worktree transcript copy.")
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

    func testWorkspaceSurfaceDelegatesSecondaryPaneSurfaceContracts() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let secondaryText = try Self.appSourceText(named: "QuillCodeSecondaryPaneSurface.swift")
        let extensionRowText = try Self.appSourceText(named: "ProjectExtensionManifestSurface.swift")
        let memoryRowText = try Self.appSourceText(named: "MemoryNoteSurface.swift")
        let automationRowText = try Self.appSourceText(named: "AutomationWorkflowSurface.swift")

        XCTAssertTrue(secondaryText.contains("public struct WorkspaceExtensionsSurface"), "Extensions surface should live beside secondary-pane contracts.")
        XCTAssertTrue(secondaryText.contains("public struct WorkspaceMemoriesSurface"), "Memories surface should live beside secondary-pane contracts.")
        XCTAssertTrue(secondaryText.contains("public struct WorkspaceAutomationsSurface"), "Automations surface should live beside secondary-pane contracts.")
        XCTAssertTrue(secondaryText.contains("ProjectExtensionManifestSurface("), "Extensions surface should still delegate row projection to extension manifest rows.")
        XCTAssertTrue(secondaryText.contains("MemoryNoteSurface.init"), "Memories surface should still delegate row projection to memory note rows.")
        XCTAssertTrue(secondaryText.contains("AutomationWorkflowSurface.init"), "Automations surface should still delegate configured workflow row projection.")
        XCTAssertTrue(extensionRowText.contains("public struct ProjectExtensionManifestSurface"), "Extension manifest rows should live in a focused surface row file.")
        XCTAssertTrue(extensionRowText.contains("MCPToolDescriptor"), "MCP probe display compatibility should stay with extension surface rows.")
        XCTAssertTrue(extensionRowText.contains("public init(from decoder: Decoder)"), "Extension row decode compatibility should stay with the row contract.")
        XCTAssertTrue(memoryRowText.contains("public struct MemoryNoteSurface"), "Memory note rows should live in a focused surface row file.")
        XCTAssertTrue(memoryRowText.contains("memory-delete:"), "Memory delete command IDs should stay with memory note rows.")
        XCTAssertTrue(automationRowText.contains("public struct AutomationWorkflowSurface"), "Automation workflow rows should live in a focused surface row file.")
        XCTAssertTrue(automationRowText.contains("automation-run:"), "Automation row run actions should stay with automation workflow rows.")
        XCTAssertFalse(secondaryText.contains("public struct ProjectExtensionManifestSurface"), "Secondary pane aggregate should not own extension manifest row internals.")
        XCTAssertFalse(secondaryText.contains("public struct MemoryNoteSurface"), "Secondary pane aggregate should not own memory note row internals.")
        XCTAssertFalse(secondaryText.contains("public struct AutomationWorkflowSurface"), "Secondary pane aggregate should not own automation workflow row internals.")
        XCTAssertFalse(surfaceText.contains("public struct WorkspaceExtensionsSurface"), "WorkspaceSurface should not own Extensions surface records.")
        XCTAssertFalse(surfaceText.contains("public struct WorkspaceMemoriesSurface"), "WorkspaceSurface should not own Memories surface records.")
        XCTAssertFalse(surfaceText.contains("public struct WorkspaceAutomationsSurface"), "WorkspaceSurface should not own Automations surface records.")
        XCTAssertFalse(surfaceText.contains("public struct ProjectExtensionManifestSurface"), "WorkspaceSurface should not own extension manifest rows.")
        XCTAssertFalse(surfaceText.contains("public struct MemoryNoteSurface"), "WorkspaceSurface should not own memory note rows.")
        XCTAssertFalse(surfaceText.contains("public struct AutomationWorkflowSurface"), "WorkspaceSurface should not own automation workflow rows.")
    }

    func testNativeSecondaryPanesUseFocusedViewFiles() throws {
        let workspaceText = try Self.appSourceText(named: "WorkspaceSwiftUIView.swift")
        let mainPaneText = try Self.appSourceText(named: "QuillCodeWorkspaceMainPaneView.swift")
        let chromeText = try Self.appSourceText(named: "QuillCodeSecondaryPanesView.swift")
        let extensionsText = try Self.appSourceText(named: "QuillCodeExtensionsPaneView.swift")
        let memoriesText = try Self.appSourceText(named: "QuillCodeMemoriesPaneView.swift")
        let automationsText = try Self.appSourceText(named: "QuillCodeAutomationsPaneView.swift")

        XCTAssertTrue(workspaceText.contains("QuillCodeWorkspaceMainPaneView"), "Workspace shell should delegate center-pane placement.")
        XCTAssertTrue(chromeText.contains("struct QuillCodePaneCountPill"), "Secondary pane count pills should remain shared native chrome.")
        XCTAssertTrue(chromeText.contains("struct QuillCodePaneEmptyStateView"), "Secondary pane empty states should remain shared native chrome.")
        XCTAssertTrue(extensionsText.contains("struct QuillCodeExtensionsPaneView"), "Extensions native UI should live in its own focused file.")
        XCTAssertTrue(extensionsText.contains("ProjectExtensionManifestSurface"), "MCP extension metadata display should stay with the Extensions native pane.")
        XCTAssertTrue(memoriesText.contains("struct QuillCodeMemoriesPaneView"), "Memories native UI should live in its own focused file.")
        XCTAssertTrue(automationsText.contains("struct QuillCodeAutomationsPaneView"), "Automations native UI should live in its own focused file.")
        XCTAssertTrue(mainPaneText.contains("QuillCodeExtensionsPaneView"), "Workspace main pane should route Extensions pane placement.")
        XCTAssertTrue(mainPaneText.contains("QuillCodeMemoriesPaneView"), "Workspace main pane should route Memories pane placement.")
        XCTAssertTrue(mainPaneText.contains("QuillCodeAutomationsPaneView"), "Workspace main pane should route Automations pane placement.")
        XCTAssertFalse(workspaceText.contains("QuillCodeExtensionsPaneView"), "Workspace shell should not own Extensions pane placement.")
        XCTAssertFalse(workspaceText.contains("QuillCodeMemoriesPaneView"), "Workspace shell should not own Memories pane placement.")
        XCTAssertFalse(workspaceText.contains("QuillCodeAutomationsPaneView"), "Workspace shell should not own Automations pane placement.")
        XCTAssertFalse(chromeText.contains("struct QuillCodeExtensionsPaneView"), "Shared secondary chrome should not own Extensions pane content.")
        XCTAssertFalse(chromeText.contains("struct QuillCodeMemoriesPaneView"), "Shared secondary chrome should not own Memories pane content.")
        XCTAssertFalse(chromeText.contains("struct QuillCodeAutomationsPaneView"), "Shared secondary chrome should not own Automations pane content.")
    }

    func testWorkspaceHTMLRendererDelegatesToolCardRendering() throws {
        let htmlText = try Self.appSourceText(named: "WorkspaceHTMLRenderer.swift")
        let transcriptText = try Self.appSourceText(named: "WorkspaceHTMLTranscriptRenderer.swift")
        let toolCardText = try Self.appSourceText(named: "WorkspaceHTMLToolCardRenderer.swift")
        let primitivesText = try Self.appSourceText(named: "WorkspaceHTMLPrimitives.swift")

        XCTAssertTrue(toolCardText.contains("enum WorkspaceHTMLToolCardRenderer"), "HTML tool-card rendering should live in a focused renderer.")
        XCTAssertTrue(toolCardText.contains("static func render(_ card: ToolCardState"), "HTML tool-card rendering should expose a directly testable entry point.")
        XCTAssertTrue(toolCardText.contains("private static func renderArtifacts"), "Artifact chip rendering should live beside tool-card HTML.")
        XCTAssertTrue(toolCardText.contains("private static func renderTextPreviews"), "Text-preview rendering should live beside tool-card HTML.")
        XCTAssertTrue(toolCardText.contains("private static func renderDocumentPreviews"), "Document-preview rendering should live beside tool-card HTML.")
        XCTAssertTrue(toolCardText.contains("private static func renderImagePreviews"), "Image-preview rendering should live beside tool-card HTML.")
        XCTAssertTrue(primitivesText.contains("enum WorkspaceHTMLPrimitives"), "Shared HTML primitives should live outside feature renderers.")
        XCTAssertTrue(primitivesText.contains("static func escape"), "HTML escaping should have one implementation.")
        XCTAssertTrue(primitivesText.contains("static func executionContextChip"), "Execution-context chip HTML should be shared by tool cards and terminal rows.")
        XCTAssertTrue(toolCardText.contains("WorkspaceHTMLPrimitives.executionContextChip"), "Tool-card rows should use shared execution-context chip HTML.")
        XCTAssertTrue(htmlText.contains("WorkspaceHTMLTranscriptRenderer.render"), "WorkspaceHTMLRenderer should delegate transcript rendering.")
        XCTAssertTrue(transcriptText.contains("WorkspaceHTMLToolCardRenderer.render"), "Transcript HTML should delegate tool-card rows to the focused renderer.")
        XCTAssertFalse(htmlText.contains("private static func renderToolCard"), "WorkspaceHTMLRenderer should not own tool-card rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderToolArtifacts"), "WorkspaceHTMLRenderer should not own artifact chip rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderToolTextPreviews"), "WorkspaceHTMLRenderer should not own text-preview rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderToolDocumentPreviews"), "WorkspaceHTMLRenderer should not own document-preview rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderToolImagePreviews"), "WorkspaceHTMLRenderer should not own image-preview rendering.")
        XCTAssertFalse(htmlText.contains("private static func documentIcon"), "WorkspaceHTMLRenderer should not own document-preview icon labels.")
    }

    func testWorkspaceHTMLRendererDelegatesTopBarRendering() throws {
        let htmlText = try Self.appSourceText(named: "WorkspaceHTMLRenderer.swift")
        let topBarText = try Self.appSourceText(named: "WorkspaceHTMLTopBarRenderer.swift")

        XCTAssertTrue(topBarText.contains("enum WorkspaceHTMLTopBarRenderer"), "HTML top-bar rendering should live in a focused renderer.")
        XCTAssertTrue(topBarText.contains("static func render(_ topBar: TopBarSurface"), "HTML top-bar rendering should expose a directly testable entry point.")
        XCTAssertFalse(topBarText.contains("renderPrimaryCluster"), "Send-time model/mode controls should not crowd top-bar HTML.")
        XCTAssertTrue(topBarText.contains("private static func renderStatusMetadata"), "Status semantics should stay available without visible top-bar chrome.")
        XCTAssertFalse(topBarText.contains("private static func renderStatusCluster"), "HTML top-bar should not reintroduce a visible status cluster.")
        XCTAssertTrue(topBarText.contains("private static func renderActionCluster"), "Overflow cluster rendering should live beside top-bar HTML.")
        XCTAssertTrue(topBarText.contains("private static func renderActivityHairline"), "Runtime and activity state should use quiet top-bar hairline rendering.")
        XCTAssertTrue(topBarText.contains("private static func renderRuntimeIssuePill"), "Runtime issue metadata rendering should live beside top-bar HTML.")
        XCTAssertTrue(topBarText.contains("TopBarOverflowCommandCatalog.commands"), "Top-bar overflow should use the shared command catalog.")
        XCTAssertTrue(topBarText.contains("WorkspaceHTMLPrimitives.escape"), "Top-bar renderer should reuse shared HTML escaping.")
        XCTAssertFalse(topBarText.contains("topbar-status-menu"), "HTML top-bar should not expose a status details menu in primary chrome.")
        XCTAssertFalse(topBarText.contains("top-bar-status-button"), "HTML top-bar should not expose a status button in primary chrome.")
        XCTAssertTrue(htmlText.contains("WorkspaceHTMLTopBarRenderer.render"), "WorkspaceHTMLRenderer should delegate top-bar rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderTopBar"), "WorkspaceHTMLRenderer should not own top-bar rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderTopBarOverflow"), "WorkspaceHTMLRenderer should not own top-bar overflow rendering.")
        XCTAssertFalse(htmlText.contains("topbar-primary-cluster"), "WorkspaceHTMLRenderer should not own top-bar cluster markup.")
        XCTAssertFalse(htmlText.contains("runtime-issue-pill"), "WorkspaceHTMLRenderer should not own runtime issue pill markup.")
        XCTAssertFalse(htmlText.contains("top-bar-overflow-popover"), "WorkspaceHTMLRenderer should not own top-bar overflow markup.")
    }

    func testComposerSeparatesModelAndApprovalModeControls() throws {
        let topBarViewText = try Self.appSourceText(named: "QuillCodeTopBarView.swift")
        let composerViewText = try Self.appSourceText(named: "QuillCodeComposerView.swift")
        let designText = try Self.appSourceText(named: "QuillCodeDesignSystem.swift")
        let modelPickerText = try Self.appSourceText(named: "QuillCodeModelPickerView.swift")
        let htmlTopBarText = try Self.appSourceText(named: "WorkspaceHTMLTopBarRenderer.swift")
        let htmlTranscriptText = try Self.appSourceText(named: "WorkspaceHTMLTranscriptRenderer.swift")

        XCTAssertFalse(topBarViewText.contains("QuillCodeModelPickerView"), "Top bar should not carry send-time model selection chrome.")
        XCTAssertTrue(composerViewText.contains("QuillCodeModelPickerView"), "Composer should expose send-time model selection.")
        XCTAssertTrue(composerViewText.contains("QuillCodeModePickerButton"), "Composer should expose a dedicated approval-mode control.")
        XCTAssertTrue(composerViewText.contains("composerSurface"), "Native composer should group input, send, model, and mode chrome into one focused surface.")
        XCTAssertTrue(composerViewText.contains("composerAccessoryBar"), "Native composer should keep model and mode controls as an input accessory bar.")
        XCTAssertTrue(composerViewText.contains("composerSurfaceStroke"), "Native composer should show focus feedback on the whole input surface.")
        XCTAssertTrue(designText.contains("composerSurfaceRadius: CGFloat = 12"), "Native composer should keep a compact code-editor radius.")
        XCTAssertTrue(topBarViewText.contains("Choose Auto safety mode"), "The mode control should advertise Auto safety intent.")
        XCTAssertTrue(topBarViewText.contains("selectedModeColor"), "Native mode control should give safety mode a distinct compact cue.")
        XCTAssertFalse(topBarViewText.contains(#"Text("Mode")"#), "Native mode control should keep the accessory bar compact.")
        XCTAssertFalse(topBarViewText.contains("modeColor(for:"), "Native mode control should not reuse health-status color semantics.")
        XCTAssertFalse(composerViewText.contains("topBar.agentStatus"), "Composer should not duplicate the top-bar agent status.")
        XCTAssertFalse(modelPickerText.contains("modeLabel"), "The model picker trigger and popover must not merge approval mode back into model selection.")
        XCTAssertNil(
            modelPickerText.range(of: #"\bvar\s+onSetMode\b"#, options: .regularExpression),
            "Model selection should not own approval-mode mutation."
        )
        XCTAssertNil(
            modelPickerText.range(of: #"\bonSetMode\s*:"#, options: .regularExpression),
            "Model picker initialization should not accept an approval-mode callback."
        )
        XCTAssertFalse(htmlTopBarText.contains("data-testid=\"model-picker-button\""), "HTML top bar should not expose the model control.")
        XCTAssertTrue(htmlTranscriptText.contains("data-testid=\"composer-surface\""), "HTML composer should mirror the native single-surface composer structure.")
        XCTAssertTrue(htmlTranscriptText.contains("class=\"composer-input-row\""), "HTML composer should keep text input and send/stop together inside the surface.")
        XCTAssertTrue(htmlTranscriptText.contains("composer-sr-only"), "HTML composer should keep the field label accessible but visually quiet.")
        XCTAssertTrue(htmlTranscriptText.contains("data-testid=\"model-picker-button\""), "HTML composer should expose a model control.")
        XCTAssertTrue(htmlTranscriptText.contains("data-testid=\"mode-picker-button\""), "HTML composer should expose a separate mode control.")
        XCTAssertFalse(htmlTranscriptText.contains("mode-prefix"), "HTML mode control should not add redundant label chrome.")
        XCTAssertTrue(htmlTranscriptText.contains("mode-dot"), "HTML mode control should remain visually distinct from the model picker.")
        XCTAssertFalse(htmlTopBarText.contains(" · "), "HTML top bar must not render model and mode as one combined label.")
    }

    func testWorkspaceHTMLRendererDelegatesTerminalRendering() throws {
        let htmlText = try Self.appSourceText(named: "WorkspaceHTMLRenderer.swift")
        let terminalText = try Self.appSourceText(named: "WorkspaceHTMLTerminalRenderer.swift")

        XCTAssertTrue(terminalText.contains("enum WorkspaceHTMLTerminalRenderer"), "HTML terminal rendering should live in a focused renderer.")
        XCTAssertTrue(terminalText.contains("static func render(_ terminal: TerminalSurface"), "HTML terminal rendering should expose a directly testable entry point.")
        XCTAssertTrue(terminalText.contains("private static func renderEntry"), "Terminal entry rendering should live beside terminal pane HTML.")
        XCTAssertTrue(terminalText.contains("private static func statusClass"), "Terminal status classes should live beside terminal pane HTML.")
        XCTAssertTrue(terminalText.contains("WorkspaceHTMLPrimitives.executionContextChip"), "Terminal rows should use shared execution-context chip HTML.")
        XCTAssertTrue(htmlText.contains("WorkspaceHTMLTerminalRenderer.render"), "WorkspaceHTMLRenderer should delegate terminal rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderTerminal"), "WorkspaceHTMLRenderer should not own terminal pane rendering.")
        XCTAssertFalse(htmlText.contains("private static func terminalStatusClass"), "WorkspaceHTMLRenderer should not own terminal status class mapping.")
    }

    func testNativeTerminalAndBrowserPanesUseFocusedViewFiles() throws {
        let appRoot = Self.packageRoot().appendingPathComponent("Sources/QuillCodeApp")
        for fileName in [
            "QuillCodeTerminalPaneView.swift",
            "QuillCodeTerminalEntryView.swift",
            "QuillCodeBrowserPaneView.swift"
        ] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: appRoot.appendingPathComponent(fileName).path), fileName)
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: appRoot.appendingPathComponent("QuillCodeTerminalBrowserPaneView.swift").path),
            "Terminal and browser panes should not drift back into one combined file."
        )

        let terminalText = try Self.appSourceText(named: "QuillCodeTerminalPaneView.swift")
        let terminalEntryText = try Self.appSourceText(named: "QuillCodeTerminalEntryView.swift")
        let browserText = try Self.appSourceText(named: "QuillCodeBrowserPaneView.swift")

        XCTAssertTrue(terminalText.contains("struct QuillCodeTerminalPaneView"), "Native terminal pane should have a focused owner.")
        XCTAssertTrue(terminalText.contains("QuillCodeTerminalEntryView"), "Terminal pane should compose the focused terminal-entry row.")
        XCTAssertTrue(terminalEntryText.contains("struct QuillCodeTerminalEntryView"), "Terminal entry rendering should have a focused owner.")
        XCTAssertTrue(browserText.contains("struct QuillCodeBrowserPaneView"), "Native browser pane should have a focused owner.")
        XCTAssertFalse(terminalText.contains("struct QuillCodeBrowserPaneView"), "Terminal pane file should not own browser rendering.")
        XCTAssertFalse(browserText.contains("struct QuillCodeTerminalPaneView"), "Browser pane file should not own terminal rendering.")
    }

    func testWorkspaceSurfaceDelegatesTerminalSurfaceContracts() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let terminalText = try Self.appSourceText(named: "QuillCodeTerminalSurface.swift")

        XCTAssertTrue(terminalText.contains("public struct TerminalSurface"), "Terminal surface should live beside terminal pane contracts.")
        XCTAssertTrue(terminalText.contains("public struct TerminalCommandSurface"), "Terminal command rows should live beside terminal pane contracts.")
        XCTAssertTrue(terminalText.contains("TerminalCommandState"), "Terminal surface rows should map terminal engine state directly.")
        XCTAssertTrue(terminalText.contains("ExecutionContextSurface?"), "Terminal command rows should preserve execution context chips.")
        XCTAssertFalse(surfaceText.contains("public struct TerminalSurface"), "WorkspaceSurface should not own terminal surface records.")
        XCTAssertFalse(surfaceText.contains("public struct TerminalCommandSurface"), "WorkspaceSurface should not own terminal command rows.")
    }

    func testTerminalStateContractsLiveOutsideEngine() throws {
        let engineText = try Self.appSourceText(named: "WorkspaceTerminalEngine.swift")
        let stateText = try Self.appSourceText(named: "WorkspaceTerminalState.swift")
        let adapterText = try Self.appSourceText(named: "WorkspaceTerminalSessionAdapter.swift")

        XCTAssertTrue(stateText.contains("public struct TerminalCommandState"), "Terminal command state should live in the terminal state contract file.")
        XCTAssertTrue(stateText.contains("public enum TerminalCommandStatus"), "Terminal command lifecycle labels should live in the terminal state contract file.")
        XCTAssertTrue(stateText.contains("public struct TerminalState"), "Terminal session state should live in the terminal state contract file.")
        XCTAssertTrue(stateText.contains("struct WorkspaceTerminalExecutionContext"), "Terminal execution context should live beside terminal state contracts.")
        XCTAssertTrue(stateText.contains("struct WorkspaceTerminalSessionResult"), "Terminal session result should live beside terminal state contracts.")
        XCTAssertTrue(engineText.contains("enum WorkspaceTerminalEngine"), "Terminal lifecycle reduction should remain in the terminal engine.")
        XCTAssertTrue(adapterText.contains("enum WorkspaceTerminalSessionAdapter"), "Terminal command wrapping should live in a focused session adapter.")
        XCTAssertTrue(adapterText.contains("static func localExecutionContext"), "Terminal session adapter should own local shell wrapping.")
        XCTAssertTrue(adapterText.contains("static func remoteWrappedCommand"), "Terminal session adapter should own remote shell wrapping.")
        XCTAssertTrue(adapterText.contains("static func sessionResult"), "Terminal session result parsing should live in the adapter.")
        XCTAssertTrue(adapterText.contains("static func remoteMetadata"), "Terminal session adapter should own remote marker parsing.")
        XCTAssertTrue(adapterText.contains("static func remoteEnvironmentDelta"), "Terminal session adapter should own remote environment deltas.")
        XCTAssertTrue(adapterText.contains("private static func environment(fromHex"), "Terminal session adapter should own remote environment decoding.")
        XCTAssertTrue(adapterText.contains("nonisolated static func shellSingleQuoted"), "Terminal session adapter should expose shared shell quoting for remote command builders.")
        XCTAssertTrue(engineText.contains("WorkspaceTerminalSessionAdapter.sessionResult"), "Terminal engine should delegate session marker parsing to the adapter.")
        XCTAssertFalse(engineText.contains("public struct TerminalCommandState"), "Terminal engine should not own command state DTO definitions.")
        XCTAssertFalse(engineText.contains("public enum TerminalCommandStatus"), "Terminal engine should not own command status DTO definitions.")
        XCTAssertFalse(engineText.contains("public struct TerminalState"), "Terminal engine should not own terminal session DTO definitions.")
        XCTAssertFalse(engineText.contains("struct WorkspaceTerminalExecutionContext"), "Terminal engine should not own execution context DTO definitions.")
        XCTAssertFalse(engineText.contains("struct WorkspaceTerminalSessionResult"), "Terminal engine should not own session result DTO definitions.")
        XCTAssertFalse(engineText.contains("static func localExecutionContext"), "Terminal engine should not own local shell wrapping.")
        XCTAssertFalse(engineText.contains("static func remoteWrappedCommand"), "Terminal engine should not own remote shell wrapping.")
        XCTAssertFalse(engineText.contains("struct RemoteTerminalMetadata"), "Terminal engine should not own remote marker metadata parsing.")
        XCTAssertFalse(engineText.contains("environment(fromHex"), "Terminal engine should not own remote environment decoding.")
    }

    func testWorkspaceHTMLRendererDelegatesBrowserRendering() throws {
        let htmlText = try Self.appSourceText(named: "WorkspaceHTMLRenderer.swift")
        let browserText = try Self.appSourceText(named: "WorkspaceHTMLBrowserRenderer.swift")

        XCTAssertTrue(browserText.contains("enum WorkspaceHTMLBrowserRenderer"), "HTML browser rendering should live in a focused renderer.")
        XCTAssertTrue(browserText.contains("static func render(_ browser: BrowserSurface"), "HTML browser rendering should expose a directly testable entry point.")
        XCTAssertTrue(browserText.contains("private static func renderPreview"), "Browser preview rendering should live beside browser pane HTML.")
        XCTAssertTrue(browserText.contains("private static func renderSnapshot"), "Browser snapshot rendering should live beside browser pane HTML.")
        XCTAssertTrue(browserText.contains("private static func renderComment"), "Browser comment rendering should live beside browser pane HTML.")
        XCTAssertTrue(browserText.contains("WorkspaceHTMLPrimitives.escape"), "Browser renderer should reuse shared HTML escaping.")
        XCTAssertTrue(htmlText.contains("WorkspaceHTMLBrowserRenderer.render"), "WorkspaceHTMLRenderer should delegate browser rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderBrowser"), "WorkspaceHTMLRenderer should not own browser pane rendering.")
        XCTAssertFalse(htmlText.contains("browser-snapshot-outline"), "WorkspaceHTMLRenderer should not own browser snapshot outline markup.")
        XCTAssertFalse(htmlText.contains("browser-comment"), "WorkspaceHTMLRenderer should not own browser comment markup.")
    }

    func testWorkspaceHTMLRendererDelegatesSecondaryPaneRendering() throws {
        let htmlText = try Self.appSourceText(named: "WorkspaceHTMLRenderer.swift")
        let secondaryText = try Self.appSourceText(named: "WorkspaceHTMLSecondaryPaneRenderer.swift")

        XCTAssertTrue(secondaryText.contains("enum WorkspaceHTMLSecondaryPaneRenderer"), "HTML secondary panes should live in a focused renderer.")
        XCTAssertTrue(secondaryText.contains("static func renderExtensions"), "Extensions HTML should expose a directly testable entry point.")
        XCTAssertTrue(secondaryText.contains("static func renderMemories"), "Memories HTML should expose a directly testable entry point.")
        XCTAssertTrue(secondaryText.contains("static func renderActivity"), "Activity HTML should expose a directly testable entry point.")
        XCTAssertTrue(secondaryText.contains("static func renderAutomations"), "Automation HTML should expose a directly testable entry point.")
        XCTAssertTrue(secondaryText.contains("private static func renderMCPTools"), "MCP tool chips should live beside Extensions HTML.")
        XCTAssertTrue(secondaryText.contains("private static func renderAutomationActions"), "Automation actions should live beside Automations HTML.")
        XCTAssertTrue(secondaryText.contains("WorkspaceHTMLPrimitives.escape"), "Secondary pane renderer should reuse shared HTML escaping.")
        XCTAssertTrue(htmlText.contains("WorkspaceHTMLSecondaryPaneRenderer.renderExtensions"), "WorkspaceHTMLRenderer should delegate Extensions rendering.")
        XCTAssertTrue(htmlText.contains("WorkspaceHTMLSecondaryPaneRenderer.renderMemories"), "WorkspaceHTMLRenderer should delegate Memories rendering.")
        XCTAssertTrue(htmlText.contains("WorkspaceHTMLSecondaryPaneRenderer.renderActivity"), "WorkspaceHTMLRenderer should delegate Activity rendering.")
        XCTAssertTrue(htmlText.contains("WorkspaceHTMLSecondaryPaneRenderer.renderAutomations"), "WorkspaceHTMLRenderer should delegate Automation rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderExtensions"), "WorkspaceHTMLRenderer should not own Extensions pane rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderMemories"), "WorkspaceHTMLRenderer should not own Memories pane rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderActivity"), "WorkspaceHTMLRenderer should not own Activity pane rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderAutomations"), "WorkspaceHTMLRenderer should not own Automations pane rendering.")
        XCTAssertFalse(htmlText.contains("private static func countLabel"), "WorkspaceHTMLRenderer should not own secondary-pane count labels.")
        XCTAssertFalse(htmlText.contains("extension-mcp-tool-schema"), "WorkspaceHTMLRenderer should not own MCP extension details markup.")
    }

    func testWorkspaceHTMLRendererDelegatesReviewRendering() throws {
        let htmlText = try Self.appSourceText(named: "WorkspaceHTMLRenderer.swift")
        let transcriptText = try Self.appSourceText(named: "WorkspaceHTMLTranscriptRenderer.swift")
        let reviewText = try Self.appSourceText(named: "WorkspaceHTMLReviewRenderer.swift")

        XCTAssertTrue(reviewText.contains("enum WorkspaceHTMLReviewRenderer"), "HTML review rendering should live in a focused renderer.")
        XCTAssertTrue(reviewText.contains("static func render(_ review: WorkspaceReviewSurface"), "HTML review rendering should expose a directly testable entry point.")
        XCTAssertTrue(reviewText.contains("private static func renderFile"), "Review file rendering should live beside review pane HTML.")
        XCTAssertTrue(reviewText.contains("private static func renderHunk"), "Review hunk rendering should live beside review pane HTML.")
        XCTAssertTrue(reviewText.contains("private static func renderLine"), "Review line rendering should live beside review pane HTML.")
        XCTAssertTrue(reviewText.contains("private static func renderAction"), "Review action rendering should live beside review pane HTML.")
        XCTAssertTrue(reviewText.contains("WorkspaceHTMLPrimitives.escape"), "Review renderer should reuse shared HTML escaping.")
        XCTAssertTrue(htmlText.contains("WorkspaceHTMLTranscriptRenderer.render"), "WorkspaceHTMLRenderer should delegate transcript rendering.")
        XCTAssertTrue(transcriptText.contains("WorkspaceHTMLReviewRenderer.render"), "Transcript HTML should delegate review panes to the focused renderer.")
        XCTAssertFalse(htmlText.contains("private static func renderReview"), "WorkspaceHTMLRenderer should not own review pane rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderReviewHunk"), "WorkspaceHTMLRenderer should not own review hunk rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderReviewLine"), "WorkspaceHTMLRenderer should not own review line rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderReviewAction"), "WorkspaceHTMLRenderer should not own review action rendering.")
        XCTAssertFalse(htmlText.contains("review-hunk-header"), "WorkspaceHTMLRenderer should not own review hunk markup.")
        XCTAssertFalse(htmlText.contains("review-line-marker"), "WorkspaceHTMLRenderer should not own review line markup.")
    }

    func testWorkspaceHTMLRendererDelegatesTranscriptRendering() throws {
        let htmlText = try Self.appSourceText(named: "WorkspaceHTMLRenderer.swift")
        let transcriptText = try Self.appSourceText(named: "WorkspaceHTMLTranscriptRenderer.swift")

        XCTAssertTrue(transcriptText.contains("enum WorkspaceHTMLTranscriptRenderer"), "HTML transcript rendering should live in a focused renderer.")
        XCTAssertTrue(transcriptText.contains("static func render("), "HTML transcript rendering should expose a directly testable entry point.")
        XCTAssertTrue(transcriptText.contains("static func renderComposer"), "HTML composer rendering should live beside transcript HTML.")
        XCTAssertTrue(transcriptText.contains("private static func renderRuntimeIssue"), "Runtime issue panel HTML should live beside transcript HTML.")
        XCTAssertTrue(transcriptText.contains("private static func renderTimelineItem"), "Timeline item HTML should live beside transcript HTML.")
        XCTAssertTrue(transcriptText.contains("private static func renderContextBanner"), "Context banner HTML should live beside transcript HTML.")
        XCTAssertTrue(transcriptText.contains("WorkspaceHTMLToolCardRenderer.render"), "Transcript HTML should delegate tool-card rows to the tool-card renderer.")
        XCTAssertTrue(transcriptText.contains("WorkspaceHTMLReviewRenderer.render"), "Transcript HTML should delegate review panes to the review renderer.")
        XCTAssertTrue(transcriptText.contains("WorkspaceHTMLPrimitives.escape"), "Transcript renderer should reuse shared HTML escaping.")
        XCTAssertTrue(htmlText.contains("WorkspaceHTMLTranscriptRenderer.render"), "WorkspaceHTMLRenderer should delegate transcript rendering.")
        XCTAssertTrue(htmlText.contains("WorkspaceHTMLTranscriptRenderer.renderComposer"), "WorkspaceHTMLRenderer should delegate composer rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderTranscript"), "WorkspaceHTMLRenderer should not own transcript rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderRuntimeIssue"), "WorkspaceHTMLRenderer should not own runtime issue panel rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderTimelineItem"), "WorkspaceHTMLRenderer should not own timeline item rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderMessageFeedbackActions"), "WorkspaceHTMLRenderer should not own message feedback markup.")
        XCTAssertFalse(htmlText.contains("private static func renderContextBanner"), "WorkspaceHTMLRenderer should not own context banner rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderComposer"), "WorkspaceHTMLRenderer should not own composer rendering.")
        XCTAssertFalse(htmlText.contains(#"data-testid="message-feedback-up""#), "WorkspaceHTMLRenderer should not own message action markup.")
        XCTAssertFalse(htmlText.contains(#"data-testid="runtime-issue""#), "WorkspaceHTMLRenderer should not own runtime issue markup.")
        XCTAssertFalse(htmlText.contains(#"data-testid="context-banner""#), "WorkspaceHTMLRenderer should not own context banner markup.")
    }

    func testWorkspaceSurfaceDelegatesReviewSurfaceContracts() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let reviewText = try Self.appSourceText(named: "QuillCodeReviewSurface.swift")

        XCTAssertTrue(reviewText.contains("public struct WorkspaceReviewSurface"), "Review surface should live beside review pane contracts.")
        XCTAssertTrue(reviewText.contains("public struct WorkspaceReviewFileSurface"), "Review file rows should live beside review pane contracts.")
        XCTAssertTrue(reviewText.contains("public struct WorkspaceReviewHunkSurface"), "Review hunk rows should live beside review pane contracts.")
        XCTAssertTrue(reviewText.contains("public struct WorkspaceReviewLineSurface"), "Review line rows should live beside review pane contracts.")
        XCTAssertTrue(reviewText.contains("public struct WorkspaceReviewCommentSurface"), "Review comment rows should live beside review pane contracts.")
        XCTAssertTrue(reviewText.contains("public struct WorkspaceReviewActionSurface"), "Review actions should live beside review pane contracts.")
        XCTAssertTrue(reviewText.contains("public enum WorkspaceReviewLineKind"), "Review line kind presentation should live beside review pane contracts.")
        XCTAssertTrue(reviewText.contains("public enum WorkspaceReviewActionKind"), "Review action presentation should live beside review pane contracts.")
        XCTAssertFalse(surfaceText.contains("public struct WorkspaceReviewSurface"), "WorkspaceSurface should not own review surface records.")
        XCTAssertFalse(surfaceText.contains("public struct WorkspaceReviewFileSurface"), "WorkspaceSurface should not own review file rows.")
        XCTAssertFalse(surfaceText.contains("public struct WorkspaceReviewHunkSurface"), "WorkspaceSurface should not own review hunk rows.")
        XCTAssertFalse(surfaceText.contains("public struct WorkspaceReviewLineSurface"), "WorkspaceSurface should not own review line rows.")
        XCTAssertFalse(surfaceText.contains("public struct WorkspaceReviewCommentSurface"), "WorkspaceSurface should not own review comment rows.")
        XCTAssertFalse(surfaceText.contains("public struct WorkspaceReviewActionSurface"), "WorkspaceSurface should not own review action rows.")
        XCTAssertFalse(surfaceText.contains("public enum WorkspaceReviewLineKind"), "WorkspaceSurface should not own review line kind presentation.")
        XCTAssertFalse(surfaceText.contains("public enum WorkspaceReviewActionKind"), "WorkspaceSurface should not own review action presentation.")
    }

    func testWorkspaceSurfaceDelegatesTranscriptSurfaceContracts() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let transcriptText = try Self.appSourceText(named: "QuillCodeTranscriptSurface.swift")

        XCTAssertTrue(transcriptText.contains("public struct TranscriptSurface"), "Transcript aggregate should live beside transcript contracts.")
        XCTAssertTrue(transcriptText.contains("public enum TranscriptTimelineItemKind"), "Transcript timeline kind should live beside transcript contracts.")
        XCTAssertTrue(transcriptText.contains("public struct TranscriptTimelineItemSurface"), "Transcript timeline rows should live beside transcript contracts.")
        XCTAssertTrue(transcriptText.contains("public struct ContextBannerSurface"), "Context banner presentation should live beside transcript contracts.")
        XCTAssertTrue(transcriptText.contains("public struct MessageSurface"), "Message presentation should live beside transcript contracts.")
        XCTAssertTrue(transcriptText.contains("public struct ComposerSurface"), "Composer presentation should live beside transcript contracts.")
        XCTAssertFalse(surfaceText.contains("public struct TranscriptSurface"), "WorkspaceSurface should not own transcript aggregate records.")
        XCTAssertFalse(surfaceText.contains("public enum TranscriptTimelineItemKind"), "WorkspaceSurface should not own transcript timeline kind presentation.")
        XCTAssertFalse(surfaceText.contains("public struct TranscriptTimelineItemSurface"), "WorkspaceSurface should not own transcript timeline rows.")
        XCTAssertFalse(surfaceText.contains("public struct ContextBannerSurface"), "WorkspaceSurface should not own context banner presentation.")
        XCTAssertFalse(surfaceText.contains("public struct MessageSurface"), "WorkspaceSurface should not own message presentation.")
        XCTAssertFalse(surfaceText.contains("public struct ComposerSurface"), "WorkspaceSurface should not own composer presentation.")
    }

    func testWorkspaceHTMLRendererDelegatesSidebarRendering() throws {
        let htmlText = try Self.appSourceText(named: "WorkspaceHTMLRenderer.swift")
        let sidebarText = try Self.appSourceText(named: "WorkspaceHTMLSidebarRenderer.swift")

        XCTAssertTrue(sidebarText.contains("enum WorkspaceHTMLSidebarRenderer"), "HTML sidebar rendering should live in a focused renderer.")
        XCTAssertTrue(sidebarText.contains("static func render("), "HTML sidebar rendering should expose a directly testable entry point.")
        XCTAssertTrue(sidebarText.contains("private static func renderProjects"), "Project-list rendering should live beside sidebar HTML.")
        XCTAssertTrue(sidebarText.contains("private static func renderThreadSections"), "Thread-section rendering should live beside sidebar HTML.")
        XCTAssertTrue(sidebarText.contains("private static func renderBulkToolbar"), "Bulk-selection rendering should live beside sidebar HTML.")
        XCTAssertTrue(sidebarText.contains("private static func renderFooter"), "Sidebar tool footer rendering should live beside sidebar HTML.")
        XCTAssertTrue(sidebarText.contains("private static func renderUtilityAction"), "Individual utility command HTML should live beside grouped sidebar rendering.")
        XCTAssertTrue(sidebarText.contains("WorkspaceHTMLPrimitives.escape"), "Sidebar renderer should reuse shared HTML escaping.")
        XCTAssertTrue(htmlText.contains("WorkspaceHTMLSidebarRenderer.render"), "WorkspaceHTMLRenderer should delegate sidebar rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderSidebar"), "WorkspaceHTMLRenderer should not own sidebar rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderSidebarPrimaryActions"), "WorkspaceHTMLRenderer should not own sidebar primary action rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderSidebarSection"), "WorkspaceHTMLRenderer should not own sidebar section rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderSidebarBulkToolbar"), "WorkspaceHTMLRenderer should not own sidebar bulk toolbar rendering.")
        XCTAssertFalse(htmlText.contains("sidebar-tools-popover"), "WorkspaceHTMLRenderer should not own sidebar footer markup.")
        XCTAssertFalse(htmlText.contains("project-empty"), "WorkspaceHTMLRenderer should not own project empty-state markup.")
    }

    func testWorkspaceSurfaceDelegatesReviewSurfaceBuilding() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceReviewSurfaceBuilder.swift")

        XCTAssertTrue(builderText.contains("struct WorkspaceReviewSurfaceBuilder"), "Review diff construction should live in a focused builder.")
        XCTAssertTrue(builderText.contains("func surface() -> WorkspaceReviewSurface"), "Review builder should expose directly testable review construction.")
        XCTAssertTrue(builderText.contains("latestCompletedGitDiffResult"), "Review builder should own latest git-diff result selection.")
        XCTAssertTrue(builderText.contains("reviewCommentBuckets"), "Review builder should own review comment bucketing.")
        XCTAssertTrue(surfaceText.contains("WorkspaceReviewSurfaceBuilder("), "WorkspaceSurface should delegate review construction.")
        XCTAssertFalse(surfaceText.contains("private func reviewSurface("), "WorkspaceSurface should not own review surface construction.")
        XCTAssertFalse(surfaceText.contains("reviewCommentBuckets"), "WorkspaceSurface should not own review comment bucketing.")
        XCTAssertFalse(surfaceText.contains("GitDiffReviewParser.parse"), "WorkspaceSurface should not parse git diffs directly.")
    }

    func testWorkspaceModelDelegatesReviewCommentPlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceReviewCommentPlanner.swift")

        XCTAssertTrue(plannerText.contains("public struct WorkspaceReviewCommentState"), "Review comment payload state should live beside the planner.")
        XCTAssertTrue(plannerText.contains("struct WorkspaceReviewCommentPlanner"), "Review comment event construction should live in a focused planner.")
        XCTAssertTrue(plannerText.contains("static func event"), "Review comment planning should be directly testable.")
        XCTAssertTrue(plannerText.contains("private static func normalizedRange"), "Review line-range normalization should be isolated in the planner.")
        XCTAssertTrue(plannerText.contains("private static func rangeExists"), "Review range validation should be isolated in the planner.")
        XCTAssertTrue(modelText.contains("WorkspaceReviewCommentPlanner.event"), "WorkspaceModel should delegate review comment planning.")
        XCTAssertFalse(modelText.contains("WorkspaceReviewCommentState: Codable"), "WorkspaceModel should not own review comment payload state.")
        XCTAssertFalse(modelText.contains("normalizedReviewRange"), "WorkspaceModel should not own review line-range normalization.")
        XCTAssertFalse(modelText.contains("reviewRangeExists"), "WorkspaceModel should not own review range validation.")
        XCTAssertFalse(modelText.contains("JSONHelpers.encodePretty(comment)"), "WorkspaceModel should not own review comment payload encoding.")
    }

    func testWorkspaceModelDelegatesReviewActionToolCallPlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceReviewActionToolCallPlanner.swift")

        XCTAssertTrue(plannerText.contains("struct WorkspaceReviewActionRunPlan"), "Review action run sequencing should live in a focused plan.")
        XCTAssertTrue(plannerText.contains("enum WorkspaceReviewActionToolCallPlanner"), "Review action tool-call planning should live in a focused planner.")
        XCTAssertTrue(plannerText.contains("static func runPlan"), "Review action run planning should be directly testable.")
        XCTAssertTrue(plannerText.contains("static func toolCall"), "Review action tool-call planning should be directly testable.")
        XCTAssertTrue(plannerText.contains("diffRefreshCall"), "Review diff refresh sequencing should live in the planner.")
        XCTAssertTrue(plannerText.contains("finalStatus"), "Review action status derivation should live in the planner.")
        XCTAssertTrue(plannerText.contains("ToolDefinition.gitStage.name"), "File stage calls should live in the planner.")
        XCTAssertTrue(plannerText.contains("ToolDefinition.gitRestore.name"), "File restore calls should live in the planner.")
        XCTAssertTrue(plannerText.contains("ToolDefinition.gitStageHunk.name"), "Hunk stage calls should live in the planner.")
        XCTAssertTrue(plannerText.contains("ToolDefinition.gitRestoreHunk.name"), "Hunk restore calls should live in the planner.")
        XCTAssertTrue(modelText.contains("WorkspaceReviewActionToolCallPlanner.runPlan"), "WorkspaceModel should delegate review action run planning.")
        XCTAssertFalse(modelText.contains("private extension WorkspaceReviewActionSurface"), "WorkspaceModel should not own review action surface extensions.")
        XCTAssertFalse(modelText.contains("var toolCall: ToolCall"), "WorkspaceModel should not own review action tool-call mapping.")
        XCTAssertFalse(modelText.contains("ToolCall(name: ToolDefinition.gitDiff.name"), "WorkspaceModel should not own review diff refresh call construction.")
        XCTAssertFalse(modelText.contains("ToolDefinition.gitStageHunk.name"), "WorkspaceModel should not own hunk review tool-call details.")
        XCTAssertFalse(modelText.contains("ToolDefinition.gitRestoreHunk.name"), "WorkspaceModel should not own hunk review tool-call details.")
    }

    func testWorkspaceModelDelegatesToolExecutionOverrideCombining() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceAgentRunContextBuilder.swift")
        let combinerText = try Self.appSourceText(named: "WorkspaceToolExecutionOverrideCombiner.swift")

        XCTAssertTrue(combinerText.contains("struct WorkspaceToolExecutionOverrideCombiner"), "Tool override composition should live in a focused helper.")
        XCTAssertTrue(combinerText.contains("static func combine"), "Tool override composition should expose a directly testable combine function.")
        XCTAssertTrue(combinerText.contains("plan?(call, workspaceRoot)"), "Plan override should keep first dispatch priority.")
        XCTAssertTrue(combinerText.contains("remoteProject?(call, workspaceRoot)"), "Remote-project override should stay before local browser/computer/memory/MCP overrides.")
        XCTAssertTrue(combinerText.contains("mcp?(call, workspaceRoot)"), "MCP override should keep final fallback priority.")
        XCTAssertTrue(builderText.contains("WorkspaceToolExecutionOverrideCombiner.combine"), "Agent run context builder should delegate override composition.")
        XCTAssertFalse(modelText.contains("WorkspaceToolExecutionOverrideCombiner.combine"), "WorkspaceModel should not compose per-run overrides directly.")
        XCTAssertFalse(modelText.contains("private func combinedToolExecutionOverride"), "WorkspaceModel should not own override composition.")
        XCTAssertFalse(modelText.contains("if let result = await plan?(call, workspaceRoot)"), "WorkspaceModel should not inline override precedence.")
    }
}
