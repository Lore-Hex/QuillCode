import XCTest

final class ParityWorkspaceModelStateGateTests: QuillCodeParityTestCase {
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
        let threadMutationText = try Self.appSourceText(named: "WorkspaceModelThreadMutation.swift")
        let reviewExtensionText = try Self.appSourceText(named: "WorkspaceModelReview.swift")
        let appenderText = try Self.appSourceText(named: "WorkspaceThreadNoticeAppender.swift")

        XCTAssertTrue(appenderText.contains("enum WorkspaceThreadNoticeAppender"), "Thread notice mutation should live in a focused helper.")
        XCTAssertTrue(appenderText.contains("static func appendNotice"), "Notice event mutation should be directly testable.")
        XCTAssertTrue(appenderText.contains("static func appendAssistantNotice"), "Assistant notice mutation should be directly testable.")
        XCTAssertTrue(threadMutationText.contains("WorkspaceThreadNoticeAppender.appendNotice"), "Workspace thread mutation extension should delegate notice event mutation.")
        XCTAssertTrue(reviewExtensionText.contains("WorkspaceThreadNoticeAppender.appendAssistantNotice"), "Workspace review extension should delegate assistant notice mutation.")
        XCTAssertFalse(modelText.contains("WorkspaceThreadNoticeAppender.appendNotice"), "WorkspaceModel.swift should not own notice event mutation.")
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
        let threadMutationText = try Self.appSourceText(named: "WorkspaceModelThreadMutation.swift")
        let composerText = try Self.appSourceText(named: "WorkspaceModelComposer.swift")

        XCTAssertTrue(threadMutationText.contains("func updateThreadFromAgentRun"), "Agent-run thread updates should use a named helper that documents focus preservation.")
        XCTAssertTrue(composerText.contains("updateThreadFromAgentRun(thread)"), "Agent progress and completion should route through the explicit async-update helper.")
        XCTAssertFalse(modelText.contains("func updateThreadFromAgentRun"), "WorkspaceModel.swift should not own agent-run thread replacement.")
        XCTAssertFalse(modelText.contains("preservingSelection"), "WorkspaceModel should not hide async navigation behavior behind a boolean flag.")
        XCTAssertFalse(modelText.contains("replaceThread("), "WorkspaceModel should not route async run updates through an ambiguous generic replacement helper.")
    }

}
