import Foundation
import QuillCodeAgent
import QuillCodeCore

extension QuillCodeWorkspaceModel {
    public func setMode(_ mode: AgentMode) {
        WorkspaceConfigurationEngine.setMode(mode, config: &root.config)
        mutateSelectedThread { thread in
            WorkspaceConfigurationEngine.setMode(mode, thread: &thread)
        }
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
    }

    /// Requests that the message composer grab focus (the `focus-composer` / Cmd+L command).
    /// Focus is view-layer `FocusState`, so the model can't set it directly — it bumps a token
    /// the rendered surface carries, and the view focuses the input when the token changes.
    @discardableResult
    public func focusComposer() -> Bool {
        composer.focusToken &+= 1
        return true
    }

    /// Advances to the next approval mode, mirroring Codex's `Shift+Tab` shortcut. The ring order
    /// matches the top-bar picker and the harness mode pill: Auto → Plan → Review → Read-only → Auto.
    @discardableResult
    public func cycleMode() -> Bool {
        let current = selectedThread?.mode ?? root.config.mode
        let order = AgentMode.cycleOrder
        let index = order.firstIndex(of: current) ?? 0
        setMode(order[(index + 1) % order.count])
        return true
    }

    @discardableResult
    public func setModel(_ model: String) -> String {
        // A confidential thread's model is pinned to the E2E-encrypted route for its lifetime: a model
        // switch would silently break the privacy promise the mode advertises, so the gesture is a
        // no-op (the picker renders locked, but the slash/palette paths land here too). The workspace
        // DEFAULT is deliberately left untouched as well — a change made from inside a confidential
        // chat should not quietly reconfigure future normal chats.
        if let thread = selectedThread, thread.runtimeContext.isConfidential {
            return thread.model
        }
        let modelID = WorkspaceConfigurationEngine.setModel(model, config: &root.config)
        mutateSelectedThread { thread in
            WorkspaceConfigurationEngine.setModelID(modelID, thread: &thread)
        }
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return modelID
    }

    @discardableResult
    public func setPersonality(_ personality: QuillCodePersonality) -> Bool {
        if selectedThread == nil {
            _ = newChat()
        }
        guard let thread = selectedThread,
              WorkspaceConfigurationEngine.modelSupportsPersonality(
                  thread.model,
                  catalog: root.modelCatalog
              )
        else {
            return false
        }
        mutateSelectedThread { thread in
            WorkspaceConfigurationEngine.setPersonality(personality, thread: &thread)
        }
        return true
    }

    public func toggleModelFavorite(_ model: String) {
        guard WorkspaceConfigurationEngine.toggleFavorite(model, config: &root.config) else { return }
        refreshTopBar(agentStatus: root.topBar.agentStatus)
    }

    public func setKeyboardShortcutPreferences(_ preferences: KeyboardShortcutPreferences) {
        root.config.keyboardShortcuts = preferences
    }

    public func setModelCatalog(_ models: [ModelInfo]) {
        guard let catalog = WorkspaceConfigurationEngine.normalizedCatalog(from: models) else { return }
        root.modelCatalog = catalog
        root.modelCatalogStatus = .bundled
    }

    public func setModelCatalog(_ catalog: TrustedRouterModelCatalog) {
        guard let models = WorkspaceConfigurationEngine.normalizedCatalog(from: catalog.models) else { return }
        root.modelCatalog = models
        root.modelCatalogStatus = catalog.status
    }

    public func setTrustedRouterCredits(_ state: TrustedRouterCreditsState) {
        root.trustedRouterCredits = state
    }

    public func applyTrustedRouterCreditsRefresh(
        _ result: TrustedRouterCreditsRefreshResult,
        previous: TrustedRouterCreditsState
    ) {
        switch result {
        case .unavailable:
            root.trustedRouterCredits = .unavailable
        case .success(let snapshot):
            root.trustedRouterCredits = .current(snapshot)
        case .failure(let attemptedAt, let message):
            root.trustedRouterCredits = .failed(
                previous: previous,
                attemptedAt: attemptedAt,
                message: message
            )
        }
    }

    public func applySettings(config: AppConfig, trustedRouterAPIKeyConfigured: Bool) {
        WorkspaceConfigurationEngine.applySettings(
            config,
            trustedRouterAPIKeyConfigured: trustedRouterAPIKeyConfigured,
            root: &root
        )
        mutateSelectedThread { thread in
            WorkspaceConfigurationEngine.syncThread(&thread, to: config)
        }
        enforceManagedWorktreeRetention()
        refreshTopBar(agentStatus: root.topBar.agentStatus)
    }

    public func applyRuntime(_ runtime: QuillCodeRuntime) {
        runner = runtime.runner
        contextSummaryGenerator = runtime.contextSummaryGenerator
        retryEventChannel = runtime.retryChannel
        refreshTopBar(agentStatus: runtime.statusLabel)
    }

    public func setAgentStatus(_ status: String, lastError: String? = nil) {
        setLastError(lastError)
        refreshTopBar(agentStatus: status)
    }
}
