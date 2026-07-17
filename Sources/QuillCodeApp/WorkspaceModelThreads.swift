import Foundation
import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
    @discardableResult
    public func newChat(projectID: UUID? = nil) -> UUID {
        _ = returnFromSideConversation()
        _ = discardIncognitoThreadOnExit()
        let effectiveProjectID = knownProjectID(projectID ?? root.selectedProjectID)
        refreshProjectMetadata(effectiveProjectID)
        let context = WorkspaceProjectContextRefresher.threadCreationContext(
            projectID: effectiveProjectID,
            mode: root.config.mode,
            model: root.config.defaultModel,
            personality: root.config.defaultPersonality,
            projects: root.projects,
            globalMemories: root.globalMemories
        )
        let thread = WorkspaceThreadCreationEngine.newThread(context: context)
        return insertCreatedThread(thread, selectedProjectID: effectiveProjectID, saveThread: false)
    }

    /// Starts an incognito chat: a session-only thread (never persisted, excluded from the sidebar)
    /// pinned to the end-to-end-encrypted TrustedRouter route. Deliberately does NOT reuse
    /// `threadCreationContext` — incognito threads carry no workspace instructions/memories and
    /// ignore the configured default model.
    @discardableResult
    public func newIncognitoChat(projectID: UUID? = nil) -> UUID {
        _ = returnFromSideConversation()
        // Starting incognito from incognito replaces the old session entirely.
        _ = discardIncognitoThreadOnExit()
        let effectiveProjectID = knownProjectID(projectID ?? root.selectedProjectID)
        let thread = WorkspaceThreadCreationEngine.incognitoThread(
            projectID: effectiveProjectID,
            mode: root.config.mode
        )
        return insertCreatedThread(thread, selectedProjectID: effectiveProjectID, saveThread: false)
    }

    @discardableResult
    public func forkFromLast() -> UUID? {
        forkThread(strategy: .latestTurn)
    }

    /// Fork/compact/duplicate all create a DURABLE (saveThread: true) copy of the source transcript —
    /// which would silently break an ephemeral thread's "never saved" promise. The palette disables
    /// these commands for ephemeral threads, but typed /fork, /compact, and /duplicate bypass
    /// isEnabled and land here (and in the async model-backed-summary continuations), so the guard
    /// must live at the model level.
    func refuseDurableContinuation(of source: ChatThread, action: String) -> Bool {
        guard source.runtimeContext.isEphemeral else { return false }
        setLastError("Can't \(action) an incognito or side conversation: it would save the private transcript.")
        return true
    }

    @discardableResult
    func forkThread(strategy: WorkspaceThreadForkStrategy) -> UUID? {
        guard let source = selectedThread, !source.messages.isEmpty else { return nil }
        guard !refuseDurableContinuation(of: source, action: "fork") else { return nil }
        let projectID = knownProjectID(source.projectID)
        let fork = WorkspaceThreadCreationEngine.forkThread(
            from: source,
            projectID: projectID,
            strategy: strategy
        )
        return insertCreatedThread(fork, selectedProjectID: projectID, saveThread: true)
    }

    @discardableResult
    public func compactContext() -> UUID? {
        guard let source = selectedThread, !source.messages.isEmpty else { return nil }
        guard !refuseDurableContinuation(of: source, action: "compact") else { return nil }
        let projectID = knownProjectID(source.projectID)
        let compacted = WorkspaceThreadCreationEngine.compactThread(
            from: source,
            projectID: projectID
        )
        return insertCreatedThread(
            compacted,
            selectedProjectID: projectID,
            saveThread: true,
            sessionStartSource: .compact
        )
    }

    @discardableResult
    public func duplicateThread(_ id: UUID) -> UUID? {
        guard let source = root.threads.first(where: { $0.id == id }) else { return nil }
        guard !refuseDurableContinuation(of: source, action: "duplicate") else { return nil }
        let projectID = knownProjectID(source.projectID)
        let duplicate = WorkspaceThreadCreationEngine.duplicateThread(
            source,
            projectID: projectID
        )
        return insertCreatedThread(duplicate, selectedProjectID: projectID, saveThread: true)
    }

    /// Binds the selected thread to a worktree so its agent runs operate in that isolated directory
    /// and branch instead of the shared project root. Persists through the shared thread-mutation
    /// helper. `base` records the ref this worktree was forked off (its land-back target).
    public func bindSelectedThreadToWorktree(
        path: String,
        branch: String,
        base: String? = nil,
        managedRoot: String? = nil,
        setupSelection: WorktreeSetupSelection = .automatic
    ) {
        mutateSelectedThread { thread in
            thread.worktree = WorktreeBinding(
                path: path,
                branch: branch,
                base: base,
                managedRoot: managedRoot,
                setupSelection: setupSelection
            )
            thread.updatedAt = Date()
        }
    }

    func setSelectedThreadWorktreeLocation(_ location: WorktreeExecutionLocation) {
        mutateSelectedThread { thread in
            thread.worktree?.location = location
            thread.updatedAt = Date()
        }
    }

    func setSelectedThreadPullRequest(_ pullRequest: PullRequestLink) {
        mutateSelectedThread { thread in
            thread.pullRequest = pullRequest
            thread.updatedAt = Date()
        }
    }

    func clearWorktreeBinding(threadID: UUID) {
        mutateThread(threadID) { thread in
            thread.worktree = nil
            thread.updatedAt = Date()
        }
    }
}
