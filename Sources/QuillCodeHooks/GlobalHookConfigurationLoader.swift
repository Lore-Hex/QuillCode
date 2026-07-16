import Foundation
import QuillCodeCore
import QuillCodePersistence

public struct WorkspaceGlobalHookConfiguration: Sendable, Hashable {
    public var hooks: [ProjectPluginHook]
    public var definitions: [HookCatalogDefinition]
    public var hookStates: [String: HookConfigurationState]
    public var hooksEnabled: Bool
    public var hooksFeatureIsManaged: Bool
    public var managedOnly: Bool
    public var warnings: [String]
    public var diagnostics: [HookConfigurationDiagnostic]

    public init(
        hooks: [ProjectPluginHook] = [],
        definitions: [HookCatalogDefinition] = [],
        hookStates: [String: HookConfigurationState] = [:],
        hooksEnabled: Bool = true,
        hooksFeatureIsManaged: Bool = false,
        managedOnly: Bool = false,
        warnings: [String] = [],
        diagnostics: [HookConfigurationDiagnostic] = []
    ) {
        self.hooks = hooks
        self.definitions = definitions
        self.hookStates = hookStates
        self.hooksEnabled = hooksEnabled
        self.hooksFeatureIsManaged = hooksFeatureIsManaged
        self.managedOnly = managedOnly
        self.warnings = warnings
        self.diagnostics = diagnostics
    }

    public func resolvingTrust(_ trust: ProjectHookTrustLoadResult) -> WorkspaceGlobalHookConfiguration {
        var resolved = self
        resolved.hooks = ProjectPluginHookResolver.resolve(hooks, trust: trust)
        return resolved
    }
}

/// Loads additive global hooks in deterministic low-to-high configuration order.
/// System and requirements sources are managed; user sources retain exact-definition review.
public enum GlobalHookConfigurationLoader {
    public static let maxHooks = 192

    public static func load(from paths: HookConfigurationPaths) -> WorkspaceGlobalHookConfiguration {
        let managed = CodexHookDocumentLoader.load(
            managedDocuments(from: paths),
            maxHooks: maxHooks
        )
        let ordinary = CodexHookDocumentLoader.load(
            ordinaryDocuments(from: paths),
            maxHooks: max(0, maxHooks - managed.hooks.count)
        )
        let hooksEnabled = managed.hooksFeatureOverride
            ?? ordinary.hooksFeatureOverride
            ?? true
        let managedOnly = managed.allowManagedHooksOnly ?? false
        let mergedDefinitions = ordinary.definitions + managed.definitions
        let selectedDefinitions = mergedDefinitions.filter { !managedOnly || $0.hook.isManaged }
        var hookStates = ordinary.hookStates
        for (key, state) in managed.hookStates {
            hookStates[key] = state
        }
        return WorkspaceGlobalHookConfiguration(
            hooks: hooksEnabled ? selectedDefinitions.map(\.hook) : [],
            definitions: selectedDefinitions,
            hookStates: hookStates,
            hooksEnabled: hooksEnabled,
            hooksFeatureIsManaged: managed.hooksFeatureOverride != nil,
            managedOnly: managedOnly,
            warnings: ordinary.warnings + managed.warnings,
            diagnostics: ordinary.diagnostics + managed.diagnostics
        )
    }

    private static func ordinaryDocuments(from paths: HookConfigurationPaths) -> [CodexHookDocument] {
        var documents: [CodexHookDocument] = []
        appendLayer(
            paths.systemCodexDirectory,
            id: "system-codex",
            name: "Codex system hooks",
            displayPrefix: "/etc/codex",
            trustScope: .managed,
            catalogSource: .system,
            to: &documents
        )
        appendLayer(
            paths.systemQuillCodeDirectory,
            id: "system-quillcode",
            name: "QuillCode system hooks",
            displayPrefix: "/etc/quillcode",
            trustScope: .managed,
            catalogSource: .system,
            to: &documents
        )
        appendLayer(
            paths.userCodexDirectory,
            id: "user-codex",
            name: "Codex user hooks",
            displayPrefix: "~/.codex",
            trustScope: .user,
            catalogSource: .user,
            to: &documents
        )
        appendLayer(
            paths.userQuillCodeDirectory,
            id: "user-quillcode",
            name: "QuillCode user hooks",
            displayPrefix: "~/.quillcode",
            trustScope: .user,
            catalogSource: .user,
            to: &documents
        )
        return documents
    }

    private static func managedDocuments(from paths: HookConfigurationPaths) -> [CodexHookDocument] {
        paths.managedRequirementFiles.enumerated().map { index, file in
            let sourceID = "managed-requirements-\(index)"
            return CodexHookDocument(
                root: file.deletingLastPathComponent(),
                fileName: file.lastPathComponent,
                format: .toml,
                source: CodexHookDefinitionSource(
                    idPrefix: "managed_hook:\(sourceID)",
                    ownerID: "hook-source:\(sourceID)",
                    ownerName: "Managed requirements",
                    relativePath: file.path,
                    pluginRootRelativePath: nil,
                    trustScope: .managed,
                    catalogSource: .cloudRequirements
                ),
                readsActivationPolicy: true
            )
        }
    }

    private static func appendLayer(
        _ root: URL?,
        id: String,
        name: String,
        displayPrefix: String,
        trustScope: ProjectHookTrustScope,
        catalogSource: HookCatalogSource,
        to documents: inout [CodexHookDocument]
    ) {
        guard let root else { return }
        documents.append(document(
            root: root,
            fileName: "hooks.json",
            sourceID: "\(id)-json",
            ownerName: name,
            displayPath: "\(displayPrefix)/hooks.json",
            format: .json,
            trustScope: trustScope,
            catalogSource: catalogSource,
            readsActivationPolicy: false
        ))
        documents.append(document(
            root: root,
            fileName: "config.toml",
            sourceID: "\(id)-config",
            ownerName: name,
            displayPath: "\(displayPrefix)/config.toml",
            format: .toml,
            trustScope: trustScope,
            catalogSource: catalogSource,
            readsActivationPolicy: true
        ))
    }

    private static func document(
        root: URL,
        fileName: String,
        sourceID: String,
        ownerName: String,
        displayPath: String,
        format: CodexHookDocumentFormat,
        trustScope: ProjectHookTrustScope,
        catalogSource: HookCatalogSource,
        readsActivationPolicy: Bool
    ) -> CodexHookDocument {
        CodexHookDocument(
            root: root,
            fileName: fileName,
            format: format,
            source: CodexHookDefinitionSource(
                idPrefix: "global_hook:\(sourceID)",
                ownerID: "hook-source:\(sourceID)",
                ownerName: ownerName,
                relativePath: displayPath,
                pluginRootRelativePath: nil,
                trustScope: trustScope,
                catalogSource: catalogSource
            ),
            readsActivationPolicy: readsActivationPolicy
        )
    }
}
