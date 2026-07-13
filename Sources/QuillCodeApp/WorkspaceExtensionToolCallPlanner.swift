import Foundation
import QuillCodeCore
import QuillCodeTools

enum WorkspaceExtensionToolCallPlanner {
    static func update(_ manifest: ProjectExtensionManifest) -> ToolCall? {
        WorkspaceShellToolCallPlanner.command(
            manifest.updateCommand,
            timeoutSeconds: manifest.updateTimeoutSeconds
        )
    }

    static func install(_ manifest: ProjectExtensionManifest) -> ToolCall? {
        guard let source = manifest.localInstallSourceRelativePath else {
            return WorkspaceShellToolCallPlanner.command(
                manifest.installCommand,
                timeoutSeconds: manifest.installTimeoutSeconds
            )
        }
        let pluginName = manifest.id.hasPrefix("plugin:")
            ? String(manifest.id.dropFirst("plugin:".count))
            : manifest.id
        return ToolCall(
            name: ToolDefinition.localPluginInstall.name,
            argumentsJSON: ToolArguments.json([
                "source": source,
                "pluginName": pluginName
            ])
        )
    }
}
