import XCTest

final class ParityWorkspaceContextRefreshGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesProjectContextRefresh() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let composerText = try Self.appSourceText(named: "WorkspaceModelComposer.swift")
        let threadText = try Self.appSourceText(named: "WorkspaceModelThreads.swift")
        let worktreeText = try Self.appSourceText(named: "WorkspaceModelWorktrees.swift")
        let refresherText = try Self.appSourceText(named: "WorkspaceProjectContextRefresher.swift")
        let contextPreparerText = try Self.appSourceText(named: "WorkspaceThreadContextPreparer.swift")

        assertFocusedRefresher(refresherText)
        assertWorkspaceModelDelegatesRefresh(modelText)
        assertThreadContextPreparation(composerText, contextPreparerText)
        Self.assertSource(threadText, contains: "WorkspaceProjectContextRefresher.threadCreationContext")
        Self.assertSource(worktreeText, contains: "WorkspaceProjectContextRefresher.worktreeOpenContext")
        assertWorkspaceModelAvoidsRefreshOwnership(modelText)
        Self.assertSource(
            composerText,
            excludes: "WorkspaceProjectContextRefresher.syncThreadContext"
        )
    }

    func testUserProjectContextRefreshUsesTheVisibleBackgroundContract() throws {
        let schedulingText = try Self.appSourceText(named: "WorkspaceModelProjectContextScheduling.swift")
        let rowExecutorText = try Self.appSourceText(named: "WorkspaceSidebarRowActionPlanner.swift")
        let commandExecutorText = try Self.appSourceText(named: "WorkspaceCommandActionExecutor.swift")
        let planExecutorText = try Self.appSourceText(named: "WorkspaceCommandPlanExecutor.swift")
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")

        Self.assertSource(schedulingText, containsAll: [
            "public func scheduleProjectContextRefresh",
            "Task.detached(priority: .utility)",
            "WorkspaceProjectMetadataLoader.loadRemote",
            "var refreshingProjectContextIDs"
        ])
        Self.assertSource(rowExecutorText, contains: "model.scheduleProjectContextRefresh(projectID)")
        Self.assertSource(commandExecutorText, contains: "scheduleProjectContextRefresh(projectID)")
        Self.assertSource(planExecutorText, contains: "scheduleProjectContextRefresh(projectID)")
        Self.assertSource(surfaceText, containsAll: [
            "refreshingProjectIDs: refreshingProjectContextIDs",
            "projectContextRefreshIsActive: selectedProject.map"
        ])
    }

    private func assertFocusedRefresher(_ source: String) {
        [
            "enum WorkspaceProjectContextRefresher",
            "refreshLocalProjectMetadata",
            "refreshRemoteProjectContext",
            "syncThreadContext",
            "syncThreadMemories",
            "threadCreationContext",
            "worktreeOpenContext",
            "static func globalMemories"
        ].forEach { Self.assertSource(source, contains: $0) }
    }

    private func assertWorkspaceModelDelegatesRefresh(_ modelText: String) {
        [
            "WorkspaceProjectContextRefresher.refreshLocalProjectMetadata",
            "WorkspaceProjectContextRefresher.refreshRemoteProjectContext"
        ].forEach { Self.assertSource(modelText, contains: $0) }
    }

    private func assertThreadContextPreparation(
        _ composerText: String,
        _ contextPreparerText: String
    ) {
        Self.assertSource(
            contextPreparerText,
            contains: "WorkspaceProjectContextRefresher.syncThreadContext"
        )
        Self.assertSource(
            composerText,
            contains: "WorkspaceThreadContextPreparer.syncThreadContext"
        )
    }

    private func assertWorkspaceModelAvoidsRefreshOwnership(_ modelText: String) {
        [
            "WorkspaceProjectContextRefresher.syncThreadContext",
            "WorkspaceProjectContextRefresher.worktreeOpenContext",
            "WorkspaceProjectMetadataLoader.loadLocal(from: rootURL)",
            "WorkspaceProjectMetadataLoader.loadRemote",
            "WorkspaceMemoryEngine.loadGlobal(from:",
            "contextResolver.instructions(for:",
            "contextResolver.memoryNotes(for:",
            "thread.instructions = contextResolver.instructions",
            "thread.memories = contextResolver.memoryNotes"
        ].forEach { Self.assertSource(modelText, excludes: $0) }
    }
}
