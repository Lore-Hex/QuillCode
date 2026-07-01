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

        let relativePath = try WorkspaceRemoteProjectMemoryTarget.relativePath(
            from: id,
            knownMemories: project.memories
        )
        let content = try MemoryNoteLoader.validatedUpdateContent(rawContent)
        try WorkspaceRemoteProjectMemoryCommand.write(
            content: content,
            relativePath: relativePath,
            connection: project.connection,
            executor: executor
        )

        return try WorkspaceRemoteProjectMemoryRefresh.memories(
            connection: project.connection,
            executor: executor
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
        let relativePath = try WorkspaceRemoteProjectMemoryTarget.relativePath(
            from: id,
            knownMemories: project.memories
        )
        try WorkspaceRemoteProjectMemoryCommand.delete(
            relativePath: relativePath,
            connection: project.connection,
            executor: executor
        )

        return (
            deleted: deleted,
            updatedMemories: try WorkspaceRemoteProjectMemoryRefresh.memories(
                connection: project.connection,
                executor: executor
            )
        )
    }
}

private enum WorkspaceRemoteProjectMemoryRefresh {
    static func memories(
        connection: ProjectConnection,
        executor: SSHRemoteShellExecutor
    ) throws -> [MemoryNote] {
        do {
            return try WorkspaceProjectMetadataLoader
                .loadRemote(connection: connection, executor: executor)
                .memories
        } catch {
            throw WorkspaceRemoteProjectMemoryUpdateError.refreshFailed(
                WorkspaceMemoryErrorMessageBuilder.userFacingMessage(for: error)
            )
        }
    }
}

private enum WorkspaceRemoteProjectMemoryCommand {
    static func write(
        content: String,
        relativePath: String,
        connection: ProjectConnection,
        executor: SSHRemoteShellExecutor
    ) throws {
        let encoded = Data(content.appending("\n").utf8).base64EncodedString()
        let quotedPath = WorkspaceTerminalSessionAdapter.shellSingleQuoted(relativePath)
        try run(
            [
                "test -f \(quotedPath)",
                "test ! -L \(quotedPath)",
                "printf %s \(shellQuote(encoded)) | base64 --decode > \(quotedPath)",
                "printf 'Updated %s\\n' \(quotedPath)"
            ],
            connection: connection,
            executor: executor,
            failure: WorkspaceRemoteProjectMemoryUpdateError.updateFailed
        )
    }

    static func delete(
        relativePath: String,
        connection: ProjectConnection,
        executor: SSHRemoteShellExecutor
    ) throws {
        let quotedPath = WorkspaceTerminalSessionAdapter.shellSingleQuoted(relativePath)
        try run(
            [
                "test -f \(quotedPath)",
                "test ! -L \(quotedPath)",
                "rm \(quotedPath)",
                "printf 'Deleted %s\\n' \(quotedPath)"
            ],
            connection: connection,
            executor: executor,
            failure: WorkspaceRemoteProjectMemoryUpdateError.deleteFailed
        )
    }

    private static func run(
        _ commandParts: [String],
        connection: ProjectConnection,
        executor: SSHRemoteShellExecutor,
        failure: (String) -> WorkspaceRemoteProjectMemoryUpdateError
    ) throws {
        try WorkspaceRemoteProjectMemoryCommandRunner.run(
            commandParts.joined(separator: " && "),
            connection: connection,
            executor: executor,
            failure: failure
        )
    }

    private static func shellQuote(_ value: String) -> String {
        WorkspaceTerminalSessionAdapter.shellSingleQuoted(value)
    }
}
