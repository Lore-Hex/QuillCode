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

    static func saveGlobal(
        content: String,
        userText: String,
        directory: URL?
    ) -> WorkspaceMemoryMutation {
        guard let directory else {
            return WorkspaceMemoryMutationFactory.saveFailed(
                userText: userText,
                error: MemoryNoteWriteError.unavailable,
                refresh: .none
            )
        }

        do {
            let saved = try WorkspaceMemoryRememberToolExecutor.saveGlobal(content: content, to: directory)
            let note = saved.note
            return WorkspaceMemoryMutationFactory.saved(
                userText: userText,
                note: note,
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

    static func deleteGlobal(
        id: String,
        directory: URL?
    ) -> WorkspaceMemoryMutation? {
        guard let directory else { return nil }

        do {
            let note = try MemoryNoteLoader.deleteGlobal(id: id, from: directory)
            return WorkspaceMemoryMutationFactory.deleted(note: note, refresh: .global(from: directory))
        } catch let error as MemoryNoteDeleteError {
            return WorkspaceMemoryMutationFactory.deleteFailed(error: error, refresh: .global(from: directory))
        } catch {
            return WorkspaceMemoryMutationFactory.deleteFailed(
                error: MemoryNoteDeleteError.deleteFailed,
                refresh: .global(from: directory)
            )
        }
    }

    static func deleteProject(
        id: String,
        projectRoot: URL?
    ) -> WorkspaceMemoryMutation {
        guard let projectRoot else {
            return WorkspaceMemoryMutationFactory.deleteFailed(
                error: MemoryNoteDeleteError.deleteFailed,
                refresh: .none
            )
        }

        do {
            let note = try MemoryNoteLoader.deleteProject(id: id, from: projectRoot)
            return WorkspaceMemoryMutationFactory.deleted(note: note, refresh: .project(from: projectRoot))
        } catch let error as MemoryNoteDeleteError {
            return WorkspaceMemoryMutationFactory.deleteFailed(
                error: error,
                refresh: .project(from: projectRoot)
            )
        } catch {
            return WorkspaceMemoryMutationFactory.deleteFailed(
                error: MemoryNoteDeleteError.deleteFailed,
                refresh: .project(from: projectRoot)
            )
        }
    }

    static func updateGlobal(
        id: String,
        content: String,
        userText: String,
        directory: URL?
    ) -> WorkspaceMemoryMutation {
        guard let directory else {
            return WorkspaceMemoryMutationFactory.updateFailed(
                userText: userText,
                error: MemoryNoteUpdateError.updateFailed,
                refresh: .none
            )
        }

        do {
            let note = try MemoryNoteLoader.updateGlobal(id: id, content: content, in: directory)
            return WorkspaceMemoryMutationFactory.updated(
                userText: userText,
                note: note,
                refresh: .global(from: directory)
            )
        } catch {
            return WorkspaceMemoryMutationFactory.updateFailed(
                userText: userText,
                error: error,
                refresh: .global(from: directory)
            )
        }
    }

    static func updateProject(
        id: String,
        content: String,
        userText: String,
        projectRoot: URL?
    ) -> WorkspaceMemoryMutation {
        guard let projectRoot else {
            return WorkspaceMemoryMutationFactory.updateFailed(
                userText: userText,
                error: MemoryNoteUpdateError.updateFailed,
                refresh: .none
            )
        }

        do {
            let note = try MemoryNoteLoader.updateProject(id: id, content: content, in: projectRoot)
            return WorkspaceMemoryMutationFactory.updated(
                userText: userText,
                note: note,
                refresh: .project(from: projectRoot)
            )
        } catch {
            return WorkspaceMemoryMutationFactory.updateFailed(
                userText: userText,
                error: error,
                refresh: .project(from: projectRoot)
            )
        }
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
}
