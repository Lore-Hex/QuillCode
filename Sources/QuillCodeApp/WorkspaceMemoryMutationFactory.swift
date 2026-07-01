import Foundation
import QuillCodeCore

typealias MemoryMutation = WorkspaceMemoryMutation

enum WorkspaceMemoryMutationFactory {
    typealias Refresh = WorkspaceMemoryRefresh
    typealias Outcome = WorkspaceMemoryMutationOutcome

    static func saved(
        userText: String,
        note: MemoryNote,
        refresh: Refresh
    ) -> MemoryMutation {
        mutation(
            for: Outcome.changed(.saved, userText: userText, note: note),
            refresh: refresh
        )
    }

    static func updated(
        userText: String,
        note: MemoryNote,
        refresh: Refresh
    ) -> MemoryMutation {
        mutation(
            for: Outcome.changed(.updated, userText: userText, note: note),
            refresh: refresh
        )
    }

    static func deleted(note: MemoryNote, refresh: Refresh) -> MemoryMutation {
        mutation(
            for: Outcome.changed(
                .deleted,
                userText: "Forget memory: \(note.title)",
                note: note
            ),
            refresh: refresh
        )
    }

    static func saveFailed(
        userText: String,
        error: any Error,
        refresh: Refresh
    ) -> MemoryMutation {
        mutation(
            for: Outcome.failed(
                .save,
                userText: userText,
                message: errorMessage(for: error)
            ),
            refresh: refresh
        )
    }

    static func updateFailed(
        userText: String,
        error: any Error,
        refresh: Refresh
    ) -> MemoryMutation {
        mutation(
            for: Outcome.failed(
                .update,
                userText: userText,
                message: errorMessage(for: error)
            ),
            refresh: refresh
        )
    }

    static func deleteFailed(error: any Error, refresh: Refresh) -> MemoryMutation {
        mutation(
            for: Outcome.failed(
                .delete,
                userText: "Forget memory",
                message: errorMessage(for: error)
            ),
            refresh: refresh
        )
    }

    private static func mutation(
        for outcome: Outcome,
        refresh: Refresh
    ) -> MemoryMutation {
        WorkspaceMemoryMutation(
            transcript: outcome.transcript,
            updatedGlobalMemories: refresh.global,
            updatedProjectMemories: refresh.project,
            noticeSummary: outcome.noticeSummary,
            noticeRelativePath: outcome.noticeRelativePath
        )
    }

    private static func errorMessage(for error: any Error) -> String {
        WorkspaceMemoryErrorMessageBuilder.userFacingMessage(for: error)
    }
}
