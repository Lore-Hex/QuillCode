import Foundation
import QuillCodeCore

enum WorkspaceRemoteProjectMemoryTarget {
    static func note(for id: String, knownMemories: [MemoryNote]) throws -> MemoryNote {
        guard let note = knownMemories.first(where: { $0.id == id && $0.scope == .project }) else {
            throw WorkspaceRemoteProjectMemoryUpdateError.missingKnownMemory
        }
        return note
    }

    static func relativePath(from id: String, knownMemories: [MemoryNote]) throws -> String {
        _ = try note(for: id, knownMemories: knownMemories)
        return try relativePath(from: id)
    }

    private static func relativePath(from id: String) throws -> String {
        let prefix = "\(MemoryScope.project.rawValue):"
        guard id.hasPrefix(prefix) else {
            throw WorkspaceRemoteProjectMemoryUpdateError.invalidMemoryID
        }

        let relativePath = try WorkspaceRemoteProjectPath.relativePath(String(id.dropFirst(prefix.count)))
        guard isProjectMemoryPath(relativePath) else {
            throw WorkspaceRemoteProjectMemoryUpdateError.invalidMemoryID
        }
        return relativePath
    }

    private static func isProjectMemoryPath(_ relativePath: String) -> Bool {
        let memoryPrefix = "\(MemoryNoteLoader.projectRelativeDirectory)/"
        guard relativePath.hasPrefix(memoryPrefix) else { return false }

        let filename = String(relativePath.dropFirst(memoryPrefix.count))
        guard !filename.isEmpty, !filename.contains("/") else { return false }

        let fileExtension = URL(fileURLWithPath: filename).pathExtension.lowercased()
        return MemoryNoteLoader.supportedExtensions.contains(fileExtension)
    }
}
