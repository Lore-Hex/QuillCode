import Foundation
import QuillCodeCore
import QuillCodeTools

struct WorkspaceProjectContextRefreshRequest: Sendable, Equatable {
    var projectID: UUID
    var projectRoot: URL
    var generation: Int
}

@MainActor
extension QuillCodeWorkspaceModel {
    @discardableResult
    public func addProject(path: URL, name: String? = nil) -> UUID {
        let previousLocation = currentNavigationLocation
        let standardized = path.standardizedFileURL
        let metadata = WorkspaceProjectMetadataLoader.loadLocal(
            from: standardized,
            hookTrustStore: projectHookTrustStore
        )
        let result = WorkspaceProjectEngine.upsertLocalProject(
            path: standardized,
            name: name,
            metadata: metadata,
            projects: &root.projects
        )
        worktreeEnvironmentSurfacesByProjectID[result.projectID] = metadata.worktreeEnvironmentSurface
        root.selectedProjectID = result.projectID
        syncTerminalSessionToSelectedProject()
        refreshFileMentionIndex()
        saveProjects()
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        recordNavigationTransition(from: previousLocation)
        return result.projectID
    }

    @discardableResult
    public func addSSHProject(_ address: String, name: String? = nil) -> UUID? {
        guard let connection = ProjectConnection.parseSSH(address) else {
            setLastError(WorkspaceProjectEngine.invalidSSHAddressMessage)
            return nil
        }
        return addSSHProject(connection: connection, name: name)
    }

    @discardableResult
    public func addSSHProject(connection: ProjectConnection, name: String? = nil) -> UUID? {
        let previousLocation = currentNavigationLocation
        let result: WorkspaceProjectUpsertResult
        switch WorkspaceProjectEngine.upsertSSHProject(
            connection: connection,
            name: name,
            projects: &root.projects
        ) {
        case .failure(let error):
            setLastError(error.message)
            return nil
        case .success(let upsertedProject):
            result = upsertedProject
        }
        root.selectedProjectID = result.projectID
        syncTerminalSessionToSelectedProject()
        refreshFileMentionIndex()
        saveProjects()
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        recordNavigationTransition(from: previousLocation)
        return result.projectID
    }

    public func selectProject(_ id: UUID?, recordsNavigation: Bool = true) {
        _ = returnFromSideConversation()
        _ = discardConfidentialThreadOnExit()
        guard let selection = WorkspaceProjectEngine.selectionAfterSelectingProject(
            id,
            projects: root.projects,
            threads: root.threads
        ) else { return }
        let previousLocation = currentNavigationLocation
        root.selectedProjectID = selection.projectID
        syncTerminalSessionToSelectedProject()
        touchProject(selection.projectID)
        root.selectedThreadID = selection.threadID
        requestProjectContextRefresh(selection.projectID)
        saveProjects()
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        if recordsNavigation {
            recordNavigationTransition(from: previousLocation)
        }
    }

    public func refreshSelectedProjectInstructions() {
        refreshSelectedProjectContext()
    }

    /// Refreshes the selected local project's persisted context without delaying the calling UI.
    /// Repeated requests for one root are coalesced because a blocking filesystem syscall cannot
    /// be interrupted by Swift task cancellation. A changed selection queues one follow-up scan.
    public func scheduleSelectedProjectContextRefresh() {
        let projectID = selectedThread?.projectID ?? root.selectedProjectID
        requestProjectContextRefresh(projectID)
    }

    /// Starts a best-effort freshness scan for a run but never puts that scan on the send path.
    /// The run uses the last persisted context; a completed refresh is available to later turns.
    func scheduleProjectContextRefreshForAgentSend(_ projectID: UUID?) {
        requestProjectContextRefresh(projectID, queueAfterInFlight: true)
    }

    func requestProjectContextRefreshForNewChat(_ projectID: UUID?) {
        requestProjectContextRefresh(projectID)
    }

    private func requestProjectContextRefresh(
        _ projectID: UUID?,
        queueAfterInFlight: Bool = false
    ) {
        guard let projectID,
              let project = root.projects.first(where: { $0.id == projectID }),
              !project.isRemote
        else {
            projectContextRefreshGeneration &+= 1
            projectContextRefreshPending = nil
            return
        }

        let projectRoot = URL(fileURLWithPath: project.path).standardizedFileURL
        if let inFlight = projectContextRefreshInFlight,
           inFlight.projectID == projectID,
           inFlight.projectRoot == projectRoot {
            guard queueAfterInFlight else { return }
            if let pending = projectContextRefreshPending,
               pending.projectID == projectID,
               pending.projectRoot == projectRoot {
                return
            }
        }

        projectContextRefreshGeneration &+= 1
        let request = WorkspaceProjectContextRefreshRequest(
            projectID: projectID,
            projectRoot: projectRoot,
            generation: projectContextRefreshGeneration
        )
        guard projectContextRefreshTask == nil else {
            projectContextRefreshPending = request
            return
        }
        startProjectContextRefresh(request)
    }

