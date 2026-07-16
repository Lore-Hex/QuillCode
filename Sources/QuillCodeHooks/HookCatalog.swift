import Foundation
import QuillCodeCore
import QuillCodePersistence

/// Stable source labels shared by hook discovery, execution surfaces, and app-server projection.
public enum HookCatalogSource: String, Codable, Sendable, Hashable {
    case system
    case user
    case project
    case mdm
    case sessionFlags
    case plugin
    case cloudRequirements
    case cloudManagedConfig
    case legacyManagedConfigFile
    case legacyManagedConfigMdm
    case unknown
}

public enum HookCatalogTrustStatus: String, Codable, Sendable, Hashable {
    case managed
    case untrusted
    case trusted
    case modified
}

public struct HookConfigurationDiagnostic: Sendable, Hashable {
    public var path: String
    public var message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }

    public var description: String {
        "\(message): \(path)"
    }
}

public struct HookConfigurationState: Sendable, Hashable {
    public var enabled: Bool?
    public var trustedHash: String?

    public init(enabled: Bool? = nil, trustedHash: String? = nil) {
        self.enabled = enabled
        self.trustedHash = trustedHash
    }
}

/// A discovered hook plus the source identity needed for stable trust and protocol projection.
/// Discovery is data-only; this type never evaluates or executes the command.
public struct HookCatalogDefinition: Sendable, Hashable {
    public var hook: ProjectPluginHook
    public var key: String
    public var sourcePath: URL
    public var source: HookCatalogSource
    public var pluginID: String?

    public init(
        hook: ProjectPluginHook,
        key: String,
        sourcePath: URL,
        source: HookCatalogSource,
        pluginID: String? = nil
    ) {
        self.hook = hook
        self.key = key
        self.sourcePath = sourcePath
        self.source = source
        self.pluginID = pluginID
    }
}

public struct HookCatalogEntry: Sendable, Hashable {
    public var definition: HookCatalogDefinition
    public var displayOrder: Int
    public var enabled: Bool
    public var trustStatus: HookCatalogTrustStatus

    public init(
        definition: HookCatalogDefinition,
        displayOrder: Int,
        enabled: Bool,
        trustStatus: HookCatalogTrustStatus
    ) {
        self.definition = definition
        self.displayOrder = displayOrder
        self.enabled = enabled
        self.trustStatus = trustStatus
    }

    public var isManaged: Bool {
        definition.hook.isManaged
    }
}

public enum HookCatalogResolver {
    public static func resolve(
        _ definitions: [HookCatalogDefinition],
        states: [String: HookConfigurationState] = [:],
        trust: ProjectHookTrustLoadResult = ProjectHookTrustLoadResult(),
        displayOrderOffset: Int = 0
    ) -> [HookCatalogEntry] {
        var entries: [HookCatalogEntry] = []
        entries.reserveCapacity(definitions.count)

        for definition in definitions {
            let hook = definition.hook
            guard hook.supportStatus.isSupported else { continue }
            let state = states[definition.key]
            let managed = hook.isManaged
            let enabled = managed
                || state?.enabled == true
                || (state?.enabled == nil && trust.status(for: hook) != .disabled)
            let status: HookCatalogTrustStatus
            if managed {
                status = .managed
            } else if let trustedHash = state?.trustedHash {
                status = trustedHash == hook.definitionHash ? .trusted : .modified
            } else {
                status = trust.status(for: hook) == .trusted ? .trusted : .untrusted
            }
            entries.append(HookCatalogEntry(
                definition: definition,
                displayOrder: displayOrderOffset + entries.count,
                enabled: enabled,
                trustStatus: status
            ))
        }

        return entries
    }
}
