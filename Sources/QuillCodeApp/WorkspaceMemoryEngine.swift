import Foundation
import QuillCodeCore

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
            return memoryNotSaved(
                userText: userText,
                error: MemoryNoteWriteError.unavailable,
                updatedGlobalMemories: nil
            )
        }

        do {
            let saved = try WorkspaceMemoryRememberToolExecutor.saveGlobal(content: content, to: directory)
            let note = saved.note
            return WorkspaceMemoryMutation(
                transcript: WorkspaceMemoryCommandTranscriptPlanner.memorySaved(
                    userText: userText,
                    noteTitle: note.title
                ),
                updatedGlobalMemories: loadGlobal(from: directory),
                updatedProjectMemories: nil,
                noticeSummary: WorkspaceMemoryCommandTranscriptPlanner.memorySavedSummary(noteTitle: note.title),
                noticeRelativePath: note.relativePath
            )
        } catch let error as MemoryNoteWriteError {
            return memoryNotSaved(userText: userText, error: error, updatedGlobalMemories: loadGlobal(from: directory))
        } catch {
            return memoryNotSaved(
                userText: userText,
                error: MemoryNoteWriteError.writeFailed,
                updatedGlobalMemories: loadGlobal(from: directory)
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
            return WorkspaceMemoryMutation(
                transcript: WorkspaceMemoryCommandTranscriptPlanner.memoryForgotten(
                    userText: "Forget memory: \(note.title)",
                    noteTitle: note.title
                ),
                updatedGlobalMemories: loadGlobal(from: directory),
                updatedProjectMemories: nil,
                noticeSummary: WorkspaceMemoryCommandTranscriptPlanner.memoryForgottenSummary(noteTitle: note.title),
                noticeRelativePath: note.relativePath
            )
        } catch let error as MemoryNoteDeleteError {
            return memoryNotDeleted(error: error, updatedGlobalMemories: loadGlobal(from: directory))
        } catch {
            return memoryNotDeleted(error: MemoryNoteDeleteError.deleteFailed, updatedGlobalMemories: loadGlobal(from: directory))
        }
    }

    static func updateGlobal(
        id: String,
        content: String,
        userText: String,
        directory: URL?
    ) -> WorkspaceMemoryMutation {
        guard let directory else {
            return memoryNotUpdated(
                userText: userText,
                error: MemoryNoteUpdateError.updateFailed,
                updatedGlobalMemories: nil,
                updatedProjectMemories: nil
            )
        }

        do {
            let note = try MemoryNoteLoader.updateGlobal(id: id, content: content, in: directory)
            return WorkspaceMemoryMutation(
                transcript: WorkspaceMemoryCommandTranscriptPlanner.memoryUpdated(
                    userText: userText,
                    noteTitle: note.title
                ),
                updatedGlobalMemories: loadGlobal(from: directory),
                updatedProjectMemories: nil,
                noticeSummary: WorkspaceMemoryCommandTranscriptPlanner.memoryUpdatedSummary(noteTitle: note.title),
                noticeRelativePath: note.relativePath
            )
        } catch {
            return memoryNotUpdated(
                userText: userText,
                error: error,
                updatedGlobalMemories: loadGlobal(from: directory),
                updatedProjectMemories: nil
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
            return memoryNotUpdated(
                userText: userText,
                error: MemoryNoteUpdateError.updateFailed,
                updatedGlobalMemories: nil,
                updatedProjectMemories: nil
            )
        }

        do {
            let note = try MemoryNoteLoader.updateProject(id: id, content: content, in: projectRoot)
            return WorkspaceMemoryMutation(
                transcript: WorkspaceMemoryCommandTranscriptPlanner.memoryUpdated(
                    userText: userText,
                    noteTitle: note.title
                ),
                updatedGlobalMemories: nil,
                updatedProjectMemories: MemoryNoteLoader.loadProject(from: projectRoot),
                noticeSummary: WorkspaceMemoryCommandTranscriptPlanner.memoryUpdatedSummary(noteTitle: note.title),
                noticeRelativePath: note.relativePath
            )
        } catch {
            return memoryNotUpdated(
                userText: userText,
                error: error,
                updatedGlobalMemories: nil,
                updatedProjectMemories: MemoryNoteLoader.loadProject(from: projectRoot)
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

    private static func memoryNotSaved(
        userText: String,
        error: any Error,
        updatedGlobalMemories: [MemoryNote]?
    ) -> WorkspaceMemoryMutation {
        WorkspaceMemoryMutation(
            transcript: WorkspaceMemoryCommandTranscriptPlanner.memoryNotSaved(
                userText: userText,
                message: WorkspaceMemoryErrorMessageBuilder.userFacingMessage(for: error)
            ),
            updatedGlobalMemories: updatedGlobalMemories,
            updatedProjectMemories: nil,
            noticeSummary: nil,
            noticeRelativePath: nil
        )
    }

    private static func memoryNotDeleted(
        error: any Error,
        updatedGlobalMemories: [MemoryNote]
    ) -> WorkspaceMemoryMutation {
        WorkspaceMemoryMutation(
            transcript: WorkspaceMemoryCommandTranscriptPlanner.memoryNotDeleted(
                userText: "Forget memory",
                message: WorkspaceMemoryErrorMessageBuilder.userFacingMessage(for: error)
            ),
            updatedGlobalMemories: updatedGlobalMemories,
            updatedProjectMemories: nil,
            noticeSummary: nil,
            noticeRelativePath: nil
        )
    }

    private static func memoryNotUpdated(
        userText: String,
        error: any Error,
        updatedGlobalMemories: [MemoryNote]?,
        updatedProjectMemories: [MemoryNote]?
    ) -> WorkspaceMemoryMutation {
        WorkspaceMemoryMutation(
            transcript: WorkspaceMemoryCommandTranscriptPlanner.memoryNotUpdated(
                userText: userText,
                message: WorkspaceMemoryErrorMessageBuilder.userFacingMessage(for: error)
            ),
            updatedGlobalMemories: updatedGlobalMemories,
            updatedProjectMemories: updatedProjectMemories,
            noticeSummary: nil,
            noticeRelativePath: nil
        )
    }
}
