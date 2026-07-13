import Foundation
import QuillCodeCore
import QuillCodeTools

@MainActor
extension QuillCodeWorkspaceModel {
    public func createWorktree(_ request: WorkspaceWorktreeCreateRequest, workspaceRoot: URL) {
        let result = runToolCall(
            WorkspaceWorktreeToolCallPlanner.create(request),
            workspaceRoot: workspaceRoot
        )
        if result.ok {
            openToolResultWorktree(result) { projectID in
                worktreeOpenContext(projectID: projectID, request: request)
            }
        }
    }

    public func openWorktree(_ request: WorkspaceWorktreeOpenRequest, workspaceRoot: URL) {
        let result = runToolCall(
            WorkspaceWorktreeToolCallPlanner.open(request),
            workspaceRoot: workspaceRoot
        )
        if result.ok {
            openToolResultWorktree(result) { projectID in
                worktreeOpenContext(projectID: projectID, request: request)
            }
        }
    }

    @discardableResult
    public func createBranchHere(_ request: WorkspaceWorktreeCreateBranchRequest) -> Bool {
        guard !composer.isSending,
              !terminal.isRunning,
              let threadID = root.selectedThreadID,
              let binding = selectedThread?.worktree,
              binding.location == .worktree,
              binding.isResolvable,
              binding.branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let workspaceRoot = activeWorkspaceRoot,
              workspaceRoot.standardizedFileURL.path == URL(fileURLWithPath: binding.path).standardizedFileURL.path
        else { return false }

        let result = runToolCall(
            WorkspaceWorktreeToolCallPlanner.createBranch(request),
            workspaceRoot: workspaceRoot
        )
        guard result.ok else { return false }
        _ = reconcileManagedWorktreeBranch(threadID: threadID, workspaceRoot: workspaceRoot)
        return root.threads.first(where: { $0.id == threadID })?.worktree?.branch
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    /// The Worktree thread type creates a detached managed worktree from the current branch, transfers
    /// bounded local changes, and binds a new thread in the same project to that isolated run root.
    @discardableResult
    public func newWorktreeThread(name: String? = nil) -> UUID? {
        guard let project = selectedProject, !project.isRemote else { return nil }
        let projectRoot = URL(fileURLWithPath: project.path)
        let baseBranch = selectedProjectBranch(project)
            ?? currentLocalBranch(projectRoot: projectRoot)
            ?? "HEAD"
        let plan = WorktreeThreadPlanner.plan(
            projectRoot: projectRoot,
            baseBranch: baseBranch,
            name: name,
            managedRoot: managedWorktreeRoot
        )
        let result = runToolCall(
            WorkspaceWorktreeToolCallPlanner.create(plan.request),
            workspaceRoot: projectRoot
        )
        guard result.ok, let worktreePath = result.artifacts.first else { return nil }
        let threadID = newChat(projectID: project.id)
        _ = renameThread(threadID, to: plan.title)
        bindSelectedThreadToWorktree(
            path: worktreePath,
            branch: "",
            base: baseBranch,
            managedRoot: plan.managedRoot.path
        )
        enforceManagedWorktreeRetention()
        return threadID
    }

    private func selectedProjectBranch(_ project: ProjectRef) -> String? {
        guard root.topBar.branchStatusProjectID == project.id,
              let branch = root.topBar.branchStatus?.branch,
              !branch.isEmpty
        else {
            return nil
        }
        return branch
    }

    var managedWorktreeRoot: URL {
        root.config.managedWorktrees.resolvedRoot(
            defaultRoot: managedWorktreeDefaultRoot,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    private func currentLocalBranch(projectRoot: URL) -> String? {
        let result = GitToolExecutor().listBranches(cwd: projectRoot, includeRemote: false)
        guard result.ok else { return nil }
        for line in result.stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 2,
                  fields[0].trimmingCharacters(in: .whitespaces) == "*" else {
                continue
            }
            let branch = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
            return branch.isEmpty ? nil : branch
        }
        return nil
    }

    @discardableResult
    func reconcileManagedWorktreeBranch(threadID: UUID, workspaceRoot: URL) -> Bool {
        guard let thread = root.threads.first(where: { $0.id == threadID }),
              let binding = thread.worktree,
              binding.location == .worktree,
              binding.isResolvable,
              binding.branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              workspaceRoot.standardizedFileURL.path
                == URL(fileURLWithPath: binding.path).standardizedFileURL.path,
              let branch = currentLocalBranch(projectRoot: workspaceRoot)
        else { return false }

        mutateThread(threadID) { thread in
            thread.worktree?.branch = branch
            thread.updatedAt = Date()
        }
        if let updated = root.threads.first(where: { $0.id == threadID }) {
            threadPersistence.save(updated)
        }
        if root.selectedThreadID == threadID {
            refreshTopBar()
        }
        return true
    }

    public func worktreeChoiceLoadRequest(workspaceRoot: URL) -> WorkspaceWorktreeChoiceLoadRequest {
        WorkspaceWorktreeChoiceLoadRequest(
            workspaceRoot: workspaceRoot,
            selectedProject: selectedProject,
            sshRemoteShellExecutor: sshRemoteShellExecutor
        )
    }

    public func worktreeChoiceLoad(workspaceRoot: URL) -> WorkspaceWorktreeChoiceLoad {
        worktreeChoiceLoadRequest(workspaceRoot: workspaceRoot).load()
    }

    public func worktreeChoices(workspaceRoot: URL) -> [WorkspaceWorktreeChoice] {
        worktreeChoiceLoad(workspaceRoot: workspaceRoot).choices
    }

    public func worktreePrunePreviewLoadRequest(workspaceRoot: URL) -> WorkspaceWorktreePrunePreviewLoadRequest {
        WorkspaceWorktreePrunePreviewLoadRequest(
            workspaceRoot: workspaceRoot,
            selectedProject: selectedProject,
            sshRemoteShellExecutor: sshRemoteShellExecutor
        )
    }

    public func worktreePrunePreview(workspaceRoot: URL) -> WorkspaceWorktreePrunePreview {
        worktreePrunePreviewLoadRequest(workspaceRoot: workspaceRoot).load()
    }

    @discardableResult
    public func handoffSelectedThread() -> Bool {
        guard !composer.isSending,
              !terminal.isRunning,
              let project = selectedProject,
              !project.isRemote,
              let binding = selectedThread?.worktree,
              binding.isResolvable,
              binding.branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let sourceRoot = activeWorkspaceRoot else {
            return false
        }
        let destination: URL
        let nextLocation: WorktreeExecutionLocation
        switch binding.location {
        case .worktree:
            destination = URL(fileURLWithPath: project.path).standardizedFileURL
            nextLocation = .local
        case .local:
            destination = URL(fileURLWithPath: binding.path).standardizedFileURL
            nextLocation = .worktree
        }
        let result = runToolCall(
            WorkspaceWorktreeToolCallPlanner.handoff(destination: destination.path),
            workspaceRoot: sourceRoot
        )
        guard result.ok else { return false }

        setSelectedThreadWorktreeLocation(nextLocation)
        terminal.currentDirectoryPath = destination.path
        terminal.environmentOverrides = [:]
        terminal.removedEnvironmentKeys = []
        terminal.resetInputModes()
        refreshFileMentionIndex()
        refreshTopBar()
        return true
    }

    public func removeWorktree(_ request: WorkspaceWorktreeRemoveRequest, workspaceRoot: URL) {
        runToolCall(
            WorkspaceWorktreeToolCallPlanner.remove(request),
            workspaceRoot: workspaceRoot
        )
    }

    public func pruneWorktrees(_ request: WorkspaceWorktreePruneRequest, workspaceRoot: URL) {
        runToolCall(
            WorkspaceWorktreeToolCallPlanner.prune(request),
            workspaceRoot: workspaceRoot
        )
    }

    private func openToolResultWorktree(
        _ result: ToolResult,
        context: (UUID) -> WorkspaceWorktreeOpenContext
    ) {
        guard let artifact = result.artifacts.first else { return }
        if selectedProject?.isRemote == true {
            openToolResultRemoteWorktree(artifact, context: context)
            return
        }
        let worktreeURL = URL(fileURLWithPath: artifact).standardizedFileURL
        guard FileManager.default.fileExists(atPath: worktreeURL.path) else { return }

        let projectID = addProject(
            path: worktreeURL,
            name: WorkspaceProjectEngine.defaultProjectName(for: worktreeURL)
        )
        refreshProjectMetadata(projectID)

        let opened = WorkspaceWorktreeOpenEngine.localThread(
            worktreeURL: worktreeURL,
            context: context(projectID)
        )
        openCreatedWorktreeThread(opened.thread, projectID: projectID)
    }

    private func openToolResultRemoteWorktree(
        _ artifact: String,
        context: (UUID) -> WorkspaceWorktreeOpenContext
    ) {
        guard let connection = ProjectConnection.parseSSH(artifact),
              let projectID = addSSHProject(
                artifact,
                name: WorkspaceProjectEngine.defaultSSHProjectName(for: connection)
              ) else {
            return
        }

        let opened = WorkspaceWorktreeOpenEngine.remoteThread(
            connection: connection,
            context: context(projectID)
        )
        openCreatedWorktreeThread(opened.thread, projectID: projectID)
    }

    private func worktreeOpenContext(
        projectID: UUID,
        request: WorkspaceWorktreeCreateRequest
    ) -> WorkspaceWorktreeOpenContext {
        WorkspaceProjectContextRefresher.worktreeOpenContext(
            request: request,
            projectID: projectID,
            mode: root.config.mode,
            model: root.config.defaultModel,
            projects: root.projects,
            globalMemories: root.globalMemories
        )
    }

    private func worktreeOpenContext(
        projectID: UUID,
        request: WorkspaceWorktreeOpenRequest
    ) -> WorkspaceWorktreeOpenContext {
        WorkspaceProjectContextRefresher.worktreeOpenContext(
            request: request,
            projectID: projectID,
            mode: root.config.mode,
            model: root.config.defaultModel,
            projects: root.projects,
            globalMemories: root.globalMemories
        )
    }

    private func openCreatedWorktreeThread(_ thread: ChatThread, projectID: UUID) {
        _ = insertCreatedThread(thread, selectedProjectID: projectID, saveThread: true)
    }
}
