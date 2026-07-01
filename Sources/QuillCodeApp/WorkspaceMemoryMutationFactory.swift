import Foundation
import QuillCodeCore

struct WorkspaceMemoryRefresh: Sendable, Equatable {
    let global: [MemoryNote]?
    let project: [MemoryNote]?

    static let none = WorkspaceMemoryRefresh(global: nil, project: nil)

    static func global(from directory: URL) -> WorkspaceMemoryRefresh {
        WorkspaceMemoryRefresh(
            global: MemoryNoteLoader.loadGlobal(from: directory),
            project: nil
        )
    }

    static func project(from projectRoot: URL) -> WorkspaceMemoryRefresh {
        WorkspaceMemoryRefresh(
            global: nil,
            project: MemoryNoteLoader.loadProject(from: projectRoot)
        )
    }

    static func project(_ memories: [MemoryNote]?) -> WorkspaceMemoryRefresh {
        WorkspaceMemoryRefresh(global: nil, project: memories)
    }
}

enum WorkspaceMemoryMutationFactory {
    static func saved(userText: String, note: MemoryNote, refresh: WorkspaceMemoryRefresh) -> WorkspaceMemoryMutation {
        WorkspaceMemoryMutation(
            transcript: WorkspaceMemoryCommandTranscriptPlanner.memorySaved(
                userText: userText,
                noteTitle: note.title
            ),
            updatedGlobalMemories: refresh.global,
            updatedProjectMemories: refresh.project,
            noticeSummary: WorkspaceMemoryCommandTranscriptPlanner.memorySavedSummary(noteTitle: note.title),
            noticeRelativePath: note.relativePath
        )
    }

    static func updated(userText: String, note: MemoryNote, refresh: WorkspaceMemoryRefresh) -> WorkspaceMemoryMutation {
        WorkspaceMemoryMutation(
            transcript: WorkspaceMemoryCommandTranscriptPlanner.memoryUpdated(
                userText: userText,
                noteTitle: note.title
            ),
            updatedGlobalMemories: refresh.global,
            updatedProjectMemories: refresh.project,
            noticeSummary: WorkspaceMemoryCommandTranscriptPlanner.memoryUpdatedSummary(noteTitle: note.title),
            noticeRelativePath: note.relativePath
        )
    }

    static func deleted(note: MemoryNote, refresh: WorkspaceMemoryRefresh) -> WorkspaceMemoryMutation {
        WorkspaceMemoryMutation(
            transcript: WorkspaceMemoryCommandTranscriptPlanner.memoryForgotten(
                userText: "Forget memory: \(note.title)",
                noteTitle: note.title
            ),
            updatedGlobalMemories: refresh.global,
            updatedProjectMemories: refresh.project,
            noticeSummary: WorkspaceMemoryCommandTranscriptPlanner.memoryForgottenSummary(noteTitle: note.title),
            noticeRelativePath: note.relativePath
        )
    }

    static func saveFailed(
        userText: String,
        error: any Error,
        refresh: WorkspaceMemoryRefresh
    ) -> WorkspaceMemoryMutation {
        WorkspaceMemoryMutation(
            transcript: WorkspaceMemoryCommandTranscriptPlanner.memoryNotSaved(
                userText: userText,
                message: WorkspaceMemoryErrorMessageBuilder.userFacingMessage(for: error)
            ),
            updatedGlobalMemories: refresh.global,
            updatedProjectMemories: refresh.project,
            noticeSummary: nil,
            noticeRelativePath: nil
        )
    }

    static func updateFailed(
        userText: String,
        error: any Error,
        refresh: WorkspaceMemoryRefresh
    ) -> WorkspaceMemoryMutation {
        WorkspaceMemoryMutation(
            transcript: WorkspaceMemoryCommandTranscriptPlanner.memoryNotUpdated(
                userText: userText,
                message: WorkspaceMemoryErrorMessageBuilder.userFacingMessage(for: error)
            ),
            updatedGlobalMemories: refresh.global,
            updatedProjectMemories: refresh.project,
            noticeSummary: nil,
            noticeRelativePath: nil
        )
    }

    static func deleteFailed(error: any Error, refresh: WorkspaceMemoryRefresh) -> WorkspaceMemoryMutation {
        WorkspaceMemoryMutation(
            transcript: WorkspaceMemoryCommandTranscriptPlanner.memoryNotDeleted(
                userText: "Forget memory",
                message: WorkspaceMemoryErrorMessageBuilder.userFacingMessage(for: error)
            ),
            updatedGlobalMemories: refresh.global,
            updatedProjectMemories: refresh.project,
            noticeSummary: nil,
            noticeRelativePath: nil
        )
    }
}
