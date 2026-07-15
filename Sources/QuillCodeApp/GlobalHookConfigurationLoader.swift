import Foundation
import QuillCodeCore
import QuillCodePersistence

public struct WorkspaceGlobalHookConfiguration: Sendable, Hashable {
    public var hooks: [ProjectPluginHook]
    public var hooksEnabled: Bool
    public var managedOnly: Bool

    public init(
        hooks: [ProjectPluginHook] = [],
        hooksEnabled: Bool = true,
        managedOnly: Bool = false
    ) {
        self.hooks = hooks
        self.hooksEnabled = hooksEnabled
        self.managedOnly = managedOnly
    }

    func resolvingTrust(_ trust: ProjectHookTrustLoadResult) -> WorkspaceGlobalHookConfiguration {
        var resolved = self
        resolved.hooks = ProjectPluginHookResolver.resolve(hooks, trust: trust)
        return resolved
    }
}

/// Loads additive global hooks in deterministic low-to-high configuration order.
/// System and requirements sources are managed; user sources retain exact-definition review.
enum GlobalHookConfigurationLoader {
    static let maxHooks = 192

    static func load(from paths: HookConfigurationPaths) -> WorkspaceGlobalHookConfiguration {
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
        let merged = ordinary.hooks + managed.hooks
        return WorkspaceGlobalHookConfiguration(
            hooks: hooksEnabled
                ? merged.filter { !managedOnly || $0.isManaged }
                : [],
            hooksEnabled: hooksEnabled,
            managedOnly: managedOnly
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
            to: &documents
        )
        appendLayer(
            paths.systemQuillCodeDirectory,
            id: "system-quillcode",
            name: "QuillCode system hooks",
            displayPrefix: "/etc/quillcode",
            trustScope: .managed,
            to: &documents
        )
        appendLayer(
            paths.userCodexDirectory,
            id: "user-codex",
            name: "Codex user hooks",
            displayPrefix: "~/.codex",
            trustScope: .user,
            to: &documents
        )
        appendLayer(
            paths.userQuillCodeDirectory,
            id: "user-quillcode",
            name: "QuillCode user hooks",
            displayPrefix: "~/.quillcode",
            trustScope: .user,
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
                    trustScope: .managed
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
                trustScope: trustScope
            ),
            readsActivationPolicy: readsActivationPolicy
        )
    }
}