    private func startProjectContextRefresh(_ request: WorkspaceProjectContextRefreshRequest) {
        let metadataLoader = projectMetadataLoader
        let hookTrustStore = projectHookTrustStore
        projectContextRefreshInFlight = request
        projectContextRefreshTask = Task(priority: .utility) { [weak self] in
            let loadingTask = Task.detached(priority: .utility) {
                metadataLoader(request.projectRoot, hookTrustStore)
            }
            let metadata = await loadingTask.value

            guard let self else { return }
            self.finishProjectContextRefresh(request, metadata: metadata)
        }
    }

    private func finishProjectContextRefresh(
        _ request: WorkspaceProjectContextRefreshRequest,
        metadata: WorkspaceProjectMetadata
    ) {
        let shouldApply = !Task.isCancelled
            && projectContextRefreshGeneration == request.generation
            && root.projects.contains { project in
                project.id == request.projectID
                    && !project.isRemote
                    && URL(fileURLWithPath: project.path).standardizedFileURL == request.projectRoot
            }

        if shouldApply,
           WorkspaceProjectEngine.applyMetadata(
                metadata,
                to: request.projectID,
                projects: &root.projects,
                includeLocalExtensions: true
           ) {
            worktreeEnvironmentSurfacesByProjectID[request.projectID] =
                metadata.worktreeEnvironmentSurface
            if selectedThread?.projectID == request.projectID {
                let refreshedContext = workspaceThreadContext(request.projectID)
                mutateSelectedThread { thread in
                    guard !thread.runtimeContext.isConfidential else { return }
                    thread.instructions = refreshedContext.instructions
                    thread.memories = refreshedContext.memories
                }
            }
            saveProjects()
            refreshTopBar(agentStatus: root.topBar.agentStatus)
            onProjectContextChanged?()
        }

        projectContextRefreshTask = nil
        projectContextRefreshInFlight = nil
        if let pending = projectContextRefreshPending {
            projectContextRefreshPending = nil
            startProjectContextRefresh(pending)
        }
    }

    func waitForScheduledProjectContextRefresh() async {
        while let task = projectContextRefreshTask {
            await task.value
        }
    }

    public func refreshSelectedProjectContext() {
        projectContextRefreshGeneration &+= 1
        projectContextRefreshPending = nil
        let projectID = selectedThread?.projectID ?? root.selectedProjectID
        refreshProjectMetadata(projectID)
        let refreshedContext = workspaceThreadContext(projectID)
        mutateSelectedThread { thread in
            thread.instructions = refreshedContext.instructions
            thread.memories = refreshedContext.memories
        }
        saveProjects()
    }

    @discardableResult
    public func renameProject(_ id: UUID, to name: String) -> Bool {
        guard WorkspaceProjectEngine.renameProject(id, to: name, projects: &root.projects) else {
            return false
        }
        saveProjects()
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }

    @discardableResult
    public func moveProjectToTop(_ id: UUID) -> Bool {
        guard WorkspaceProjectEngine.touchProject(id, projects: &root.projects) else {
            return false
        }
        saveProjects()
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }

    @discardableResult
    public func moveProjectToBottom(_ id: UUID) -> Bool {
        guard WorkspaceProjectEngine.moveProjectToBottom(id, projects: &root.projects) else {
            return false
        }
        saveProjects()
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }

    @discardableResult
    public func moveProject(_ id: UUID, direction: WorkspaceProjectMoveDirection) -> Bool {
        guard WorkspaceProjectEngine.moveProject(id, direction: direction, projects: &root.projects) else {
            return false
        }
        saveProjects()
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }

    @discardableResult
    public func moveProject(_ sourceID: UUID, before targetID: UUID) -> Bool {
        guard WorkspaceProjectEngine.moveProject(sourceID, before: targetID, projects: &root.projects) else {
            return false
        }
        saveProjects()
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }

