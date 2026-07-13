import Foundation
import QuillCodeCore
import QuillCodeTools

enum WorkspaceProjectMetadataLoader {
    static func loadLocal(from projectRoot: URL) -> WorkspaceProjectMetadata {
        let root = projectRoot.standardizedFileURL
        let configuration = WorkspaceProjectConfigurationLoader.load(from: root)
        let installedManifests = ProjectExtensionManifestLoader.load(from: root)
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
            ),
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
            extensionManifests: [],
            memories: context.memories
        )
    }
}
