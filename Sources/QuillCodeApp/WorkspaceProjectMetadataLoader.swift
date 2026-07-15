import Foundation
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools

enum WorkspaceProjectMetadataLoader {
    static func loadLocal(
        from projectRoot: URL,
        hookTrustStore: ProjectHookTrustFileStore? = nil
    ) -> WorkspaceProjectMetadata {
        let root = projectRoot.standardizedFileURL
        let configuration = WorkspaceProjectConfigurationLoader.load(from: root)
        let installed = ProjectExtensionManifestLoader.discover(from: root)
        let installedManifests = installed.manifests
        let pluginHooks = ProjectPluginHookResolver.resolve(
            installed.pluginHooks + ProjectHookConfigurationLoader.load(from: root),
            trust: hookTrustStore?.load(forWorkspaceRoot: root) ?? ProjectHookTrustLoadResult()
        )
        let marketplaceManifests = ProjectExtensionManifestLoader.loadMarketplace(
            from: root,
            installedManifests: installedManifests
        )
        let standardMarketplaceManifests = CodexPluginMarketplaceLoader.load(
            from: root,
            installedManifests: installedManifests + marketplaceManifests
        )
        let bundledMarketplaceManifests = BundledExtensionMarketplace.availableManifests(
            excluding: installedManifests + marketplaceManifests + standardMarketplaceManifests
        )
        return WorkspaceProjectMetadata(
            instructions: ProjectInstructionLoader.load(from: root),
            localActions: LocalEnvironmentActionLoader.load(
                from: root,
                directories: configuration.localActionDirectories,
                maxActions: configuration.maxLocalActions
            ),
            runHooks: ProjectRunHookLoader.load(
                from: root,
                beforeAgentRunDirectories: configuration.beforeAgentRunHookDirectories,
                afterAgentRunDirectories: configuration.afterAgentRunHookDirectories,
                maxHooks: configuration.maxRunHooks
            ) + ProjectPluginHookResolver.executableRunHooks(from: pluginHooks),
            pluginHooks: pluginHooks,
            extensionManifests: installedManifests
                + marketplaceManifests
                + standardMarketplaceManifests
                + bundledMarketplaceManifests,
            memories: MemoryNoteLoader.loadProject(from: root)
        )
    }

    static func loadRemote(
        connection: ProjectConnection,
        executor: SSHRemoteShellExecutor
    ) throws -> WorkspaceProjectMetadata {
        metadata(from: try SSHRemoteProjectContextLoader.load(
            connection: connection,
            executor: executor
        ))
    }

    static func metadata(from context: SSHRemoteProjectContext) -> WorkspaceProjectMetadata {
        WorkspaceProjectMetadata(
            instructions: context.instructions,
            localActions: [],
            runHooks: context.runHooks,
            pluginHooks: [],
            extensionManifests: [],
            memories: context.memories
        )
    }
}