    @discardableResult
    public func refreshProjectContext(_ id: UUID) -> Bool {
        guard let project = root.projects.first(where: { $0.id == id }) else {
            return false
        }
        if project.isRemote {
            guard refreshRemoteProjectContext(id) else {
                return false
            }
        } else {
            refreshProjectMetadata(id)
        }
        if selectedThread?.projectID == id || root.selectedProjectID == id {
            let refreshedContext = workspaceThreadContext(id)
            mutateSelectedThread { thread in
                guard thread.projectID == id else { return }
                // Confidential threads deliberately carry no workspace context; a project refresh must
                // not become the side door that fills the private conversation with durable notes.
                guard !thread.runtimeContext.isConfidential else { return }
                thread.instructions = refreshedContext.instructions
                thread.memories = refreshedContext.memories
                thread.events.append(ThreadEvent(
                    kind: .notice,
                    summary: "Refreshed project context",
                    payloadJSON: id.uuidString
                ))
            }
        }
        touchProject(id)
        saveProjects()
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }

    @discardableResult
    public func runProjectExtensionUpdate(id: String, workspaceRoot: URL) -> Bool {
        runProjectExtensionCommand(
            id: id,
            workspaceRoot: workspaceRoot,
            planToolCall: WorkspaceExtensionToolCallPlanner.update,
            successNotice: { "Updated extension \($0.name)" },
            failureNotice: { "Extension update failed for \($0.name)" }
        )
    }

    @discardableResult
    public func runProjectExtensionInstall(id: String, workspaceRoot: URL) -> Bool {
        runProjectExtensionCommand(
            id: id,
            workspaceRoot: workspaceRoot,
            planToolCall: WorkspaceExtensionToolCallPlanner.install,
            successNotice: { "Installed extension \($0.name)" },
            failureNotice: { "Extension install failed for \($0.name)" }
        )
    }

    @discardableResult
    public func setProjectHookTrust(
        id: String,
        decision: ProjectHookTrustDecision
    ) -> Bool {
        guard let projectHookTrustStore else { return false }

        refreshProjectMetadata(selectedProject?.id)
        let project = selectedProject
        guard let hook = effectiveHookDefinitions(for: project).first(where: { $0.id == id }),
              !hook.isManaged,
              decision != .trusted || hook.supportStatus.isSupported,
              let trustScopeRoot = trustScopeRoot(for: hook, project: project)
        else { return false }

        do {
            try projectHookTrustStore.setDecision(
                decision,
                for: hook,
                workspaceRoot: trustScopeRoot
            )
            refreshProjectMetadata(project?.id)
            saveProjects()
            appendNotice(
                decision == .trusted
                    ? "Trusted hook: \(hook.statusMessage ?? hook.event)"
                    : "Disabled hook: \(hook.statusMessage ?? hook.event)"
            )
            return true
        } catch {
            setLastError("Could not save hook trust: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    private func runProjectExtensionCommand(
        id: String,
        workspaceRoot: URL,
        planToolCall: (ProjectExtensionManifest) -> ToolCall?,
        successNotice: (ProjectExtensionManifest) -> String,
        failureNotice: (ProjectExtensionManifest) -> String
    ) -> Bool {
        refreshProjectMetadata(root.selectedProjectID)
        guard let manifest = selectedProject?.extensionManifests.first(where: { $0.id == id }),
              let toolCall = planToolCall(manifest)
        else {
            return false
        }

        let result = runToolCall(
            toolCall,
            workspaceRoot: workspaceRoot
        )
        refreshProjectMetadata(root.selectedProjectID)
        appendNotice(result.ok ? successNotice(manifest) : failureNotice(manifest))
        return result.ok
    }

    @discardableResult
    public func removeProject(_ id: UUID) -> Bool {
        let previousLocation = currentNavigationLocation
        var projects = root.projects
        var threads = root.threads
        guard let result = WorkspaceProjectEngine.removeProject(
            id,
            projects: &projects,
            threads: &threads,
            selectedProjectID: root.selectedProjectID
        ) else {
            return false
        }
        root.projects = projects
        root.threads = threads
        worktreeEnvironmentSurfacesByProjectID[id] = nil
        for threadID in result.changedThreadIDs {
            guard let thread = root.threads.first(where: { $0.id == threadID }) else { continue }
            threadPersistence.save(thread)
        }
        root.selectedProjectID = result.selectedProjectID
        syncTerminalSessionToSelectedProject()
        saveProjects()
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        recordNavigationTransition(from: previousLocation)
        pruneNavigationHistory()
        return true
    }
}
