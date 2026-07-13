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
        let modelID = WorkspaceConfigurationEngine.setModel(model, config: &root.config)
        mutateSelectedThread { thread in
            WorkspaceConfigurationEngine.setModelID(modelID, thread: &thread)
        }
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return modelID
    }

    public func toggleModelFavorite(_ model: String) {
        guard WorkspaceConfigurationEngine.toggleFavorite(model, config: &root.config) else { return }
        refreshTopBar(agentStatus: root.topBar.agentStatus)
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
