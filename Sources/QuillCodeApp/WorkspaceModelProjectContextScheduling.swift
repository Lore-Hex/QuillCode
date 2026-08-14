import Foundation
import QuillCodeCore
import QuillCodeTools

struct WorkspaceProjectContextRefreshRequest: Sendable, Equatable {
    var projectID: UUID
    var source: WorkspaceProjectContextRefreshSource
    var generation: Int
    var announcesCompletion: Bool

    func matches(projectID: UUID, source: WorkspaceProjectContextRefreshSource) -> Bool {
        self.projectID == projectID && self.source == source
    }
}

enum WorkspaceProjectContextRefreshSource: Sendable, Equatable {
    case local(URL)
    case remote(ProjectConnection)

    var includesLocalExtensions: Bool {
        switch self {
        case .local:
            return true
        case .remote:
            return false
        }
    }

    func matches(_ project: ProjectRef) -> Bool {
        switch self {
        case .local(let root):
            return !project.isRemote
                && URL(fileURLWithPath: project.path).standardizedFileURL == root
        case .remote(let connection):
            return project.isRemote && project.connection == connection
        }
    }
}

enum WorkspaceProjectContextRefreshOutcome: Sendable {
    case loaded(WorkspaceProjectMetadata)
    case failed(String)
}

@MainActor
extension QuillCodeWorkspaceModel {
    /// Refreshes the selected local project's persisted context without delaying the calling UI.
    /// Repeated requests for one root are coalesced because a blocking filesystem syscall cannot
    /// be interrupted by Swift task cancellation. A changed selection queues one follow-up scan.
    public func scheduleSelectedProjectContextRefresh() {
        let projectID = selectedThread?.projectID ?? root.selectedProjectID
        requestProjectContextRefresh(projectID)
    }

    /// Refreshes local or SSH-backed project context without blocking the calling UI. Explicit
    /// requests queue one latest follow-up behind an in-flight scan and surface completion or
    /// failure after the project identity has been revalidated on the main actor.
    @discardableResult
    public func scheduleProjectContextRefresh(_ projectID: UUID) -> Bool {
        guard root.projects.contains(where: { $0.id == projectID }) else { return false }
        requestProjectContextRefresh(
            projectID,
            queueAfterInFlight: true,
            allowsRemote: true,
            announcesCompletion: true
        )
        return true
    }

    /// Starts a best-effort freshness scan for a run but never puts that scan on the send path.
    /// The run uses the last persisted context; a completed refresh is available to later turns.
    func scheduleProjectContextRefreshForAgentSend(_ projectID: UUID?) {
        requestProjectContextRefresh(projectID, queueAfterInFlight: true)
    }

    func requestProjectContextRefreshForNewChat(_ projectID: UUID?) {
        requestProjectContextRefresh(projectID)
    }

    func requestProjectContextRefresh(
        _ projectID: UUID?,
        queueAfterInFlight: Bool = false,
        allowsRemote: Bool = false,
        announcesCompletion: Bool = false
    ) {
        guard let projectID,
              let project = root.projects.first(where: { $0.id == projectID })
        else {
            projectContextRefreshGeneration &+= 1
            projectContextRefreshPending = nil
            return
        }

        let source: WorkspaceProjectContextRefreshSource
        if project.isRemote {
            guard allowsRemote else {
                projectContextRefreshGeneration &+= 1
                projectContextRefreshPending = nil
                return
            }
            source = .remote(project.connection)
        } else {
            source = .local(URL(fileURLWithPath: project.path).standardizedFileURL)
        }

        if let inFlight = projectContextRefreshInFlight,
           inFlight.matches(projectID: projectID, source: source) {
            guard queueAfterInFlight else { return }
            if let pending = projectContextRefreshPending,
               pending.matches(projectID: projectID, source: source) {
                if announcesCompletion, !pending.announcesCompletion {
                    projectContextRefreshPending?.announcesCompletion = true
                }
                return
            }
        }

        projectContextRefreshGeneration &+= 1
        let request = WorkspaceProjectContextRefreshRequest(
            projectID: projectID,
            source: source,
            generation: projectContextRefreshGeneration,
            announcesCompletion: announcesCompletion
        )
        guard projectContextRefreshTask == nil else {
            projectContextRefreshPending = request
            onProjectContextChanged?()
            return
        }
        startProjectContextRefresh(request)
        onProjectContextChanged?()
    }

