import Foundation
import QuillCodeCore
import QuillCodeTools

enum WorkspaceProjectMetadataLoader {
    static func loadLocal(from projectRoot: URL) -> WorkspaceProjectMetadata {
        let root = projectRoot.standardizedFileURL
        return WorkspaceProjectMetadata(
            instructions: ProjectInstructionLoader.load(from: root),
            localActions: LocalEnvironmentActionLoader.load(from: root),
            extensionManifests: ProjectExtensionManifestLoader.load(from: root),
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
