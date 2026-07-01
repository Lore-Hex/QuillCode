import Foundation
import QuillCodeCore
import QuillCodeTools

struct WorkspaceMemoryMutation: Sendable, Equatable {
    let transcript: WorkspaceLocalCommandTranscript
    let updatedGlobalMemories: [MemoryNote]?
    let updatedProjectMemories: [MemoryNote]?
    let noticeSummary: String?
    let noticeRelativePath: String?

    var changedContext: Bool {
        noticeSummary != nil && noticeRelativePath != nil
    }
}

enum WorkspaceMemoryEngine {
    static func loadGlobal(from directory: URL?) -> [MemoryNote] {
        guard let directory else { return [] }
        return MemoryNoteLoader.loadGlobal(from: directory)
    }

    static func saveGlobal(content: String, userText: String, directory: URL?) -> WorkspaceMemoryMutation {
        guard let directory else {
            return WorkspaceMemoryMutationFactory.saveFailed(
                userText: userText,
                error: MemoryNoteWriteError.unavailable,
                refresh: .none
            )
        }

        do {
            let saved = try WorkspaceMemoryRememberToolExecutor.saveGlobal(content: content, to: directory)
            return WorkspaceMemoryMutationFactory.saved(
                userText: userText,
                note: saved.note,
                refresh: .global(from: directory)
            )
        } catch let error as MemoryNoteWriteError {
            return WorkspaceMemoryMutationFactory.saveFailed(
                userText: userText,
                error: error,
                refresh: .global(from: directory)
            )
        } catch {
            return WorkspaceMemoryMutationFactory.saveFailed(
                userText: userText,
                error: MemoryNoteWriteError.writeFailed,
                refresh: .global(from: directory)
            )
        }
    }

    static func deleteGlobal(id: String, directory: URL?) -> WorkspaceMemoryMutation? {
        deleteLocalMemory(
            root: directory,
            missingRoot: nil,
            refresh: WorkspaceMemoryRefresh.global(from:),
            delete: { try MemoryNoteLoader.deleteGlobal(id: id, from: $0) }
        )
    }

    static func deleteProject(id: String, projectRoot: URL?) -> WorkspaceMemoryMutation {
        deleteLocalMemory(
            root: projectRoot,
            missingRoot: WorkspaceMemoryMutationFactory.deleteFailed(
                error: MemoryNoteDeleteError.deleteFailed,
                refresh: .none
            ),
            refresh: WorkspaceMemoryRefresh.project(from:),
            delete: { try MemoryNoteLoader.deleteProject(id: id, from: $0) }
        ) ?? WorkspaceMemoryMutationFactory.deleteFailed(error: MemoryNoteDeleteError.deleteFailed, refresh: .none)
    }

    static func updateGlobal(id: String, content: String, userText: String, directory: URL?) -> WorkspaceMemoryMutation {
        updateLocalMemory(
            root: directory,
            userText: userText,
            refresh: WorkspaceMemoryRefresh.global(from:),
            update: { try MemoryNoteLoader.updateGlobal(id: id, content: content, in: $0) }
        )
    }

    static func updateProject(
        id: String,
        content: String,
        userText: String,
        projectRoot: URL?
    ) -> WorkspaceMemoryMutation {
        updateLocalMemory(
            root: projectRoot,
            userText: userText,
            refresh: WorkspaceMemoryRefresh.project(from:),
            update: { try MemoryNoteLoader.updateProject(id: id, content: content, in: $0) }
        )
    }

    static func updateRemoteProject(
        id: String,
        content: String,
        userText: String,
        project: ProjectRef?,
        executor: SSHRemoteShellExecutor
    ) -> WorkspaceMemoryMutation {
        guard let project, project.isRemote else {
            return WorkspaceMemoryMutationFactory.updateFailed(
                userText: userText,
                error: WorkspaceRemoteProjectMemoryUpdateError.invalidConnection,
                refresh: .project(project?.memories)
            )
        }

        do {
            let updatedMemories = try WorkspaceRemoteProjectMemoryUpdater.update(
                id: id,
                content: content,
                project: project,
                executor: executor
            )
            let note = updatedMemories.first { $0.id == id }
            return WorkspaceMemoryMutationFactory.updated(
                userText: userText,
                note: note ?? fallbackRemoteMemoryNote(id: id),
                refresh: .project(updatedMemories)
            )
        } catch {
            return WorkspaceMemoryMutationFactory.updateFailed(
                userText: userText,
                error: error,
                refresh: .project(project.memories)
            )
        }
    }

    static func deleteRemoteProject(
        id: String,
        project: ProjectRef?,
        executor: SSHRemoteShellExecutor
    ) -> WorkspaceMemoryMutation {
        guard let project, project.isRemote else {
            return WorkspaceMemoryMutationFactory.deleteFailed(
                error: WorkspaceRemoteProjectMemoryUpdateError.invalidConnection,
                refresh: .project(project?.memories)
            )
        }

        do {
            let result = try WorkspaceRemoteProjectMemoryDeleter.delete(
                id: id,
                project: project,
                executor: executor
            )
            return WorkspaceMemoryMutationFactory.deleted(
                note: result.deleted,
                refresh: .project(result.updatedMemories)
            )
        } catch {
            return WorkspaceMemoryMutationFactory.deleteFailed(
                error: error,
                refresh: .project(project.memories)
            )
        }
    }

    static func contextUpdate(
        memories: [MemoryNote],
        summary: String,
        relativePath: String
    ) -> WorkspaceMemoryContextUpdate {
        WorkspaceMemoryContextUpdatePlanner.memoryChanged(
            memories: memories,
            summary: summary,
            relativePath: relativePath
        )
    }

    private static func fallbackRemoteMemoryNote(id: String) -> MemoryNote {
        MemoryNote(
            id: id,
            scope: .project,
            title: "remote project memory",
            content: "",
            relativePath: id,
            byteCount: 0
        )
    }

    private static func updateLocalMemory(
        root: URL?,
        userText: String,
        refresh: (URL) -> WorkspaceMemoryRefresh,
        update: (URL) throws -> MemoryNote
    ) -> WorkspaceMemoryMutation {
        guard let root else {
            return WorkspaceMemoryMutationFactory.updateFailed(
                userText: userText,
                error: MemoryNoteUpdateError.updateFailed,
                refresh: .none
            )
        }
        do {
            return WorkspaceMemoryMutationFactory.updated(
                userText: userText,
                note: try update(root),
                refresh: refresh(root)
            )
        } catch {
            return WorkspaceMemoryMutationFactory.updateFailed(
                userText: userText,
                error: error,
                refresh: refresh(root)
            )
        }
    }

    private static func deleteLocalMemory(
        root: URL?,
        missingRoot: WorkspaceMemoryMutation?,
        refresh: (URL) -> WorkspaceMemoryRefresh,
        delete: (URL) throws -> MemoryNote
    ) -> WorkspaceMemoryMutation? {
        guard let root else { return missingRoot }
        do {
            return WorkspaceMemoryMutationFactory.deleted(note: try delete(root), refresh: refresh(root))
        } catch let error as MemoryNoteDeleteError {
            return WorkspaceMemoryMutationFactory.deleteFailed(error: error, refresh: refresh(root))
        } catch {
            return WorkspaceMemoryMutationFactory.deleteFailed(
                error: MemoryNoteDeleteError.deleteFailed,
                refresh: refresh(root)
            )
        }
    }
}