    private func startProjectContextRefresh(_ request: WorkspaceProjectContextRefreshRequest) {
        let metadataLoader = projectMetadataLoader
        let hookTrustStore = projectHookTrustStore
        let remoteExecutor = sshRemoteShellExecutor
        projectContextRefreshInFlight = request
        projectContextRefreshTask = Task(priority: .utility) { [weak self] in
            let loadingTask = Task.detached(priority: .utility) { () -> WorkspaceProjectContextRefreshOutcome in
                switch request.source {
                case .local(let root):
                    return .loaded(metadataLoader(root, hookTrustStore))
                case .remote(let connection):
                    do {
                        return .loaded(try WorkspaceProjectMetadataLoader.loadRemote(
                            connection: connection,
                            executor: remoteExecutor
                        ))
                    } catch {
                        return .failed(error.localizedDescription)
                    }
                }
            }
            let outcome = await withTaskCancellationHandler {
                await loadingTask.value
            } onCancel: {
                loadingTask.cancel()
            }

            guard let self else { return }
            self.finishProjectContextRefresh(request, outcome: outcome)
        }
    }

    private func finishProjectContextRefresh(
        _ request: WorkspaceProjectContextRefreshRequest,
        outcome: WorkspaceProjectContextRefreshOutcome
    ) {
        let shouldApply = !Task.isCancelled
            && projectContextRefreshGeneration == request.generation
            && root.projects.contains {
                $0.id == request.projectID && request.source.matches($0)
            }

        if shouldApply {
            applyProjectContextRefreshOutcome(outcome, request: request)
        }

        projectContextRefreshTask = nil
        projectContextRefreshInFlight = nil
        if let pending = projectContextRefreshPending {
            projectContextRefreshPending = nil
            startProjectContextRefresh(pending)
        }
        onProjectContextChanged?()
    }

    private func applyProjectContextRefreshOutcome(
        _ outcome: WorkspaceProjectContextRefreshOutcome,
        request: WorkspaceProjectContextRefreshRequest
    ) {
        switch outcome {
        case .loaded(let metadata):
            guard WorkspaceProjectEngine.applyMetadata(
                metadata,
                to: request.projectID,
                projects: &root.projects,
                includeLocalExtensions: request.source.includesLocalExtensions
            ) else { return }
            worktreeEnvironmentSurfacesByProjectID[request.projectID] =
                metadata.worktreeEnvironmentSurface
            syncThreadAfterProjectContextRefresh(request)
            if request.announcesCompletion {
                setLastError(nil)
                touchProject(request.projectID)
            }
            saveProjects()
            refreshTopBar(agentStatus: root.topBar.agentStatus)
        case .failed(let message):
            guard request.announcesCompletion else { return }
            setLastError(message)
            appendProjectContextRefreshEvent(
                projectID: request.projectID,
                summary: "Project context refresh failed",
                payloadJSON: message
            )
        }
    }

    private func syncThreadAfterProjectContextRefresh(
        _ request: WorkspaceProjectContextRefreshRequest
    ) {
        guard selectedThread?.projectID == request.projectID else { return }
        let refreshedContext = workspaceThreadContext(request.projectID)
        mutateSelectedThread { thread in
            guard !thread.runtimeContext.isConfidential else { return }
            thread.instructions = refreshedContext.instructions
            thread.memories = refreshedContext.memories
            if request.announcesCompletion {
                thread.events.append(ThreadEvent(
                    kind: .notice,
                    summary: "Refreshed project context",
                    payloadJSON: request.projectID.uuidString
                ))
            }
        }
    }

    private func appendProjectContextRefreshEvent(
        projectID: UUID,
        summary: String,
        payloadJSON: String
    ) {
        guard selectedThread?.projectID == projectID else { return }
        mutateSelectedThread { thread in
            guard !thread.runtimeContext.isConfidential else { return }
            thread.events.append(ThreadEvent(
                kind: .notice,
                summary: summary,
                payloadJSON: payloadJSON
            ))
        }
    }

    var refreshingProjectContextIDs: Set<UUID> {
        Set([
            projectContextRefreshInFlight?.projectID,
            projectContextRefreshPending?.projectID
        ].compactMap(\.self))
    }

    func waitForScheduledProjectContextRefresh() async {
        while let task = projectContextRefreshTask {
            await task.value
        }
    }
}
