import QuillCodeCore

struct WorkspaceConfigurationEngine {
    @discardableResult
    static func setModel(_ model: String, config: inout AppConfig) -> String {
        let modelID = TrustedRouterDefaults.normalizedDefaultModelID(model)
        config.defaultModel = modelID
        return modelID
    }

    static func setModelID(_ modelID: String, thread: inout ChatThread) {
        thread.model = TrustedRouterDefaults.normalizedDefaultModelID(modelID)
    }

    static func setMode(_ mode: AgentMode, config: inout AppConfig) {
        config.mode = mode
    }

    static func setMode(_ mode: AgentMode, thread: inout ChatThread) {
        thread.mode = mode
    }

    static func setPersonality(_ personality: QuillCodePersonality, thread: inout ChatThread) {
        thread.personality = personality
    }

    static func modelSupportsPersonality(_ modelID: String, catalog: [ModelInfo]) -> Bool {
        let canonicalID = TrustedRouterDefaults.canonicalModelID(modelID)
        return catalog.first {
            TrustedRouterDefaults.canonicalModelID($0.id) == canonicalID
        }?.supportsPersonality ?? true
    }

    @discardableResult
    static func toggleFavorite(_ model: String, config: inout AppConfig) -> Bool {
        let modelID = TrustedRouterDefaults.canonicalModelID(model)
        guard !modelID.isEmpty else { return false }

        var favoriteModels = config.favoriteModels
        if let index = favoriteModels.firstIndex(of: modelID) {
            favoriteModels.remove(at: index)
        } else {
            favoriteModels.append(modelID)
        }
        config.favoriteModels = AppConfig(favoriteModels: favoriteModels).favoriteModels
        return true
    }

    static func normalizedCatalog(from models: [ModelInfo]) -> [ModelInfo]? {
        guard !models.isEmpty else { return nil }
        return TrustedRouterDefaults.normalizedModelCatalog(models)
    }

    static func applySettings(
        _ config: AppConfig,
        trustedRouterAPIKeyConfigured: Bool,
        root: inout QuillCodeRootState
    ) {
        root.config = config
        root.trustedRouterAPIKeyConfigured = trustedRouterAPIKeyConfigured
    }

    static func syncThread(_ thread: inout ChatThread, to config: AppConfig) {
        thread.mode = config.mode
        // Saving Settings (even an unrelated option) must not overwrite a confidential thread's model:
        // the picker renders locked, and silently retargeting the next send at config.defaultModel
        // would defeat the advertised E2E pin.
        guard !thread.runtimeContext.isConfidential else { return }
        thread.model = config.defaultModel
    }
}
