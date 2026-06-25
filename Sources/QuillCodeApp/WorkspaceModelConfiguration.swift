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
        refreshTopBar(agentStatus: root.topBar.agentStatus)
    }

    public func applyRuntime(_ runtime: QuillCodeRuntime) {
        runner = runtime.runner
        refreshTopBar(agentStatus: runtime.statusLabel)
    }

    public func setAgentStatus(_ status: String, lastError: String? = nil) {
        setLastError(lastError)
        refreshTopBar(agentStatus: status)
    }
}
