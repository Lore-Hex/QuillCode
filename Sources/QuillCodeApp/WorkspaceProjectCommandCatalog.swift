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

    static func extensionUpdateCommands(
        manifests: [ProjectExtensionManifest],
        hasActiveWorkspaceRoot: Bool
    ) -> [WorkspaceCommandSurface] {
        manifests
            .filter { $0.updateCommand != nil }
            .map { manifest in
                WorkspaceCommandSurface(
                    id: "extension-update:\(manifest.id)",
                    title: "Update \(manifest.name)",
                    category: WorkspaceCommandPalette.extensionsCategory,
                    keywords: extensionUpdateKeywords(for: manifest),
                    isEnabled: hasActiveWorkspaceRoot
                )
            }
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

    private static func extensionUpdateKeywords(for manifest: ProjectExtensionManifest) -> [String] {
        [
            "extension",
            "plugin",
            "skill",
            "mcp",
            "update",
            manifest.kind.title,
            manifest.name,
            manifest.version ?? "",
            manifest.sourceURL ?? ""
        ].filter { !$0.isEmpty }
    }
}
