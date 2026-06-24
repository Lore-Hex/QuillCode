import XCTest

final class ParityGateTests: XCTestCase {
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

    func testWorkspaceModelDelegatesToolCardSurfaceTypes() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let toolCardSurfaceText = try Self.appSourceText(named: "QuillCodeToolCardSurface.swift")
        let transcriptBuilderText = try Self.appSourceText(named: "WorkspaceTranscriptSurfaceBuilder.swift")

        XCTAssertTrue(toolCardSurfaceText.contains("public struct ToolCardState"), "Tool card surface state should live in a focused surface file.")
        XCTAssertTrue(toolCardSurfaceText.contains("public struct ToolArtifactState"), "Tool artifact surface state should live in a focused surface file.")
        XCTAssertTrue(toolCardSurfaceText.contains("enum ToolArtifactPreviewBuilder"), "Tool artifact preview construction should live beside artifact state.")
        XCTAssertTrue(transcriptBuilderText.contains("ToolArtifactPreviewBuilder.textPreview"), "Transcript projection should request artifact previews through the extracted builder.")
        XCTAssertFalse(modelText.contains("public struct ToolCardState"), "WorkspaceModel should not own tool card surface state.")
        XCTAssertFalse(modelText.contains("public enum ToolCardStatus"), "WorkspaceModel should not own tool card status.")
        XCTAssertFalse(modelText.contains("public struct ToolArtifactState"), "WorkspaceModel should not own tool artifact surface state.")
        XCTAssertFalse(modelText.contains("ToolArtifactPreviewBuilder.textPreview"), "WorkspaceModel should not own artifact-preview requests.")
    }

    func testActionableReviewCardsStayWiredThroughSurfaces() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let toolCardSurfaceText = try Self.appSourceText(named: "QuillCodeToolCardSurface.swift")
        let toolCardViewText = try Self.appSourceText(named: "QuillCodeToolCardView.swift")
        let transcriptViewText = try Self.appSourceText(named: "QuillCodeTranscriptView.swift")
        let workspaceViewText = try Self.appSourceText(named: "WorkspaceSwiftUIView.swift")
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
        XCTAssertTrue(workspaceViewText.contains("onToolCardAction"), "Workspace view should expose review-card actions to the host app.")
        XCTAssertTrue(modelText.contains("public func runToolCardAction"), "Workspace model should execute approved review-card actions.")
        XCTAssertTrue(htmlRendererText.contains("data-testid=\"tool-card-actions\""), "HTML harness should expose action buttons for Playwright.")
        XCTAssertTrue(htmlRendererText.contains("card.statusDisplayLabel"), "HTML cards should use the same human-facing status labels as native cards.")
        XCTAssertTrue(htmlRendererText.contains("card.reviewState.rawValue"), "HTML cards should expose review substate for E2E checks without parsing copy.")
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

        XCTAssertTrue(lifecycleText.contains("struct WorkspaceThreadLifecycleEngine"), "Thread lifecycle transitions should live in a focused engine.")
        XCTAssertTrue(lifecycleText.contains("static func renameThread"), "Thread rename mutation should be directly testable.")
        XCTAssertTrue(lifecycleText.contains("static func archiveThread"), "Thread archive fallback selection should be directly testable.")
        XCTAssertTrue(lifecycleText.contains("static func unarchiveThread"), "Thread unarchive mutation should be directly testable.")
        XCTAssertTrue(lifecycleText.contains("static func deleteThread"), "Thread delete fallback selection should be directly testable.")
        XCTAssertTrue(lifecycleText.contains("static func applyAgentRunThreadUpdate"), "Agent-run thread upsert and fallback selection should be directly testable.")
        XCTAssertTrue(modelText.contains("WorkspaceThreadLifecycleEngine.renameThread"), "WorkspaceModel should delegate thread rename mutation.")
        XCTAssertTrue(modelText.contains("WorkspaceThreadLifecycleEngine.archiveThread"), "WorkspaceModel should delegate thread archive mutation.")
        XCTAssertTrue(modelText.contains("WorkspaceThreadLifecycleEngine.deleteThread"), "WorkspaceModel should delegate thread delete mutation.")
        XCTAssertTrue(modelText.contains("WorkspaceThreadLifecycleEngine.applyAgentRunThreadUpdate"), "WorkspaceModel should delegate agent-run thread upsert and fallback selection.")
        XCTAssertFalse(modelText.contains("thread.title = trimmed"), "WorkspaceModel should not own thread rename mutation.")
        XCTAssertFalse(modelText.contains("thread.isArchived = true"), "WorkspaceModel should not own thread archive mutation.")
        XCTAssertFalse(modelText.contains("thread.isArchived = false"), "WorkspaceModel should not own thread unarchive mutation.")
        XCTAssertFalse(modelText.contains("private func upsertThread"), "WorkspaceModel should not own generic thread upsert mutation.")
        XCTAssertFalse(modelText.contains("private func selectUpdatedThread"), "WorkspaceModel should not own agent-run fallback selection mutation.")
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

    func testWorkspaceModelDelegatesStatusTextAndLabels() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceStatusTextBuilder.swift")
        let slashTranscriptText = try Self.appSourceText(named: "WorkspaceSlashCommandTranscriptPlanner.swift")

        XCTAssertTrue(builderText.contains("struct WorkspaceStatusTextBuilder"), "Workspace status text and labels should live in a focused builder.")
        XCTAssertTrue(builderText.contains("static func statusText"), "Slash status copy should be directly testable.")
        XCTAssertTrue(builderText.contains("static func topBarSubtitle"), "Top-bar subtitle copy should be directly testable.")
        XCTAssertTrue(builderText.contains("static func instructionLabel"), "Instruction status labels should be directly testable.")
        XCTAssertTrue(builderText.contains("static func memoryLabel"), "Memory status labels should be directly testable.")
        XCTAssertTrue(builderText.contains("static func modeLabel"), "Mode labels should be shared by status and UI surfaces.")
        XCTAssertTrue(modelText.contains("WorkspaceStatusTextBuilder.statusText"), "WorkspaceModel should delegate /status copy.")
        XCTAssertTrue(slashTranscriptText.contains("WorkspaceStatusTextBuilder.modeLabel"), "Slash mode transcript copy should delegate shared mode labels.")
        XCTAssertTrue(surfaceText.contains("WorkspaceStatusTextBuilder.topBarSubtitle"), "WorkspaceSurface should delegate top-bar subtitles.")
        XCTAssertTrue(surfaceText.contains("WorkspaceStatusTextBuilder.instructionLabel"), "WorkspaceSurface should delegate instruction labels.")
        XCTAssertTrue(surfaceText.contains("WorkspaceStatusTextBuilder.memoryLabel"), "WorkspaceSurface should delegate memory labels.")
        XCTAssertFalse(modelText.contains("No project instructions"), "WorkspaceModel should not own instruction status copy.")
        XCTAssertFalse(modelText.contains("No memories"), "WorkspaceModel should not own memory status copy.")
        XCTAssertFalse(modelText.contains("static func instructionStatusLabel"), "WorkspaceModel should not own instruction status labels.")
        XCTAssertFalse(modelText.contains("static func memoryStatusLabel"), "WorkspaceModel should not own memory status labels.")
        XCTAssertFalse(surfaceText.contains("static func modeLabel"), "WorkspaceSurface should not own mode label copy.")
    }

    func testWorkspaceModelDelegatesContextResolving() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let resolverText = try Self.appSourceText(named: "WorkspaceContextResolver.swift")

        XCTAssertTrue(resolverText.contains("struct WorkspaceContextResolver"), "Workspace context lookup should live in a focused resolver.")
        XCTAssertTrue(resolverText.contains("func instructions(for projectID:"), "Project instruction lookup should be directly testable.")
        XCTAssertTrue(resolverText.contains("func memoryNotes(for projectID:"), "Global/project memory merging should be directly testable.")
        XCTAssertTrue(resolverText.contains("func selectedLocalAction(withID"), "Local action ID lookup should be directly testable.")
        XCTAssertTrue(resolverText.contains("func selectedLocalAction(matching"), "Local action alias matching should be directly testable.")
        XCTAssertTrue(modelText.contains("WorkspaceContextResolver("), "WorkspaceModel should delegate context lookup through the resolver.")
        XCTAssertFalse(modelText.contains("private func instructions(for projectID"), "WorkspaceModel should not own project instruction lookup.")
        XCTAssertFalse(modelText.contains("private func memoryNotes(for projectID"), "WorkspaceModel should not own memory merging.")
        XCTAssertFalse(modelText.contains("private func localAction(withID"), "WorkspaceModel should not own local action ID lookup.")
        XCTAssertFalse(modelText.contains("private func localAction(matching"), "WorkspaceModel should not own local action matching.")
        XCTAssertFalse(modelText.contains("private static func normalizedActionName"), "WorkspaceModel should not own local action alias normalization.")
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

        XCTAssertTrue(mockText.contains("public struct MockLLMClient"), "The deterministic mock LLM client should live in its own file.")
        XCTAssertTrue(mockText.contains("extractPullRequestArguments"), "Mock PR parsing heuristics should stay with the mock client.")
        XCTAssertTrue(mockText.contains("AgentRunner.finalAnswer"), "Mock tool feedback should still reuse the production final-answer contract.")
        XCTAssertFalse(agentText.contains("public struct MockLLMClient"), "Agent.swift should not own mock LLM planning.")
        XCTAssertFalse(agentText.contains("extractPullRequestArguments"), "Agent.swift should not own mock PR parsing heuristics.")
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

        XCTAssertTrue(parserText.contains("public enum AgentActionJSONParser"), "Action JSON parsing should live in a focused parser file.")
        XCTAssertTrue(parserText.contains("canonicalArguments"), "Tool argument normalization should stay with the parser.")
        XCTAssertTrue(parserText.contains("recoverExplicitShellCommand"), "Malformed model-output recovery should stay with the parser.")
        XCTAssertTrue(clientText.contains("AgentActionStreamCollector.collect"), "TrustedRouter client should delegate action collection/parsing.")
        XCTAssertFalse(clientText.contains("public enum AgentActionJSONParser"), "TrustedRouter transport should not own action parsing.")
        XCTAssertFalse(clientText.contains("canonicalArguments"), "TrustedRouter transport should not own tool argument normalization.")
        XCTAssertFalse(clientText.contains("recoverExplicitShellCommand"), "TrustedRouter transport should not own malformed-output recovery.")
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
        let plannerText = try Self.appSourceText(named: "WorkspaceSlashCommandTranscriptPlanner.swift")

        XCTAssertTrue(plannerText.contains("struct WorkspaceLocalCommandTranscript"), "Local command transcript records should live beside the planner.")
        XCTAssertTrue(plannerText.contains("struct WorkspaceSlashCommandTranscriptPlanner"), "Slash command transcript copy should live in a focused planner.")
        XCTAssertTrue(plannerText.contains("static func sshProjectAdded"), "SSH success copy should be directly testable.")
        XCTAssertTrue(plannerText.contains("static func workspaceCommandFailed"), "Slash command failure copy should be directly testable.")
        XCTAssertTrue(plannerText.contains("SlashCommandCatalog.helpText()"), "Slash help text should stay catalog-backed.")
        for delegatedCall in [
            "WorkspaceSlashCommandTranscriptPlanner.help",
            "WorkspaceSlashCommandTranscriptPlanner.status",
            "WorkspaceSlashCommandTranscriptPlanner.mode",
            "WorkspaceSlashCommandTranscriptPlanner.model",
            "WorkspaceSlashCommandTranscriptPlanner.renameThread",
            "WorkspaceSlashCommandTranscriptPlanner.renameProject",
            "WorkspaceSlashCommandTranscriptPlanner.sshProjectAdded",
            "WorkspaceSlashCommandTranscriptPlanner.threadFollowUpScheduled",
            "WorkspaceSlashCommandTranscriptPlanner.workspaceScheduleScheduled",
            "WorkspaceSlashCommandTranscriptPlanner.workspaceCommandFailed",
            "WorkspaceSlashCommandTranscriptPlanner.environmentActions",
            "WorkspaceSlashCommandTranscriptPlanner.environmentActionNotFound",
            "WorkspaceSlashCommandTranscriptPlanner.invalid",
            "WorkspaceSlashCommandTranscriptPlanner.unknown"
        ] {
            XCTAssertTrue(modelText.contains(delegatedCall), "WorkspaceModel should delegate \(delegatedCall).")
        }
        XCTAssertFalse(modelText.contains("Could not rename this chat. Try /rename New chat title."), "WorkspaceModel should not own thread rename fallback copy.")
        XCTAssertFalse(modelText.contains("Could not rename this project. Try /project rename New project name."), "WorkspaceModel should not own project rename fallback copy.")
        XCTAssertFalse(modelText.contains("Use SSH format user@host:/path or ssh://user@host/path."), "WorkspaceModel should not own SSH fallback copy.")
        XCTAssertFalse(modelText.contains("Scheduled a thread follow-up for"), "WorkspaceModel should not own follow-up success copy.")
        XCTAssertFalse(modelText.contains("Scheduled a workspace check for"), "WorkspaceModel should not own workspace schedule success copy.")
        XCTAssertFalse(modelText.contains("Local environment actions:"), "WorkspaceModel should not own /env list copy.")
        XCTAssertFalse(modelText.contains("No local environment action matches"), "WorkspaceModel should not own /env missing-action copy.")
        XCTAssertFalse(modelText.contains("Unknown slash command"), "WorkspaceModel should not own unknown slash command copy.")
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
        XCTAssertTrue(modelText.contains("WorkspaceMemoryEngine.loadGlobal"), "WorkspaceModel should delegate global memory reloads.")
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

    func testTopBarViewsDelegateStatusPresentationSemantics() throws {
        let topBarViewText = try Self.appSourceText(named: "QuillCodeTopBarView.swift")
        let htmlRendererText = try Self.appSourceText(named: "WorkspaceHTMLTopBarRenderer.swift")
        let presentationText = try Self.appSourceText(named: "QuillCodeTopBarStatusPresentation.swift")

        XCTAssertTrue(presentationText.contains("public enum TopBarAgentStatusLabel"), "Shared status labels should live beside top-bar presentation semantics.")
        XCTAssertTrue(presentationText.contains("struct TopBarStatusPresentation"), "Top-bar status semantics should live in a focused presentation value.")
        XCTAssertTrue(presentationText.contains("static func agentStatus"), "Agent status classification should be directly testable.")
        XCTAssertTrue(presentationText.contains("struct TopBarRuntimeIssuePresentation"), "Runtime issue pill semantics should be directly testable.")
        XCTAssertTrue(topBarViewText.contains("topBar.agentStatusPresentation"), "Native top bar should use shared status presentation.")
        XCTAssertTrue(topBarViewText.contains("topBar.runtimeIssuePresentation"), "Native top bar should use shared runtime issue presentation.")
        XCTAssertTrue(htmlRendererText.contains("topBar.agentStatusPresentation"), "HTML top bar should use shared status presentation.")
        XCTAssertTrue(htmlRendererText.contains("topBar.runtimeIssuePresentation"), "HTML top bar should use shared runtime issue presentation.")
        XCTAssertFalse(topBarViewText.contains("lowercasedStatus.contains"), "Top-bar view should not own status string classification.")
        XCTAssertFalse(topBarViewText.contains("runtimeIssueSeverity == .error"), "Top-bar view should not own runtime issue tone classification.")
        XCTAssertFalse(htmlRendererText.contains("runtimeIssueSeverity?.rawValue"), "HTML renderer should not own runtime issue tone fallback logic.")
    }

    func testNativeTopBarKeepsCodexStyleChromeQuiet() throws {
        let topBarViewText = try Self.appSourceText(named: "QuillCodeTopBarView.swift")
        let designText = try Self.appSourceText(named: "QuillCodeDesignSystem.swift")

        XCTAssertTrue(topBarViewText.contains("contextLabel"), "Native top bar should preserve a quiet leading context label.")
        XCTAssertTrue(topBarViewText.contains("threadTitle"), "Native top bar should center the active thread title.")
        XCTAssertTrue(topBarViewText.contains("showsActivityHairline"), "Native top bar should show run/error state as a subtle hairline instead of another pill.")
        XCTAssertTrue(designText.contains("static let topBarHeight: CGFloat = 40"), "Native top bar should keep a compact Codex-style height.")
        XCTAssertFalse(topBarViewText.contains("statusIndicator"), "Native top bar should not reintroduce a permanent status pill.")
        XCTAssertFalse(topBarViewText.contains("QuillCodeTopBarPill"), "Native top bar should not reintroduce runtime issue pills into the main chrome.")
    }

    func testTopBarAgentStatusLabelsAreSharedByRuntimePaths() throws {
        let appStateText = try Self.appSourceText(named: "AppState.swift")
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceAgentStatusBuilder.swift")
        let mcpRuntimeText = try Self.appSourceText(named: "WorkspaceMCPRuntime.swift")

        XCTAssertTrue(appStateText.contains("agentStatus: String = TopBarAgentStatusLabel.idle"), "Root state should use the shared idle label default.")
        XCTAssertTrue(modelText.contains("TopBarAgentStatusLabel.running"), "WorkspaceModel should use shared running status copy.")
        XCTAssertTrue(modelText.contains("TopBarAgentStatusLabel.terminal"), "WorkspaceModel should use shared terminal status copy.")
        XCTAssertTrue(builderText.contains("TopBarAgentStatusLabel.streaming"), "Agent progress builder should use shared streaming status copy.")
        XCTAssertTrue(mcpRuntimeText.contains("TopBarAgentStatusLabel.failed"), "MCP runtime should use shared failed status copy.")
        XCTAssertFalse(modelText.contains("refreshTopBar(agentStatus: \""), "WorkspaceModel should not pass raw lifecycle status strings to the top bar.")
        XCTAssertFalse(builderText.contains("return \"Running\""), "Agent progress builder should not return raw lifecycle status strings.")
        XCTAssertFalse(builderText.contains("return \"Failed\""), "Agent progress builder should not return raw lifecycle status strings.")
        XCTAssertFalse(mcpRuntimeText.contains("agentStatus: \"Idle\""), "MCP runtime should not return raw idle status strings.")
        XCTAssertFalse(mcpRuntimeText.contains("agentStatus: \"Failed\""), "MCP runtime should not return raw failed status strings.")
    }

    func testRuntimeStatusLabelsAreSharedByAuthAndIssuePaths() throws {
        let labelsText = try Self.appSourceText(named: "QuillCodeRuntimeStatusLabel.swift")
        let runtimeFactoryText = try Self.appSourceText(named: "RuntimeFactory.swift")
        let issueBuilderText = try Self.appSourceText(named: "WorkspaceRuntimeIssueBuilder.swift")
        let desktopControllerText = try Self.desktopSourceText(named: "QuillCodeDesktopController.swift")

        XCTAssertTrue(labelsText.contains("public enum QuillCodeRuntimeStatusLabel"), "Runtime/auth status labels should live in one focused label boundary.")
        XCTAssertTrue(runtimeFactoryText.contains("QuillCodeRuntimeStatusLabel.signInWithTrustedRouter"), "RuntimeFactory should use shared sign-in-needed copy.")
        XCTAssertTrue(runtimeFactoryText.contains("QuillCodeRuntimeStatusLabel.developerKeyNeeded"), "RuntimeFactory should use shared developer-key-needed copy.")
        XCTAssertTrue(runtimeFactoryText.contains("QuillCodeRuntimeStatusLabel.trustedRouterReady"), "RuntimeFactory should use shared TrustedRouter-ready copy.")
        XCTAssertTrue(issueBuilderText.contains("case QuillCodeRuntimeStatusLabel.signInWithTrustedRouter"), "Runtime issue builder should branch on shared sign-in-needed copy.")
        XCTAssertTrue(issueBuilderText.contains("case QuillCodeRuntimeStatusLabel.developerKeyNeeded"), "Runtime issue builder should branch on shared developer-key-needed copy.")
        XCTAssertTrue(desktopControllerText.contains("QuillCodeRuntimeStatusLabel.signInFailed"), "Desktop sign-in failure should use shared runtime status copy.")
        XCTAssertFalse(runtimeFactoryText.contains("status: \"Mock LLM\""), "RuntimeFactory should not emit raw mock status copy.")
        XCTAssertFalse(runtimeFactoryText.contains("status: \"Sign in with TrustedRouter\""), "RuntimeFactory should not emit raw sign-in-needed status copy.")
        XCTAssertFalse(runtimeFactoryText.contains("status: \"Developer key needed\""), "RuntimeFactory should not emit raw developer-key-needed status copy.")
        XCTAssertFalse(issueBuilderText.contains("case \"Sign in with TrustedRouter\""), "Runtime issue builder should not branch on raw sign-in-needed copy.")
        XCTAssertFalse(issueBuilderText.contains("case \"Developer key needed\""), "Runtime issue builder should not branch on raw developer-key-needed copy.")
        XCTAssertFalse(desktopControllerText.contains("setAgentStatus(\"Sign-in failed\""), "Desktop controller should not emit raw sign-in-failed status copy.")
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
        XCTAssertTrue(modelText.contains("WorkspaceProjectMetadataLoader.loadRemote"), "WorkspaceModel should delegate SSH Remote project metadata loading.")
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

        XCTAssertTrue(projectIntegrationTests.contains("testProjectInstructionsLoadIntoNewThreadsAndRefreshBeforeRun"), "Project instruction integration should live in focused project tests.")
        XCTAssertFalse(modelTests.contains("testProjectInstructionsLoadIntoNewThreadsAndRefreshBeforeRun"), "WorkspaceModelTests should not own project instruction integration flows.")
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
        let sidebarText = try Self.appSourceText(named: "QuillCodeSidebarView.swift")
        let htmlSidebarText = try Self.appSourceText(named: "WorkspaceHTMLSidebarRenderer.swift")

        XCTAssertTrue(presentationText.contains("struct QuillCodeSidebarCommandPresentation"), "Sidebar command labels and icons should live in one focused presentation helper.")
        XCTAssertTrue(presentationText.contains("static let primaryCommandIDs"), "Primary sidebar command order should be explicit.")
        XCTAssertTrue(presentationText.contains("static let utilityCommandIDs"), "Utility sidebar command order should be explicit.")
        XCTAssertTrue(presentationText.contains("static func displayTitle"), "Sidebar command display titles should be shared.")
        XCTAssertTrue(presentationText.contains("static func systemImage"), "Native sidebar command icons should be shared.")
        XCTAssertTrue(presentationText.contains("static func htmlIconToken"), "HTML sidebar icon tokens should be shared.")
        XCTAssertTrue(sidebarText.contains("QuillCodeSidebarCommandPresentation.primaryCommandIDs"), "Native sidebar should consume shared primary command ordering.")
        XCTAssertTrue(sidebarText.contains("QuillCodeSidebarCommandPresentation.utilityCommandIDs"), "Native sidebar should consume shared utility command ordering.")
        XCTAssertTrue(sidebarText.contains("QuillCodeSidebarCommandPresentation.displayTitle"), "Native sidebar should consume shared labels.")
        XCTAssertTrue(sidebarText.contains("QuillCodeSidebarCommandPresentation.systemImage"), "Native sidebar should consume shared SF Symbols.")
        XCTAssertTrue(htmlSidebarText.contains("renderPrimaryActions"), "HTML sidebar renderer should build primary sidebar actions through a helper.")
        XCTAssertTrue(htmlSidebarText.contains("renderUtilityActions"), "HTML sidebar renderer should build utility menu actions through a helper.")
        XCTAssertTrue(htmlSidebarText.contains("QuillCodeSidebarCommandPresentation.primaryCommandIDs"), "HTML sidebar renderer should consume shared primary command ordering.")
        XCTAssertTrue(htmlSidebarText.contains("QuillCodeSidebarCommandPresentation.utilityCommandIDs"), "HTML sidebar renderer should consume shared utility command ordering.")
        XCTAssertTrue(htmlSidebarText.contains("QuillCodeSidebarCommandPresentation.htmlIconToken"), "HTML sidebar renderer should consume shared icon tokens.")
        XCTAssertFalse(sidebarText.contains("private func displayTitle"), "Native sidebar should not maintain a second label map.")
        XCTAssertFalse(sidebarText.contains("private func systemImage"), "Native sidebar should not maintain a second icon map.")
        XCTAssertFalse(htmlSidebarText.contains(#"data-icon="plugins">Plugins"#), "HTML sidebar renderer should not hard-code sidebar plugin markup.")
    }

    func testWorkspaceSwiftUIViewDelegatesTranscriptFindAndContextBanner() throws {
        let shellText = try Self.appSourceText(named: "WorkspaceSwiftUIView.swift")
        let transcriptText = try Self.appSourceText(named: "QuillCodeTranscriptView.swift")
        let findText = try Self.appSourceText(named: "QuillCodeTranscriptFindView.swift")
        let contextBannerText = try Self.appSourceText(named: "QuillCodeContextBannerView.swift")

        XCTAssertTrue(transcriptText.contains("struct QuillCodeTranscriptView"), "Transcript layout should live in a focused view file.")
        XCTAssertTrue(transcriptText.contains("QuillCodeTranscriptFindBar"), "Transcript layout should compose the focused Find bar.")
        XCTAssertTrue(transcriptText.contains("QuillCodeContextBannerView"), "Transcript layout should compose the focused context banner.")
        XCTAssertTrue(transcriptText.contains("QuillCodeRuntimeIssueView"), "Transcript layout should own runtime issue placement.")
        XCTAssertTrue(transcriptText.contains("QuillCodeReviewPaneView"), "Transcript layout should own review placement.")
        XCTAssertTrue(transcriptText.contains("QuillCodeToolCardView"), "Transcript layout should own tool-card timeline placement.")
        XCTAssertTrue(findText.contains("struct QuillCodeTranscriptFindMatch"), "Transcript Find matching should live in a focused Find file.")
        XCTAssertTrue(findText.contains("struct QuillCodeTranscriptFindBar"), "Transcript Find bar should live in a focused Find file.")
        XCTAssertTrue(contextBannerText.contains("struct QuillCodeContextBannerView"), "Context banner rendering should live in a focused banner file.")
        XCTAssertTrue(shellText.contains("QuillCodeTranscriptView"), "Workspace shell should compose the extracted transcript view.")
        XCTAssertFalse(shellText.contains("struct QuillCodeTranscriptView"), "Workspace shell should not own transcript layout.")
        XCTAssertFalse(shellText.contains("struct QuillCodeTranscriptFindMatch"), "Workspace shell should not own transcript Find matching.")
        XCTAssertFalse(shellText.contains("struct QuillCodeTranscriptFindBar"), "Workspace shell should not own transcript Find UI.")
        XCTAssertFalse(shellText.contains("struct QuillCodeContextBannerView"), "Workspace shell should not own context banner UI.")
        XCTAssertFalse(shellText.contains("QuillCodeRuntimeIssueView"), "Workspace shell should not own runtime issue transcript placement.")
        XCTAssertFalse(shellText.contains("QuillCodeReviewPaneView"), "Workspace shell should not own review transcript placement.")
        XCTAssertFalse(shellText.contains("QuillCodeToolCardView"), "Workspace shell should not own tool-card timeline placement.")
    }

    func testWorkspaceSwiftUIViewDelegatesSheetPresentation() throws {
        let shellText = try Self.appSourceText(named: "WorkspaceSwiftUIView.swift")
        let sheetsText = try Self.appSourceText(named: "QuillCodeWorkspaceSheets.swift")

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
        XCTAssertTrue(shellText.contains(".quillCodeWorkspaceSheets("), "Workspace shell should compose the extracted sheet presenter.")
        XCTAssertFalse(shellText.contains("QuillCodeSettingsView("), "Workspace shell should not own settings sheet wiring.")
        XCTAssertFalse(shellText.contains("QuillCodeSearchView("), "Workspace shell should not own search sheet wiring.")
        XCTAssertFalse(shellText.contains("QuillCodeCommandPaletteView("), "Workspace shell should not own command palette sheet wiring.")
        XCTAssertFalse(shellText.contains("QuillCodeWorktreeCreateView("), "Workspace shell should not own worktree create sheet wiring.")
        XCTAssertFalse(shellText.contains("QuillCodeThreadRenameView("), "Workspace shell should not own thread rename sheet wiring.")
        XCTAssertFalse(shellText.contains(".sheet(isPresented:"), "Workspace shell should not own sheet presentation modifiers.")
        XCTAssertFalse(shellText.contains(".sheet(item:"), "Workspace shell should not own item sheet presentation modifiers.")
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
        let plannerText = try Self.appSourceText(named: "QuillCodeRuntimeIssueRecoveryPlanner.swift")

        XCTAssertTrue(plannerText.contains("struct RuntimeIssueRecoveryPlanner"), "Runtime issue recovery routing should live in a focused planner.")
        XCTAssertTrue(plannerText.contains("enum RuntimeIssueRecoveryAction"), "Recovery actions should be explicit instead of view-local closures.")
        XCTAssertTrue(plannerText.contains("case \"Open Settings\", \"Add key\", \"Fix key\""), "Settings recovery labels should be directly testable.")
        XCTAssertTrue(plannerText.contains("case \"Retry\""), "Retry recovery routing should be directly testable.")
        XCTAssertTrue(plannerText.contains("case \"Switch model\""), "Model-switch recovery routing should be directly testable.")
        XCTAssertTrue(viewText.contains("RuntimeIssueRecoveryPlanner(commands:"), "WorkspaceSwiftUIView should delegate runtime issue recovery planning.")
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

    func testWorkspaceSurfaceDelegatesModelCatalogBuilding() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceModelCatalogSurfaceBuilder.swift")

        XCTAssertTrue(builderText.contains("struct WorkspaceModelCatalogSurfaceBuilder"), "Model picker category construction should live in a focused builder.")
        XCTAssertTrue(builderText.contains("func modelLabel()"), "Model picker label formatting should be directly testable.")
        XCTAssertTrue(builderText.contains("func categories()"), "Model picker category construction should be directly testable.")
        XCTAssertTrue(builderText.contains("normalizedUniqueModelIDs"), "Model picker builder should normalize favorites and recents defensively.")
        XCTAssertTrue(surfaceText.contains("WorkspaceModelCatalogSurfaceBuilder("), "WorkspaceSurface should delegate model catalog presentation construction.")
        XCTAssertFalse(surfaceText.contains("func modelCategories(selectedModelID:"), "WorkspaceSurface should not own model category construction.")
        XCTAssertFalse(surfaceText.contains("func modelOption("), "WorkspaceSurface should not own model option badge construction.")
        XCTAssertFalse(surfaceText.contains("func favoriteModelIDs()"), "WorkspaceSurface should not own model favorite normalization.")
        XCTAssertFalse(surfaceText.contains("func recentModelIDs("), "WorkspaceSurface should not own recent model normalization.")
    }

    func testWorkspaceSurfaceDelegatesTopBarSurfaceContracts() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let topBarText = try Self.appSourceText(named: "QuillCodeTopBarSurface.swift")

        XCTAssertTrue(topBarText.contains("public struct TopBarSurface"), "Top-bar aggregate records should live beside top-bar-specific behavior.")
        XCTAssertTrue(topBarText.contains("public struct ModelCategorySurface"), "Model category rows should live beside model picker filtering.")
        XCTAssertTrue(topBarText.contains("public struct ModelMetadataRowSurface"), "Model metadata rows should live beside model option compatibility behavior.")
        XCTAssertTrue(topBarText.contains("public struct ModelOptionSurface"), "Model option records should live beside model option metadata construction.")
        XCTAssertTrue(topBarText.contains("filteredModelCategories"), "Model picker filtering should be directly testable outside the aggregate workspace surface.")
        XCTAssertFalse(surfaceText.contains("public struct TopBarSurface"), "WorkspaceSurface should not own top-bar surface records.")
        XCTAssertFalse(surfaceText.contains("public struct ModelCategorySurface"), "WorkspaceSurface should not own model category records.")
        XCTAssertFalse(surfaceText.contains("public struct ModelMetadataRowSurface"), "WorkspaceSurface should not own model metadata rows.")
        XCTAssertFalse(surfaceText.contains("public struct ModelOptionSurface"), "WorkspaceSurface should not own model option records.")
        XCTAssertFalse(surfaceText.contains("filteredModelCategories"), "WorkspaceSurface should not own model picker filtering.")
    }

    func testWorkspaceSurfaceDelegatesSidebarSurfaceContracts() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let sidebarText = try Self.appSourceText(named: "QuillCodeSidebarSurface.swift")

        XCTAssertTrue(sidebarText.contains("public struct ProjectListSurface"), "Project list records should live beside sidebar contracts.")
        XCTAssertTrue(sidebarText.contains("public struct ProjectItemSurface"), "Project rows should live beside sidebar contracts.")
        XCTAssertTrue(sidebarText.contains("public enum ProjectItemActionKind"), "Project action labels should live beside sidebar contracts.")
        XCTAssertTrue(sidebarText.contains("public struct ProjectItemActionSurface"), "Project action records should live beside sidebar contracts.")
        XCTAssertTrue(sidebarText.contains("public struct SidebarSurface"), "Sidebar aggregate records should live beside sidebar contracts.")
        XCTAssertTrue(sidebarText.contains("public struct SidebarItemSurface"), "Sidebar item rows should live beside sidebar contracts.")
        XCTAssertTrue(sidebarText.contains("public enum SidebarBulkActionKind"), "Bulk action labels should live beside sidebar contracts.")
        XCTAssertTrue(sidebarText.contains("public struct SidebarBulkActionSurface"), "Bulk action command IDs should live beside sidebar contracts.")
        XCTAssertTrue(sidebarText.contains("public enum SidebarItemActionKind"), "Thread action labels should live beside sidebar contracts.")
        XCTAssertTrue(sidebarText.contains("public struct SidebarItemActionSurface"), "Thread action records should live beside sidebar contracts.")
        XCTAssertTrue(sidebarText.contains("filteredItems"), "Sidebar search filtering should be directly testable outside the aggregate workspace surface.")
        XCTAssertTrue(sidebarText.contains("selectionLabel"), "Sidebar selection copy should be directly testable outside the aggregate workspace surface.")
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
    }

    func testWorkspaceSurfaceDelegatesCommandSurfaceBuilding() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceCommandSurfaceBuilder.swift")

        XCTAssertTrue(builderText.contains("struct WorkspaceCommandSurfaceBuilder"), "Command palette construction should live in a focused builder.")
        XCTAssertTrue(builderText.contains("var commands: [WorkspaceCommandSurface]"), "Command builder should expose directly testable command rows.")
        XCTAssertTrue(builderText.contains("private var localActionCommands"), "Local environment action command construction should be isolated in the builder.")
        XCTAssertTrue(builderText.contains("private var mcpLifecycleCommands"), "MCP lifecycle command construction should be isolated in the builder.")
        XCTAssertTrue(builderText.contains("private var gitCommands"), "Git command construction should be isolated in the builder.")
        XCTAssertTrue(surfaceText.contains("WorkspaceCommandSurfaceBuilder("), "WorkspaceSurface should delegate command construction.")
        XCTAssertFalse(surfaceText.contains("private func commands() -> [WorkspaceCommandSurface]"), "WorkspaceSurface should not own the command catalog.")
        XCTAssertFalse(surfaceText.contains("let localActionCommands ="), "WorkspaceSurface should not own local-action command construction.")
        XCTAssertFalse(surfaceText.contains("let mcpLifecycleCommands ="), "WorkspaceSurface should not own MCP lifecycle command construction.")
        XCTAssertFalse(surfaceText.contains("let extensionUpdateCommands ="), "WorkspaceSurface should not own extension update command construction.")
    }

    func testWorkspaceSurfaceDelegatesCommandPaletteContract() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let paletteText = try Self.appSourceText(named: "WorkspaceCommandPaletteSurface.swift")

        XCTAssertTrue(paletteText.contains("public struct WorkspaceCommandSurface"), "Command surface records should live beside palette ranking.")
        XCTAssertTrue(paletteText.contains("public enum TopBarOverflowCommandCatalog"), "Top-bar overflow command projection should live beside command surfaces.")
        XCTAssertTrue(paletteText.contains("public enum WorkspaceCommandPalette"), "Palette grouping and ranking should live in a focused command surface file.")
        XCTAssertTrue(paletteText.contains("private static func score"), "Palette scoring should be directly guarded outside the aggregate surface file.")
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

        XCTAssertTrue(secondaryText.contains("public struct WorkspaceExtensionsSurface"), "Extensions surface should live beside secondary-pane contracts.")
        XCTAssertTrue(secondaryText.contains("public struct WorkspaceMemoriesSurface"), "Memories surface should live beside secondary-pane contracts.")
        XCTAssertTrue(secondaryText.contains("public struct WorkspaceAutomationsSurface"), "Automations surface should live beside secondary-pane contracts.")
        XCTAssertTrue(secondaryText.contains("public struct ProjectExtensionManifestSurface"), "Extension manifest rows should live beside secondary-pane contracts.")
        XCTAssertTrue(secondaryText.contains("public struct MemoryNoteSurface"), "Memory note rows should live beside secondary-pane contracts.")
        XCTAssertTrue(secondaryText.contains("public struct AutomationWorkflowSurface"), "Automation workflow rows should live beside secondary-pane contracts.")
        XCTAssertTrue(secondaryText.contains("MCPToolDescriptor"), "MCP probe display compatibility should stay with extension surface rows.")
        XCTAssertFalse(surfaceText.contains("public struct WorkspaceExtensionsSurface"), "WorkspaceSurface should not own Extensions surface records.")
        XCTAssertFalse(surfaceText.contains("public struct WorkspaceMemoriesSurface"), "WorkspaceSurface should not own Memories surface records.")
        XCTAssertFalse(surfaceText.contains("public struct WorkspaceAutomationsSurface"), "WorkspaceSurface should not own Automations surface records.")
        XCTAssertFalse(surfaceText.contains("public struct ProjectExtensionManifestSurface"), "WorkspaceSurface should not own extension manifest rows.")
        XCTAssertFalse(surfaceText.contains("public struct MemoryNoteSurface"), "WorkspaceSurface should not own memory note rows.")
        XCTAssertFalse(surfaceText.contains("public struct AutomationWorkflowSurface"), "WorkspaceSurface should not own automation workflow rows.")
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

        XCTAssertTrue(plannerText.contains("enum WorkspaceReviewActionToolCallPlanner"), "Review action tool-call planning should live in a focused planner.")
        XCTAssertTrue(plannerText.contains("static func toolCall"), "Review action tool-call planning should be directly testable.")
        XCTAssertTrue(plannerText.contains("ToolDefinition.gitStage.name"), "File stage calls should live in the planner.")
        XCTAssertTrue(plannerText.contains("ToolDefinition.gitRestore.name"), "File restore calls should live in the planner.")
        XCTAssertTrue(plannerText.contains("ToolDefinition.gitStageHunk.name"), "Hunk stage calls should live in the planner.")
        XCTAssertTrue(plannerText.contains("ToolDefinition.gitRestoreHunk.name"), "Hunk restore calls should live in the planner.")
        XCTAssertTrue(modelText.contains("WorkspaceReviewActionToolCallPlanner.toolCall"), "WorkspaceModel should delegate review action tool-call construction.")
        XCTAssertFalse(modelText.contains("private extension WorkspaceReviewActionSurface"), "WorkspaceModel should not own review action surface extensions.")
        XCTAssertFalse(modelText.contains("var toolCall: ToolCall"), "WorkspaceModel should not own review action tool-call mapping.")
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

    func testToolArgumentJSONSerializationLivesInCore() throws {
        let argumentsText = try Self.coreSourceText(named: "Arguments.swift")
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let slashText = try Self.appSourceText(named: "SlashCommand.swift")
        let shellPlannerText = try Self.appSourceText(named: "WorkspaceShellToolCallPlanner.swift")
        let worktreePlannerText = try Self.appSourceText(named: "WorkspaceWorktreeToolCallPlanner.swift")
        let reviewPlannerText = try Self.appSourceText(named: "WorkspaceReviewActionToolCallPlanner.swift")

        XCTAssertTrue(
            argumentsText.contains("public static func json(_ values: [String: Any])"),
            "Mixed tool argument JSON serialization should live in QuillCodeCore."
        )
        XCTAssertTrue(
            slashText.contains("ToolArguments.json("),
            "SlashCommand should use the shared core tool-argument serializer."
        )
        XCTAssertTrue(
            shellPlannerText.contains("ToolArguments.json("),
            "Shell tool-call planners should use the shared core tool-argument serializer."
        )
        XCTAssertTrue(
            worktreePlannerText.contains("ToolArguments.json("),
            "Worktree tool-call planners should use the shared core tool-argument serializer."
        )
        XCTAssertTrue(
            reviewPlannerText.contains("ToolArguments.json("),
            "Review action tool-call planners should use the shared core tool-argument serializer."
        )
        XCTAssertFalse(
            modelText.contains("private func toolArgumentsJSON"),
            "WorkspaceModel should not own ad hoc JSON serialization."
        )
        XCTAssertFalse(
            modelText.contains("JSONSerialization"),
            "WorkspaceModel should not own JSON serialization."
        )
        XCTAssertFalse(
            slashText.contains("private static func json(_ values: [String: Any])"),
            "SlashCommand should not own ad hoc JSON serialization."
        )
    }

    func testWorkspaceModelDelegatesRemoteProjectToolExecution() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceAgentRunContextBuilder.swift")
        let executorText = try Self.appSourceText(named: "WorkspaceRemoteProjectToolExecutor.swift")
        let gitPlannerText = try Self.appSourceText(named: "WorkspaceRemoteGitToolRequestPlanner.swift")
        let basicBuilderText = try Self.appSourceText(named: "WorkspaceRemoteGitBasicCommandBuilder.swift")
        let hunkBuilderText = try Self.appSourceText(named: "WorkspaceRemoteGitHunkCommandBuilder.swift")
        let pushBuilderText = try Self.appSourceText(named: "WorkspaceRemoteGitPushCommandBuilder.swift")
        let pullRequestBuilderText = try Self.appSourceText(named: "WorkspaceRemoteGitHubPullRequestCommandBuilder.swift")
        let worktreeBuilderText = try Self.appSourceText(named: "WorkspaceRemoteGitWorktreeCommandBuilder.swift")
        let remotePathText = try Self.appSourceText(named: "WorkspaceRemoteProjectPath.swift")

        XCTAssertTrue(executorText.contains("struct WorkspaceRemoteProjectToolExecutor"), "SSH Remote project tools should live in a focused executor.")
        XCTAssertTrue(executorText.contains("static let toolDefinitions"), "Remote project tool definitions should live beside remote execution.")
        XCTAssertTrue(executorText.contains("static let gitToolNames"), "Remote git routing should live beside remote execution.")
        XCTAssertTrue(executorText.contains("static func executionOverride"), "Remote agent override construction should be directly testable.")
        XCTAssertTrue(executorText.contains("static func execute"), "Manual remote tool execution should be directly testable.")
        XCTAssertTrue(gitPlannerText.contains("struct WorkspaceRemoteGitToolRequest"), "Remote git command planning should return a typed request contract.")
        XCTAssertTrue(gitPlannerText.contains("enum WorkspaceRemoteGitToolRequestPlanner"), "Remote git command planning should live in a pure planner.")
        XCTAssertTrue(basicBuilderText.contains("enum WorkspaceRemoteGitBasicCommandBuilder"), "Remote basic git command construction should live in a focused builder.")
        XCTAssertTrue(basicBuilderText.contains("WorkspaceRemoteProjectPath.relativePath"), "Remote basic git commands should reuse remote path validation.")
        XCTAssertTrue(basicBuilderText.contains("GitToolError.emptyCommitMessage"), "Remote basic git commands should preserve commit-message validation.")
        XCTAssertTrue(hunkBuilderText.contains("enum WorkspaceRemoteGitHunkCommandBuilder"), "Remote git hunk command construction should live in a focused builder.")
        XCTAssertTrue(hunkBuilderText.contains("GitPatchToolExecutor.mismatchedPatchPath"), "Remote hunk command construction should reuse shared patch path validation.")
        XCTAssertTrue(pushBuilderText.contains("enum WorkspaceRemoteGitPushCommandBuilder"), "Remote git push command construction should live in a focused builder.")
        XCTAssertTrue(pushBuilderText.contains("GitInputValidator.safeName"), "Remote git push command construction should reuse shared git input validation.")
        XCTAssertTrue(pullRequestBuilderText.contains("enum WorkspaceRemoteGitHubPullRequestCommandBuilder"), "Remote GitHub PR command construction should live in a focused builder.")
        XCTAssertTrue(pullRequestBuilderText.contains("GitHubPullRequestInputValidator.safeSelector"), "Remote GitHub PR command construction should reuse local PR input validation.")
        XCTAssertTrue(worktreeBuilderText.contains("enum WorkspaceRemoteGitWorktreeCommandBuilder"), "Remote git worktree command construction should live in a focused builder.")
        XCTAssertTrue(worktreeBuilderText.contains("WorkspaceRemoteProjectPath.worktreePath"), "Remote worktree command construction should reuse remote path normalization.")
        XCTAssertTrue(remotePathText.contains("enum WorkspaceRemoteProjectPath"), "Remote path normalization should live in a focused helper.")
        XCTAssertTrue(executorText.contains("WorkspaceRemoteGitToolRequestPlanner.request"), "Remote executor should delegate git command planning.")
        XCTAssertTrue(gitPlannerText.contains("WorkspaceRemoteGitBasicCommandBuilder.command"), "Remote git planning should delegate basic command construction.")
        XCTAssertTrue(gitPlannerText.contains("WorkspaceRemoteGitHunkCommandBuilder.command"), "Remote git planning should delegate hunk command construction.")
        XCTAssertTrue(gitPlannerText.contains("WorkspaceRemoteGitPushCommandBuilder.command"), "Remote git planning should delegate push command construction.")
        XCTAssertTrue(gitPlannerText.contains("WorkspaceRemoteGitHubPullRequestCommandBuilder.command"), "Remote git planning should delegate PR command construction.")
        XCTAssertTrue(gitPlannerText.contains("WorkspaceRemoteGitWorktreeCommandBuilder.plan"), "Remote git planning should delegate worktree command construction.")
        XCTAssertTrue(executorText.contains("WorkspaceRemoteProjectPath.relativePath"), "Remote executor should delegate file path normalization.")
        XCTAssertTrue(builderText.contains("WorkspaceRemoteProjectToolExecutor.toolDefinitions"), "Agent run context builder should delegate remote base tool definitions.")
        XCTAssertTrue(builderText.contains("WorkspaceRemoteProjectToolExecutor.executionOverride"), "Agent run context builder should delegate remote override creation.")
        XCTAssertTrue(modelText.contains("workspaceToolCallExecutor(router:"), "WorkspaceModel should delegate manual/review tool execution through the shared workspace executor.")
        XCTAssertTrue(try Self.appSourceText(named: "WorkspaceToolCallExecutor.swift").contains("WorkspaceRemoteProjectToolExecutor.execute"), "WorkspaceToolCallExecutor should own remote project routing.")
        XCTAssertFalse(modelText.contains("WorkspaceRemoteProjectToolExecutor.toolDefinitions"), "WorkspaceModel should not choose remote base tool definitions inline.")
        XCTAssertFalse(modelText.contains("WorkspaceRemoteProjectToolExecutor.executionOverride"), "WorkspaceModel should not create remote agent overrides inline.")
        XCTAssertFalse(executorText.contains("private static func remoteGitPullRequestCommand"), "Remote executor should not own GitHub CLI command construction.")
        XCTAssertFalse(gitPlannerText.contains("git status --short --branch"), "Generic remote git planning should not own basic git command strings.")
        XCTAssertFalse(gitPlannerText.contains("git add --"), "Generic remote git planning should not own git stage command construction.")
        XCTAssertFalse(gitPlannerText.contains("git commit -m"), "Generic remote git planning should not own git commit command construction.")
        XCTAssertFalse(gitPlannerText.contains("private static func remoteGitPullRequest"), "Generic remote git planning should not own GitHub CLI command construction.")
        XCTAssertFalse(gitPlannerText.contains(#"["gh", "pr""#), "Generic remote git planning should not assemble gh pr arguments inline.")
        XCTAssertFalse(executorText.contains("private static func remoteGitWorktreePath"), "Remote executor should not own worktree path normalization.")
        XCTAssertFalse(gitPlannerText.contains("private static func remoteGitHunk"), "Generic remote git planning should not own hunk patch transport construction.")
        XCTAssertFalse(gitPlannerText.contains("quillcode-hunk"), "Generic remote git planning should not own hunk patch temp-file details.")
        XCTAssertFalse(gitPlannerText.contains("private static func remoteGitPush"), "Generic remote git planning should not own push command construction.")
        XCTAssertFalse(gitPlannerText.contains("branch=$(git branch --show-current)"), "Generic remote git planning should not own current-branch push guards.")
        XCTAssertFalse(gitPlannerText.contains("private static func remoteGitWorktree"), "Generic remote git planning should not own worktree command construction.")
        XCTAssertFalse(gitPlannerText.contains(#"["git", "worktree""#), "Generic remote git planning should not assemble git worktree arguments inline.")
        XCTAssertFalse(modelText.contains("executeRemoteGitToolCall"), "WorkspaceModel should not own remote git command execution.")
        XCTAssertFalse(modelText.contains("executeRemoteShellToolCall"), "WorkspaceModel should not own remote shell command execution.")
        XCTAssertFalse(modelText.contains("remoteProjectGitToolNames"), "WorkspaceModel should not own remote git tool routing.")
        XCTAssertFalse(modelText.contains("remoteProjectRelativePath"), "WorkspaceModel should not own remote path normalization.")
    }

    func testGitToolDefinitionsLiveOutsideGitExecutor() throws {
        let executorText = try Self.toolsSourceText(named: "GitToolExecutor.swift")
        let definitionsText = try Self.toolsSourceText(named: "GitToolDefinitions.swift")

        XCTAssertTrue(definitionsText.contains("public extension ToolDefinition"), "Git tool schema should live in the definitions catalog.")
        XCTAssertTrue(definitionsText.contains("static let gitStatus"), "Git command definitions should remain available from the catalog.")
        XCTAssertTrue(definitionsText.contains("static let gitPullRequestMerge"), "GitHub PR definitions should remain available from the catalog.")
        XCTAssertTrue(definitionsText.contains("static let gitWorktreeRemove"), "Worktree definitions should remain available from the catalog.")
        XCTAssertFalse(executorText.contains("public extension ToolDefinition"), "GitToolExecutor should not own tool schema declarations.")
        XCTAssertFalse(executorText.contains("parametersJSON"), "GitToolExecutor should not own JSON schema strings.")
    }

    func testToolRouterDelegatesGitToolCallDispatch() throws {
        let routerText = try Self.toolsSourceText(named: "ToolRouter.swift")
        let dispatcherText = try Self.toolsSourceText(named: "GitToolCallDispatcher.swift")

        XCTAssertTrue(dispatcherText.contains("struct GitToolCallDispatcher"), "Git tool call routing should live in a focused dispatcher.")
        XCTAssertTrue(dispatcherText.contains("static let definitions"), "The git dispatcher should own the git tool definition list.")
        XCTAssertTrue(dispatcherText.contains("func execute("), "The git dispatcher should expose a directly testable execution boundary.")
        XCTAssertTrue(routerText.contains("GitToolCallDispatcher.definitions"), "ToolRouter should compose git definitions from the dispatcher.")
        XCTAssertTrue(routerText.contains("GitToolCallDispatcher.handles"), "ToolRouter should delegate git tool dispatch.")
        XCTAssertFalse(routerText.contains("ToolDefinition.gitStatus.name"), "ToolRouter should not own local git route branches.")
        XCTAssertFalse(routerText.contains("ToolDefinition.gitPullRequestCreate.name"), "ToolRouter should not own GitHub PR route branches.")
        XCTAssertFalse(routerText.contains("ToolDefinition.gitWorktreeCreate.name"), "ToolRouter should not own worktree route branches.")
        XCTAssertFalse(routerText.contains("git.createPullRequest"), "ToolRouter should not call GitHub PR execution directly.")
        XCTAssertFalse(routerText.contains("git.createWorktree"), "ToolRouter should not call worktree execution directly.")
    }

    func testToolRouterDelegatesShellToolCallDispatch() throws {
        let routerText = try Self.toolsSourceText(named: "ToolRouter.swift")
        let dispatcherText = try Self.toolsSourceText(named: "ShellToolCallDispatcher.swift")

        XCTAssertTrue(dispatcherText.contains("struct ShellToolCallDispatcher"), "Shell tool call routing should live in a focused dispatcher.")
        XCTAssertTrue(dispatcherText.contains("static let definitions"), "The shell dispatcher should own the shell tool definition list.")
        XCTAssertTrue(dispatcherText.contains("EnvironmentOverridePolicy.validateOverrides"), "The shell dispatcher should own shell environment override validation.")
        XCTAssertTrue(dispatcherText.contains("func execute("), "The shell dispatcher should expose a directly testable execution boundary.")
        XCTAssertTrue(routerText.contains("ShellToolCallDispatcher.definitions"), "ToolRouter should compose shell definitions from the dispatcher.")
        XCTAssertTrue(routerText.contains("ShellToolCallDispatcher.handles"), "ToolRouter should delegate shell tool dispatch.")
        XCTAssertFalse(routerText.contains("ToolDefinition.shellRun.name"), "ToolRouter should not own shell route branches.")
        XCTAssertFalse(routerText.contains("EnvironmentOverridePolicy.validateOverrides"), "ToolRouter should not own shell environment override validation.")
        XCTAssertFalse(routerText.contains("Shell cwd must stay inside the current workspace."), "ToolRouter should not own shell cwd validation copy.")
        XCTAssertFalse(routerText.contains("Shell timeoutSeconds must be between"), "ToolRouter should not own shell timeout validation copy.")
    }

    func testGitLocalExecutionLivesOutsideGitExecutor() throws {
        let executorText = try Self.toolsSourceText(named: "GitToolExecutor.swift")
        let localText = try Self.toolsSourceText(named: "GitLocalToolExecutor.swift")

        XCTAssertTrue(localText.contains("public struct GitLocalToolExecutor"), "Local git execution should live in a focused executor.")
        XCTAssertTrue(localText.contains("func status("), "Local git status should be directly testable.")
        XCTAssertTrue(localText.contains("func diff("), "Local git diff should be directly testable.")
        XCTAssertTrue(localText.contains("func stage("), "Local git stage should be directly testable.")
        XCTAssertTrue(localText.contains("func restore("), "Local git restore should be directly testable.")
        XCTAssertTrue(localText.contains("func commit("), "Local git commit should be directly testable.")
        XCTAssertTrue(localText.contains("func push("), "Local git push should be directly testable.")
        XCTAssertTrue(localText.contains("GitInputValidator.safeRelativePath"), "Local git file actions should use the shared path validator.")
        XCTAssertTrue(executorText.contains("private let local: GitLocalToolExecutor"), "GitToolExecutor should delegate local git work.")
        XCTAssertFalse(executorText.contains(#"["add", "--""#), "GitToolExecutor should not build git add arguments inline.")
        XCTAssertFalse(executorText.contains(#"["restore"]"#), "GitToolExecutor should not build git restore arguments inline.")
        XCTAssertFalse(executorText.contains(#"["commit", "-m""#), "GitToolExecutor should not build git commit arguments inline.")
        XCTAssertFalse(executorText.contains(#"["push"]"#), "GitToolExecutor should not build git push arguments inline.")
        XCTAssertFalse(executorText.contains("currentBranchName"), "GitToolExecutor should not own current-branch lookup.")
    }

    func testGitHubPullRequestExecutionLivesOutsideGitExecutor() throws {
        let executorText = try Self.toolsSourceText(named: "GitToolExecutor.swift")
        let pullRequestText = try Self.toolsSourceText(named: "GitHubPullRequestToolExecutor.swift")
        let inputValidatorText = try Self.toolsSourceText(named: "GitHubPullRequestInputValidator.swift")
        let outputParserText = try Self.toolsSourceText(named: "GitHubPullRequestOutputParser.swift")
        let processRunnerText = try Self.toolsSourceText(named: "GitProcessRunner.swift")

        XCTAssertTrue(pullRequestText.contains("public struct GitHubPullRequestToolExecutor"), "GitHub PR execution should live in a focused executor.")
        XCTAssertTrue(pullRequestText.contains("func createPullRequest"), "GitHub PR creation should be directly testable.")
        XCTAssertTrue(pullRequestText.contains("func merge("), "GitHub PR merge command construction should be directly testable.")
        XCTAssertTrue(inputValidatorText.contains("public enum GitHubPullRequestInputValidator"), "GitHub PR input validation should live in a focused helper.")
        XCTAssertTrue(inputValidatorText.contains("static func safeSelector"), "GitHub PR selector validation should be directly testable.")
        XCTAssertTrue(inputValidatorText.contains("static func safeReviewers"), "GitHub PR reviewer validation should be directly testable.")
        XCTAssertTrue(outputParserText.contains("public enum GitHubPullRequestOutputParser"), "GitHub PR output parsing should live in a focused helper.")
        XCTAssertTrue(outputParserText.contains("static func extractURLs"), "GitHub PR URL extraction should be directly testable.")
        XCTAssertTrue(pullRequestText.contains("GitHubPullRequestInputValidator.safeSelector"), "GitHub PR execution should delegate selector validation.")
        XCTAssertTrue(pullRequestText.contains("GitHubPullRequestOutputParser.extractURLs"), "GitHub PR execution should delegate URL artifact parsing.")
        XCTAssertTrue(processRunnerText.contains("public struct GitProcessRunner"), "Git and GitHub CLI process launching should live in a reusable runner.")
        XCTAssertTrue(processRunnerText.contains("func runGitHub"), "GitHub CLI invocation should be owned by the process runner.")
        XCTAssertTrue(executorText.contains("private let pullRequests: GitHubPullRequestToolExecutor"), "GitToolExecutor should delegate GitHub PR work.")
        XCTAssertFalse(executorText.contains("func runGitHub"), "GitToolExecutor should not own GitHub CLI process launching.")
        XCTAssertFalse(executorText.contains("Process()"), "GitToolExecutor should not own raw process launching.")
        XCTAssertFalse(executorText.contains(#"["pr", "create"]"#), "GitToolExecutor should not build GitHub PR command arguments inline.")
        XCTAssertFalse(executorText.contains("addURLArtifacts"), "GitToolExecutor should not own GitHub PR URL artifact extraction.")
        XCTAssertFalse(pullRequestText.contains("static func safeSelector"), "GitHub PR execution should not own input validation.")
        XCTAssertFalse(pullRequestText.contains("static func extractURLs"), "GitHub PR execution should not own output parsing.")
    }

    func testGitWorktreeExecutionLivesOutsideGitExecutor() throws {
        let executorText = try Self.toolsSourceText(named: "GitToolExecutor.swift")
        let worktreeText = try Self.toolsSourceText(named: "GitWorktreeToolExecutor.swift")

        XCTAssertTrue(worktreeText.contains("public struct GitWorktreeToolExecutor"), "Git worktree execution should live in a focused executor.")
        XCTAssertTrue(worktreeText.contains("func list("), "Git worktree listing should be directly testable.")
        XCTAssertTrue(worktreeText.contains("func create("), "Git worktree creation should be directly testable.")
        XCTAssertTrue(worktreeText.contains("func remove("), "Git worktree removal should be directly testable.")
        XCTAssertTrue(worktreeText.contains("static func safePath"), "Git worktree path validation should live beside worktree execution.")
        XCTAssertTrue(worktreeText.contains("registeredPaths"), "Git worktree registered-path lookup should live beside worktree removal.")
        XCTAssertTrue(executorText.contains("private let worktrees: GitWorktreeToolExecutor"), "GitToolExecutor should delegate git worktree work.")
        XCTAssertFalse(executorText.contains(#"["worktree", "add"]"#), "GitToolExecutor should not build git worktree add arguments inline.")
        XCTAssertFalse(executorText.contains(#"["worktree", "remove"]"#), "GitToolExecutor should not build git worktree remove arguments inline.")
        XCTAssertFalse(executorText.contains("safeWorktreePath"), "GitToolExecutor should not own worktree path validation.")
        XCTAssertFalse(executorText.contains("registeredWorktreePaths"), "GitToolExecutor should not own registered-worktree lookup.")
    }

    func testGitPatchExecutionLivesOutsideGitExecutor() throws {
        let executorText = try Self.toolsSourceText(named: "GitToolExecutor.swift")
        let patchText = try Self.toolsSourceText(named: "GitPatchToolExecutor.swift")
        let remoteGitHunkBuilderText = try Self.appSourceText(named: "WorkspaceRemoteGitHunkCommandBuilder.swift")
        let remoteGitPlannerText = try Self.appSourceText(named: "WorkspaceRemoteGitToolRequestPlanner.swift")

        XCTAssertTrue(patchText.contains("public struct GitPatchToolExecutor"), "Git patch execution should live in a focused executor.")
        XCTAssertTrue(patchText.contains("func stageHunk("), "Git patch staging should be directly testable.")
        XCTAssertTrue(patchText.contains("func restoreHunk("), "Git patch restore should be directly testable.")
        XCTAssertTrue(patchText.contains("static func mismatchedPatchPath"), "Patch path validation should live beside patch execution.")
        XCTAssertTrue(executorText.contains("private let patches: GitPatchToolExecutor"), "GitToolExecutor should delegate hunk patch work.")
        XCTAssertTrue(remoteGitHunkBuilderText.contains("GitPatchToolExecutor.mismatchedPatchPath"), "Remote hunk planning should reuse the focused patch validator.")
        XCTAssertFalse(executorText.contains("private func applyHunk"), "GitToolExecutor should not own patch application.")
        XCTAssertFalse(executorText.contains("mismatchedPatchPath"), "GitToolExecutor should not own patch path validation.")
        XCTAssertFalse(executorText.contains("temporaryPatchFailed"), "GitToolExecutor should not own temporary patch file handling.")
        XCTAssertFalse(executorText.contains("pathsInDiffMetadataLine"), "GitToolExecutor should not own diff metadata parsing.")
        XCTAssertFalse(remoteGitPlannerText.contains("GitPatchToolExecutor.mismatchedPatchPath"), "Generic remote git planning should not own remote hunk patch validation.")
    }

    func testGitSharedInputValidationLivesOutsideGitFacade() throws {
        let executorText = try Self.toolsSourceText(named: "GitToolExecutor.swift")
        let localText = try Self.toolsSourceText(named: "GitLocalToolExecutor.swift")
        let validatorText = try Self.toolsSourceText(named: "GitInputValidator.swift")
        let pullRequestText = try Self.toolsSourceText(named: "GitHubPullRequestToolExecutor.swift")
        let worktreeText = try Self.toolsSourceText(named: "GitWorktreeToolExecutor.swift")
        let remoteGitPlannerText = try Self.appSourceText(named: "WorkspaceRemoteGitToolRequestPlanner.swift")
        let remoteGitPushBuilderText = try Self.appSourceText(named: "WorkspaceRemoteGitPushCommandBuilder.swift")

        XCTAssertTrue(validatorText.contains("public enum GitInputValidator"), "Shared git input validation should live in a neutral helper.")
        XCTAssertTrue(validatorText.contains("static let safeNameCharacters"), "Shared git-name character policy should live in GitInputValidator.")
        XCTAssertTrue(validatorText.contains("static func trimmedNonEmpty"), "Shared trimming should live in GitInputValidator.")
        XCTAssertTrue(validatorText.contains("static func safeName"), "Shared git name validation should live in GitInputValidator.")
        XCTAssertTrue(validatorText.contains("static func safeRelativePath"), "Shared local git path validation should live in GitInputValidator.")
        XCTAssertTrue(localText.contains("GitInputValidator.safeRelativePath"), "Local git execution should use the shared path validator.")
        XCTAssertTrue(pullRequestText.contains("GitInputValidator.safeName"), "GitHub PR execution should use the shared git-name validator.")
        XCTAssertTrue(worktreeText.contains("GitInputValidator.safeName"), "Worktree execution should use the shared git-name validator.")
        XCTAssertTrue(remoteGitPushBuilderText.contains("GitInputValidator.safeName"), "Remote git push planning should use the shared git-name validator.")
        XCTAssertTrue(remoteGitPushBuilderText.contains("GitInputValidator.safeNameCharacters"), "Remote git current-branch shell guards should use the shared git-name character policy.")
        XCTAssertFalse(executorText.contains("GitInputValidator.safeRelativePath"), "GitToolExecutor should not own local path validation.")
        XCTAssertFalse(pullRequestText.contains("GitToolExecutor.safeGitName"), "GitHub PR execution should not depend on the git facade for validation.")
        XCTAssertFalse(pullRequestText.contains("GitToolExecutor.trimmedNonEmpty"), "GitHub PR execution should not depend on the git facade for trimming.")
        XCTAssertFalse(worktreeText.contains("GitToolExecutor.safeGitName"), "Worktree execution should not depend on the git facade for validation.")
        XCTAssertFalse(worktreeText.contains("GitToolExecutor.trimmedNonEmpty"), "Worktree execution should not depend on the git facade for trimming.")
        XCTAssertFalse(remoteGitPlannerText.contains("GitToolExecutor.safeGitName"), "Remote git planning should not depend on the git facade for validation.")
        XCTAssertFalse(remoteGitPlannerText.contains("GitToolExecutor.trimmedNonEmpty"), "Remote git planning should not depend on the git facade for trimming.")
        XCTAssertFalse(remoteGitPlannerText.contains("GitInputValidator.safeName"), "Generic remote git planning should not own git-name validation.")
    }

    func testWorkspaceSurfaceDelegatesContextBannerBuilding() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceContextBannerBuilder.swift")

        XCTAssertTrue(builderText.contains("struct WorkspaceContextBannerBuilder"), "Context banner construction should live in a focused builder.")
        XCTAssertTrue(builderText.contains("func banner() -> ContextBannerSurface?"), "Context banner construction should be directly testable.")
        XCTAssertTrue(builderText.contains("estimatedContextTokens"), "Context estimation should be directly testable.")
        XCTAssertTrue(surfaceText.contains("WorkspaceContextBannerBuilder("), "WorkspaceSurface should delegate context banner construction.")
        XCTAssertFalse(surfaceText.contains("private func contextBanner("), "WorkspaceSurface should not own context banner construction.")
        XCTAssertFalse(surfaceText.contains("contextUsedPercent"), "WorkspaceSurface should not own context usage calculation.")
        XCTAssertFalse(surfaceText.contains("estimatedContextTokens"), "WorkspaceSurface should not own context token estimation.")
    }

    func testDesktopDefinesNativeMenuBarWidget() throws {
        let text = try Self.desktopSourceText()

        XCTAssertTrue(text.contains("MenuBarExtra"), "Desktop app should define a native menu-bar widget.")
        XCTAssertTrue(text.contains(#"systemImage: "q.circle.fill""#), "Menu-bar widget should use a visible QuillCode symbol.")
        for label in ["New Chat", "Open Project", "Command Palette", "Keyboard Shortcuts", "Computer Use Setup", "Settings", "Stop All", "Disconnect All"] {
            XCTAssertTrue(text.contains(label), "Menu-bar widget is missing \(label).")
        }
    }

    func testDesktopTrustedRouterSignInUsesLoopbackOAuth() throws {
        let text = try Self.desktopSourceText()
        let controllerText = try Self.desktopSourceText(named: "QuillCodeDesktopController.swift")

        XCTAssertTrue(text.contains("QuillCodeDesktopSignInCoordinator"), "Desktop sign-in should be isolated from UI routing.")
        XCTAssertTrue(text.contains("TrustedRouterLoopbackCallbackServer"), "Desktop sign-in should own a loopback callback server.")
        XCTAssertTrue(text.contains("TrustedRouterDefaults.loopbackCallbackURL"), "Desktop sign-in should use the shared TrustedRouter loopback callback URL.")
        XCTAssertTrue(text.contains("createAuthorization"), "Desktop sign-in should construct a PKCE authorization URL.")
        XCTAssertTrue(text.contains("exchangeCode"), "Desktop sign-in should exchange the callback code for a scoped key.")
        XCTAssertTrue(text.contains("saveTrustedRouterAPIKey"), "Desktop sign-in should persist the returned TrustedRouter key.")
        XCTAssertTrue(text.contains("fetchModelCatalog"), "Desktop sign-in should refresh the model catalog after storing the key.")
        XCTAssertFalse(controllerText.contains("exchangeCode"), "Desktop controller should delegate OAuth exchange work.")
        XCTAssertFalse(controllerText.contains("TrustedRouterOAuthClient"), "Desktop controller should not own OAuth client construction.")
        XCTAssertFalse(controllerText.contains("TrustedRouterLoopbackCallbackServer"), "Desktop controller should not own loopback callback capture.")
        XCTAssertFalse(
            text.contains("NSWorkspace.shared.open(url)") && text.contains("TrustedRouterDefaults.signInURL"),
            "Desktop sign-in should not regress to opening the static sign-in documentation page."
        )
    }

    func testDesktopControllerDelegatesCancellableTaskSlots() throws {
        let text = try Self.desktopSourceText()
        let controllerText = try Self.desktopSourceText(named: "QuillCodeDesktopController.swift")

        XCTAssertTrue(text.contains("QuillCodeDesktopTaskCoordinator"), "Desktop cancellable tasks should be isolated behind a coordinator.")
        XCTAssertTrue(controllerText.contains("tasks.startIfIdle(.send"), "Composer sends should use the task coordinator.")
        XCTAssertTrue(controllerText.contains("tasks.startIfIdle(.terminal"), "Terminal runs should use the task coordinator.")
        XCTAssertTrue(controllerText.contains("tasks.replace(.browserPreview"), "Browser previews should replace stale preview work.")
        XCTAssertTrue(controllerText.contains("tasks.replace(.automationTicker"), "Automation ticks should use the task coordinator.")
        XCTAssertFalse(controllerText.contains("private var sendTask"), "Desktop controller should not own raw send task slots.")
        XCTAssertFalse(controllerText.contains("private var terminalTask"), "Desktop controller should not own raw terminal task slots.")
        XCTAssertFalse(controllerText.contains("private var browserPreviewTask"), "Desktop controller should not own raw browser-preview task slots.")
        XCTAssertFalse(controllerText.contains("sendTaskID"), "Desktop controller should not own manual task identity bookkeeping.")
    }

    func testDesktopControllerDelegatesSettingsPersistenceAndSystemSettings() throws {
        let text = try Self.desktopSourceText()
        let controllerText = try Self.desktopSourceText(named: "QuillCodeDesktopController.swift")

        XCTAssertTrue(text.contains("QuillCodeDesktopSettingsCoordinator"), "Desktop settings persistence should be isolated from UI routing.")
        XCTAssertTrue(text.contains("MacSystemSettingsOpener"), "macOS System Settings URLs should be isolated behind a platform opener.")
        XCTAssertTrue(controllerText.contains("settingsCoordinator.apply"), "Settings saves should use the settings coordinator.")
        XCTAssertTrue(controllerText.contains("systemSettingsOpener.open"), "Computer Use system settings routing should use the platform opener.")
        XCTAssertFalse(controllerText.contains("saveTrustedRouterAPIKey"), "Desktop controller should not persist secret keys directly.")
        XCTAssertFalse(controllerText.contains("clearTrustedRouterAPIKey"), "Desktop controller should not clear secret keys directly.")
        XCTAssertFalse(controllerText.contains("trustedRouterAccount = nil"), "Desktop controller should not own auth-account reset rules.")
        XCTAssertFalse(controllerText.contains("NSWorkspace.shared.open"), "Desktop controller should not open platform settings directly.")
        XCTAssertFalse(controllerText.contains("x-apple.systempreferences"), "Desktop controller should not own macOS System Settings URLs.")
        XCTAssertFalse(controllerText.contains("Privacy_ScreenCapture"), "Desktop controller should not own Screen Recording pane URLs.")
        XCTAssertFalse(controllerText.contains("Privacy_Accessibility"), "Desktop controller should not own Accessibility pane URLs.")
    }

    func testDesktopControllerDelegatesTranscriptCopyFeedback() throws {
        let text = try Self.desktopSourceText()
        let controllerText = try Self.desktopSourceText(named: "QuillCodeDesktopController.swift")
        let copyText = try Self.desktopSourceText(named: "QuillCodeDesktopCopyCoordinator.swift")

        XCTAssertTrue(text.contains("QuillCodeDesktopCopyCoordinator"), "Desktop transcript copy behavior should be isolated from UI routing.")
        XCTAssertTrue(copyText.contains("protocol QuillCodePasteboardWriting"), "Pasteboard writes should be isolated behind an injectable protocol.")
        XCTAssertTrue(copyText.contains("struct MacPasteboardWriter"), "Concrete macOS pasteboard access should live in a focused adapter.")
        XCTAssertTrue(copyText.contains("struct QuillCodeDesktopCopyFeedback"), "Transient copy feedback should be represented as a value.")
        XCTAssertTrue(copyText.contains("defaultFeedbackDurationNanoseconds"), "Copy feedback timing should live beside copy behavior.")
        XCTAssertTrue(controllerText.contains("copyCoordinator.copyTranscriptItem"), "Desktop controller should delegate transcript copying.")
        XCTAssertTrue(controllerText.contains("feedback.clearAfterNanoseconds"), "Desktop controller should consume the coordinator's feedback timing.")
        XCTAssertFalse(controllerText.contains("NSPasteboard"), "Desktop controller should not write the pasteboard directly.")
        XCTAssertFalse(controllerText.contains("clearContents()"), "Desktop controller should not own pasteboard mutation details.")
        XCTAssertFalse(controllerText.contains("setString(text, forType: .string)"), "Desktop controller should not own pasteboard mutation details.")
        XCTAssertFalse(controllerText.contains("1_500_000_000"), "Desktop controller should not own copy-feedback timing literals.")
        XCTAssertFalse(controllerText.contains("import AppKit"), "Desktop controller should not import AppKit for copy behavior.")
    }

    func testDesktopControllerDelegatesProjectImportResolution() throws {
        let text = try Self.desktopSourceText()
        let controllerText = try Self.desktopSourceText(named: "QuillCodeDesktopController.swift")
        let importText = try Self.desktopSourceText(named: "QuillCodeDesktopProjectImportCoordinator.swift")

        XCTAssertTrue(text.contains("QuillCodeDesktopProjectImportCoordinator"), "Desktop project import resolution should be isolated from UI routing.")
        XCTAssertTrue(importText.contains("struct QuillCodeDesktopProjectImportSelection"), "Project import selection should be represented as a value.")
        XCTAssertTrue(importText.contains("func selectedProject(from result:"), "Project import resolution should live in the coordinator.")
        XCTAssertTrue(importText.contains("fileExists(atPath: url.path, isDirectory:"), "Project import resolution should validate real directories.")
        XCTAssertTrue(controllerText.contains("projectImportCoordinator.selectedProject"), "Desktop controller should delegate project import result handling.")
        XCTAssertFalse(controllerText.contains("guard case let .success(urls)"), "Desktop controller should not parse file-import results directly.")
        XCTAssertFalse(controllerText.contains("urls.first"), "Desktop controller should not choose imported URLs directly.")
        XCTAssertFalse(controllerText.contains("fileExists(atPath:"), "Desktop controller should not own import directory validation.")
    }

    func testDesktopNotifiesWhenDueAutomationsRun() throws {
        let text = try Self.desktopSourceText()

        XCTAssertTrue(text.contains("UNUserNotificationCenter"), "Desktop app should use native notifications for due automations.")
        XCTAssertTrue(text.contains("MacAutomationNotifier"), "Desktop app should isolate notification delivery behind an adapter.")
        XCTAssertTrue(text.contains("runDueAutomationReports"), "Desktop app should consume structured automation run reports.")
        XCTAssertTrue(text.contains("automationNotifier.deliver"), "Desktop app should deliver a notification for each due automation report.")
    }

    private static func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func swiftSourceFiles(in relativePath: String) throws -> [URL] {
        let root = packageRoot().appendingPathComponent(relativePath)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }
    }

    private static func desktopSourceText() throws -> String {
        let root = packageRoot().appendingPathComponent("Sources/quill-code-desktop")
        return try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "swift" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .map { try String(contentsOf: $0, encoding: .utf8) }
        .joined(separator: "\n")
    }

    private static func desktopSourceText(named fileName: String) throws -> String {
        let file = packageRoot()
            .appendingPathComponent("Sources/quill-code-desktop")
            .appendingPathComponent(fileName)
        return try String(contentsOf: file, encoding: .utf8)
    }

    private static func appSourceText(named fileName: String) throws -> String {
        let file = packageRoot()
            .appendingPathComponent("Sources/QuillCodeApp")
            .appendingPathComponent(fileName)
        return try String(contentsOf: file, encoding: .utf8)
    }

    private static func appTestSourceText(named fileName: String) throws -> String {
        let file = packageRoot()
            .appendingPathComponent("Tests/QuillCodeAppTests")
            .appendingPathComponent(fileName)
        return try String(contentsOf: file, encoding: .utf8)
    }

    private static func agentSourceText(named fileName: String) throws -> String {
        let file = packageRoot()
            .appendingPathComponent("Sources/QuillCodeAgent")
            .appendingPathComponent(fileName)
        return try String(contentsOf: file, encoding: .utf8)
    }

    private static func coreSourceText(named fileName: String) throws -> String {
        let file = packageRoot()
            .appendingPathComponent("Sources/QuillCodeCore")
            .appendingPathComponent(fileName)
        return try String(contentsOf: file, encoding: .utf8)
    }

    private static func toolsSourceText(named fileName: String) throws -> String {
        let file = packageRoot()
            .appendingPathComponent("Sources/QuillCodeTools")
            .appendingPathComponent(fileName)
        return try String(contentsOf: file, encoding: .utf8)
    }
}
