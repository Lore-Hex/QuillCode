import Foundation
import QuillCodeCore
import QuillCodeTools

enum WorkspaceProjectMetadataLoader {
    static func loadLocal(from projectRoot: URL) -> WorkspaceProjectMetadata {
        let root = projectRoot.standardizedFileURL
        let installedManifests = ProjectExtensionManifestLoader.load(from: root)
        let marketplaceManifests = ProjectExtensionManifestLoader.loadMarketplace(
            from: root,
            installedManifests: installedManifests
        )
        let bundledMarketplaceManifests = BundledExtensionMarketplace.availableManifests(
            excluding: installedManifests + marketplaceManifests
        )
        return WorkspaceProjectMetadata(
            instructions: ProjectInstructionLoader.load(from: root),
            localActions: LocalEnvironmentActionLoader.load(from: root),
            extensionManifests: installedManifests + marketplaceManifests + bundledMarketplaceManifests,
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
            extensionManifests: [],
            memories: context.memories
        )
    }
}
