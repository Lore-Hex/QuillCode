import Foundation
import QuillCodeCore
import QuillCodeTools

enum WorkspaceRemoteProjectMemoryUpdateError: Error, Equatable, LocalizedError {
    case invalidMemoryID
    case missingKnownMemory
    case invalidConnection
    case updateFailed(String)
    case refreshFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidMemoryID:
            return "Remote project memory edits must target a loaded .quillcode/memories file."
        case .missingKnownMemory:
            return "Memory was not found in the selected remote project. Refresh context and try again."
        case .invalidConnection:
            return "SSH Remote project is missing a usable host."
        case .updateFailed(let message):
            return message
        case .refreshFailed(let message):
            return message
        }
    }
}

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
        guard project.memories.contains(where: { $0.id == id && $0.scope == .project }) else {
            throw WorkspaceRemoteProjectMemoryUpdateError.missingKnownMemory
        }

        let relativePath = try remoteMemoryPath(from: id)
        let content = try MemoryNoteLoader.validatedUpdateContent(rawContent)
        try writeRemoteMemory(content: content, relativePath: relativePath, connection: project.connection, executor: executor)

        do {
            return try WorkspaceProjectMetadataLoader.loadRemote(connection: project.connection, executor: executor).memories
        } catch {
            throw WorkspaceRemoteProjectMemoryUpdateError.refreshFailed(WorkspaceMemoryErrorMessageBuilder.userFacingMessage(for: error))
        }
    }

    private static func remoteMemoryPath(from id: String) throws -> String {
        let prefix = "\(MemoryScope.project.rawValue):"
        guard id.hasPrefix(prefix) else {
            throw WorkspaceRemoteProjectMemoryUpdateError.invalidMemoryID
        }
        let rawPath = String(id.dropFirst(prefix.count))
        let relativePath = try WorkspaceRemoteProjectPath.relativePath(rawPath)
        let memoryPrefix = "\(MemoryNoteLoader.projectRelativeDirectory)/"
        guard relativePath.hasPrefix(memoryPrefix) else {
            throw WorkspaceRemoteProjectMemoryUpdateError.invalidMemoryID
        }

        let filename = String(relativePath.dropFirst(memoryPrefix.count))
        guard !filename.isEmpty,
              !filename.contains("/"),
              MemoryNoteLoader.supportedExtensions.contains(URL(fileURLWithPath: filename).pathExtension.lowercased())
        else {
            throw WorkspaceRemoteProjectMemoryUpdateError.invalidMemoryID
        }
        return relativePath
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

        guard let request = executor.request(command: command, connection: connection) else {
            throw WorkspaceRemoteProjectMemoryUpdateError.invalidConnection
        }
        let result = ShellToolExecutor().run(request)
        guard result.ok else {
            let detail = result.error
                ?? [result.stderr, result.stdout]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first(where: { !$0.isEmpty })
                ?? "Remote project memory could not be updated."
            throw WorkspaceRemoteProjectMemoryUpdateError.updateFailed(detail)
        }
    }
}
