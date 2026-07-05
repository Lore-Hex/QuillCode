import Foundation
import QuillCodeCore

enum WorkspaceProjectCommandCatalog {
    static func localActionCommands(
        actions: [LocalEnvironmentAction],
        hasActiveWorkspaceRoot: Bool
    ) -> [WorkspaceCommandSurface] {
        actions.map { action in
            WorkspaceCommandSurface(
                id: action.id,
                title: "Run \(action.title)",
                category: WorkspaceCommandPalette.environmentCategory,
                keywords: keywords(for: action),
                isEnabled: hasActiveWorkspaceRoot
            )
        }
    }

    static func mcpLifecycleCommands(
        manifests: [ProjectExtensionManifest],
        statuses: [String: MCPServerLifecycleStatus],
        hasActiveWorkspaceRoot: Bool
    ) -> [WorkspaceCommandSurface] {
        manifests
            .filter { $0.kind == .mcpServer }
            .flatMap { manifest -> [WorkspaceCommandSurface] in
                let status = statuses[manifest.id] ?? .stopped
                let canStart = manifest.isEnabled
                    && manifest.launchExecutable != nil
                    && !status.isActive
                    && hasActiveWorkspaceRoot
                return [
                    WorkspaceCommandSurface(
                        id: "mcp-start:\(manifest.id)",
                        title: "Start \(manifest.name)",
                        category: WorkspaceCommandPalette.extensionsCategory,
                        keywords: ["mcp", "server", "start", "stdio", manifest.name],
                        isEnabled: canStart
                    ),
                    WorkspaceCommandSurface(
                        id: "mcp-stop:\(manifest.id)",
                        title: "Stop \(manifest.name)",
                        category: WorkspaceCommandPalette.extensionsCategory,
                        keywords: ["mcp", "server", "stop", "stdio", manifest.name],
                        isEnabled: status.isActive
                    )
                ]
            }
    }

    static func mcpReferenceCommands(
        manifests: [ProjectExtensionManifest],
        statuses: [String: MCPServerLifecycleStatus],
        probeSummaries: [String: MCPServerProbeSummary],
        hasActiveWorkspaceRoot: Bool
    ) -> [WorkspaceCommandSurface] {
        manifests
            .filter { $0.kind == .mcpServer }
            .filter { manifest in
                manifest.isEnabled
                    && statuses[manifest.id] == .ready
                    && probeSummaries[manifest.id]?.errorMessage == nil
            }
            .flatMap { manifest -> [WorkspaceCommandSurface] in
                let summary = probeSummaries[manifest.id]
                return resourceCommands(
                    manifest: manifest,
                    resources: summary?.resourceNames ?? [],
                    uris: summary?.resourceURIs ?? [],
                    isEnabled: hasActiveWorkspaceRoot
                ) + promptCommands(
                    manifest: manifest,
                    prompts: summary?.promptNames ?? [],
                    isEnabled: hasActiveWorkspaceRoot
                )
            }
    }

    static func extensionUpdateCommands(
        manifests: [ProjectExtensionManifest],
        hasActiveWorkspaceRoot: Bool
    ) -> [WorkspaceCommandSurface] {
        extensionLifecycleCommands(
            manifests: manifests,
            action: .update,
            hasActiveWorkspaceRoot: hasActiveWorkspaceRoot
        )
    }

    static func extensionInstallCommands(
        manifests: [ProjectExtensionManifest],
        hasActiveWorkspaceRoot: Bool
    ) -> [WorkspaceCommandSurface] {
        extensionLifecycleCommands(
            manifests: manifests,
            action: .install,
            hasActiveWorkspaceRoot: hasActiveWorkspaceRoot
        )
    }

    private static func keywords(for action: LocalEnvironmentAction) -> [String] {
        let baseKeywords = [
            "local environment",
            "script"
        ] + [action.detail].compactMap { $0 } + [
            "bootstrap",
            action.title,
            action.relativePath
        ]
        let workingDirectoryKeywords = [action.workingDirectory].compactMap { $0 }
        let timeoutKeywords = action.timeoutSeconds.map { ["timeout", "\($0)s"] } ?? []
        let environmentKeywords = action.environment?.keys.sorted() ?? []
        return baseKeywords + workingDirectoryKeywords + timeoutKeywords + environmentKeywords
    }

    private static func extensionLifecycleCommands(
        manifests: [ProjectExtensionManifest],
        action: ExtensionLifecycleAction,
        hasActiveWorkspaceRoot: Bool
    ) -> [WorkspaceCommandSurface] {
        manifests
            .filter { action.command(for: $0) != nil }
            .map { manifest in
                WorkspaceCommandSurface(
                    id: "extension-\(action.rawValue):\(manifest.id)",
                    title: "\(action.title) \(manifest.name)",
                    category: WorkspaceCommandPalette.extensionsCategory,
                    keywords: extensionLifecycleKeywords(for: manifest, action: action),
                    isEnabled: hasActiveWorkspaceRoot
                )
            }
    }

    private static func extensionLifecycleKeywords(
        for manifest: ProjectExtensionManifest,
        action: ExtensionLifecycleAction
    ) -> [String] {
        [
            "extension",
            "plugin",
            "skill",
            "mcp",
            action.rawValue,
            manifest.kind.title,
            manifest.name,
            manifest.summary,
            manifest.version ?? "",
            manifest.sourceURL ?? ""
        ].filter { !$0.isEmpty }
    }

    private static func resourceCommands(
        manifest: ProjectExtensionManifest,
        resources: [String],
        uris: [String],
        isEnabled: Bool
    ) -> [WorkspaceCommandSurface] {
        resources.enumerated().map { index, name in
            WorkspaceCommandSurface(
                id: "mcp-resource:\(manifest.id):\(index)",
                title: "Read \(name)",
                category: WorkspaceCommandPalette.extensionsCategory,
                keywords: [
                    "mcp",
                    "resource",
                    "read",
                    manifest.name,
                    name,
                    uris.indices.contains(index) ? uris[index] : ""
                ].filter { !$0.isEmpty },
                isEnabled: isEnabled
            )
        }
    }

    private static func promptCommands(
        manifest: ProjectExtensionManifest,
        prompts: [String],
        isEnabled: Bool
    ) -> [WorkspaceCommandSurface] {
        prompts.enumerated().map { index, name in
            WorkspaceCommandSurface(
                id: "mcp-prompt:\(manifest.id):\(index)",
                title: "Use \(name)",
                category: WorkspaceCommandPalette.extensionsCategory,
                keywords: ["mcp", "prompt", "get", manifest.name, name],
                isEnabled: isEnabled
            )
        }
    }
}

private enum ExtensionLifecycleAction: String {
    case install
    case update

    var title: String {
        switch self {
        case .install:
            return "Install"
        case .update:
            return "Update"
        }
    }

    func command(for manifest: ProjectExtensionManifest) -> String? {
        switch self {
        case .install:
            return manifest.installCommand
        case .update:
            return manifest.updateCommand
        }
    }
}
