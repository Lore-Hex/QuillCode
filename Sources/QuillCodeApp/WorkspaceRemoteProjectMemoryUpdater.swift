import Foundation
import QuillCodeCore
import QuillCodeTools

enum WorkspaceRemoteProjectMemoryUpdater {
    static func update(
        id: String,
        content rawContent: String,
        project: ProjectRef,
        executor: SSHRemoteShellExecutor
    ) throws -> [MemoryNote] {
        guard project.isRemote else {
            throw WorkspaceRemoteProjectMemoryUpdateError.invalidConnection
        }

        let relativePath = try WorkspaceRemoteProjectMemoryTarget.relativePath(from: id, knownMemories: project.memories)
        let content = try MemoryNoteLoader.validatedUpdateContent(rawContent)
        try writeRemoteMemory(content: content, relativePath: relativePath, connection: project.connection, executor: executor)

        do {
            return try WorkspaceProjectMetadataLoader.loadRemote(connection: project.connection, executor: executor).memories
        } catch {
            throw WorkspaceRemoteProjectMemoryUpdateError.refreshFailed(WorkspaceMemoryErrorMessageBuilder.userFacingMessage(for: error))
        }
    }

    private static func writeRemoteMemory(
        content: String,
        relativePath: String,
        connection: ProjectConnection,
        executor: SSHRemoteShellExecutor
    ) throws {
        let encoded = Data(content.appending("\n").utf8).base64EncodedString()
        let quotedPath = WorkspaceTerminalSessionAdapter.shellSingleQuoted(relativePath)
        let command = [
            "test -f \(quotedPath)",
            "test ! -L \(quotedPath)",
            "printf %s \(WorkspaceTerminalSessionAdapter.shellSingleQuoted(encoded)) | base64 --decode > \(quotedPath)",
            "printf 'Updated %s\\n' \(quotedPath)"
        ].joined(separator: " && ")

        try WorkspaceRemoteProjectMemoryCommandRunner.run(
            command,
            connection: connection,
            executor: executor,
            failure: WorkspaceRemoteProjectMemoryUpdateError.updateFailed
        )
    }
}

enum WorkspaceRemoteProjectMemoryDeleter {
    static func delete(
        id: String,
        project: ProjectRef,
        executor: SSHRemoteShellExecutor
    ) throws -> (deleted: MemoryNote, updatedMemories: [MemoryNote]) {
        guard project.isRemote else {
            throw WorkspaceRemoteProjectMemoryUpdateError.invalidConnection
        }
        let deleted = try WorkspaceRemoteProjectMemoryTarget.note(for: id, knownMemories: project.memories)
        let relativePath = try WorkspaceRemoteProjectMemoryTarget.relativePath(from: id, knownMemories: project.memories)
        try deleteRemoteMemory(relativePath: relativePath, connection: project.connection, executor: executor)

        do {
            return (
                deleted: deleted,
                updatedMemories: try WorkspaceProjectMetadataLoader.loadRemote(
                    connection: project.connection,
                    executor: executor
                ).memories
            )
        } catch {
            throw WorkspaceRemoteProjectMemoryUpdateError.refreshFailed(WorkspaceMemoryErrorMessageBuilder.userFacingMessage(for: error))
        }
    }

    private static func deleteRemoteMemory(
        relativePath: String,
        connection: ProjectConnection,
        executor: SSHRemoteShellExecutor
    ) throws {
        let quotedPath = WorkspaceTerminalSessionAdapter.shellSingleQuoted(relativePath)
        let command = [
            "test -f \(quotedPath)",
            "test ! -L \(quotedPath)",
            "rm \(quotedPath)",
            "printf 'Deleted %s\\n' \(quotedPath)"
        ].joined(separator: " && ")

        try WorkspaceRemoteProjectMemoryCommandRunner.run(
            command,
            connection: connection,
            executor: executor,
            failure: WorkspaceRemoteProjectMemoryUpdateError.deleteFailed
        )
    }
}
