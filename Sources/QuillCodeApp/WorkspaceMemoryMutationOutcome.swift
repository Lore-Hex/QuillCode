import Foundation
import QuillCodeCore

struct WorkspaceMemoryMutationOutcome: Sendable, Equatable {
    let transcript: WorkspaceLocalCommandTranscript
    let noticeSummary: String?
    let noticeRelativePath: String?

    static func saved(userText: String, note: MemoryNote) -> WorkspaceMemoryMutationOutcome {
        changed(
            transcript: WorkspaceMemoryCommandTranscriptPlanner.memorySaved(
                userText: userText,
                noteTitle: note.title
            ),
            summary: WorkspaceMemoryCommandTranscriptPlanner.memorySavedSummary(noteTitle: note.title),
            note: note
        )
    }

    static func updated(userText: String, note: MemoryNote) -> WorkspaceMemoryMutationOutcome {
        changed(
            transcript: WorkspaceMemoryCommandTranscriptPlanner.memoryUpdated(
                userText: userText,
                noteTitle: note.title
            ),
            summary: WorkspaceMemoryCommandTranscriptPlanner.memoryUpdatedSummary(noteTitle: note.title),
            note: note
        )
    }

    static func deleted(note: MemoryNote) -> WorkspaceMemoryMutationOutcome {
        changed(
            transcript: WorkspaceMemoryCommandTranscriptPlanner.memoryForgotten(
                userText: "Forget memory: \(note.title)",
                noteTitle: note.title
            ),
            summary: WorkspaceMemoryCommandTranscriptPlanner.memoryForgottenSummary(noteTitle: note.title),
            note: note
        )
    }

    static func saveFailed(userText: String, message: String) -> WorkspaceMemoryMutationOutcome {
        failed(
            transcript: WorkspaceMemoryCommandTranscriptPlanner.memoryNotSaved(
                userText: userText,
                message: message
            )
        )
    }

    static func updateFailed(userText: String, message: String) -> WorkspaceMemoryMutationOutcome {
        failed(
            transcript: WorkspaceMemoryCommandTranscriptPlanner.memoryNotUpdated(
                userText: userText,
                message: message
            )
        )
    }

    static func deleteFailed(message: String) -> WorkspaceMemoryMutationOutcome {
        failed(
            transcript: WorkspaceMemoryCommandTranscriptPlanner.memoryNotDeleted(
                userText: "Forget memory",
                message: message
            )
        )
    }

    private static func changed(
        transcript: WorkspaceLocalCommandTranscript,
        summary: String,
        note: MemoryNote
    ) -> WorkspaceMemoryMutationOutcome {
        WorkspaceMemoryMutationOutcome(
            transcript: transcript,
            noticeSummary: summary,
            noticeRelativePath: note.relativePath
        )
    }

    private static func failed(transcript: WorkspaceLocalCommandTranscript) -> WorkspaceMemoryMutationOutcome {
        WorkspaceMemoryMutationOutcome(
            transcript: transcript,
            noticeSummary: nil,
            noticeRelativePath: nil
        )
    }
}
