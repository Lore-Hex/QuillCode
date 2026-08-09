import QuillCodeCore

public enum WorkspaceSettingsPersistenceKind: CaseIterable, Hashable, Sendable {
    case configuration
    case trustedRouterCredential

    var label: String {
        switch self {
        case .configuration:
            "Configuration"
        case .trustedRouterCredential:
            "TrustedRouter credential"
        }
    }
}

public enum WorkspaceTrustedRouterCredentialMutation: Sendable {
    case unchanged
    case replace(String)
    case clear

    public var changesCredential: Bool {
        switch self {
        case .unchanged:
            false
        case .replace, .clear:
            true
        }
    }
}

public struct WorkspaceSettingsPersistenceError: Error, CustomStringConvertible, Sendable {
    public let failedKinds: Set<WorkspaceSettingsPersistenceKind>
    public let rollbackFailed: Bool

    public init(
        failedKinds: Set<WorkspaceSettingsPersistenceKind>,
        rollbackFailed: Bool
    ) {
        self.failedKinds = failedKinds
        self.rollbackFailed = rollbackFailed
    }

    public var description: String {
        "Quill Cowork could not safely save the settings change."
    }
}

struct WorkspaceSettingsPersistenceTransaction {
    var saveConfiguration: (AppConfig) throws -> Void
    var readCredential: () throws -> String?
    var writeCredential: (String) throws -> Void
    var clearCredential: () throws -> Void

    func apply(
        currentConfig: AppConfig,
        proposedConfig: AppConfig,
        credentialMutation: WorkspaceTrustedRouterCredentialMutation
    ) throws {
        guard credentialMutation.changesCredential else {
            do {
                try saveConfiguration(proposedConfig)
            } catch {
                throw WorkspaceSettingsPersistenceError(
                    failedKinds: [.configuration],
                    rollbackFailed: false
                )
            }
            return
        }

        let priorCredential: String?
        do {
            priorCredential = try readCredential()
        } catch {
            throw failure(
                currentConfig: currentConfig,
                proposedConfig: proposedConfig,
                rollbackFailed: false
            )
        }

        do {
            try applyCredentialMutation(credentialMutation)
        } catch {
            let rollbackFailed = !restoreCredential(priorCredential)
            throw failure(
                currentConfig: currentConfig,
                proposedConfig: proposedConfig,
                rollbackFailed: rollbackFailed
            )
        }

        do {
            try saveConfiguration(proposedConfig)
        } catch {
            let rollbackFailed = !restoreCredential(priorCredential)
            throw WorkspaceSettingsPersistenceError(
                failedKinds: [.configuration, .trustedRouterCredential],
                rollbackFailed: rollbackFailed
            )
        }
    }

    private func applyCredentialMutation(
        _ mutation: WorkspaceTrustedRouterCredentialMutation
    ) throws {
        switch mutation {
        case .unchanged:
            break
        case .replace(let credential):
            try writeCredential(credential)
        case .clear:
            try clearCredential()
        }
    }

    private func restoreCredential(_ credential: String?) -> Bool {
        do {
            if let credential {
                try writeCredential(credential)
            } else {
                try clearCredential()
            }
            return true
        } catch {
            return false
        }
    }

    private func failure(
        currentConfig: AppConfig,
        proposedConfig: AppConfig,
        rollbackFailed: Bool
    ) -> WorkspaceSettingsPersistenceError {
        var kinds: Set<WorkspaceSettingsPersistenceKind> = [.trustedRouterCredential]
        if proposedConfig != currentConfig {
            kinds.insert(.configuration)
        }
        return WorkspaceSettingsPersistenceError(
            failedKinds: kinds,
            rollbackFailed: rollbackFailed
        )
    }
}
