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

    static func deleted(note: MemoryNote, refresh: Refresh, userText: String? = nil) -> MemoryMutation {
        mutation(
            for: Outcome.changed(
                .deleted,
                userText: userText ?? "Forget memory: \(note.title)",
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
        let reviewEvent = redactionReviewEvent(for: error, kind: .save, userText: userText)
        return mutation(
            for: Outcome.failed(
                .save,
                userText: redactedUserTextIfSensitive(userText, error: error, kind: .save),
                message: errorMessage(for: error)
            ),
            refresh: refresh,
            reviewEvent: reviewEvent
        )
    }

    static func updateFailed(
        userText: String,
        error: any Error,
        refresh: Refresh
    ) -> MemoryMutation {
        let reviewEvent = redactionReviewEvent(for: error, kind: .update, userText: userText)
        return mutation(
            for: Outcome.failed(
                .update,
                userText: redactedUserTextIfSensitive(userText, error: error, kind: .update),
                message: errorMessage(for: error)
            ),
            refresh: refresh,
            reviewEvent: reviewEvent
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
        refresh: Refresh,
        reviewEvent: ThreadEvent? = nil
    ) -> MemoryMutation {
        WorkspaceMemoryMutation(
            transcript: outcome.transcript,
            updatedGlobalMemories: refresh.global,
            updatedProjectMemories: refresh.project,
            noticeSummary: outcome.noticeSummary,
            noticeRelativePath: outcome.noticeRelativePath,
            reviewEvent: reviewEvent
        )
    }

    private static func errorMessage(for error: any Error) -> String {
        WorkspaceMemoryErrorMessageBuilder.userFacingMessage(for: error)
    }

    private static func redactionReviewEvent(
        for error: any Error,
        kind: WorkspaceMemoryFailureKind,
        userText: String
    ) -> ThreadEvent? {
        guard isSensitiveContent(error) else { return nil }
        return MemoryRedactionReviewSurface.event(action: kind, userText: userText)
    }

    private static func redactedUserTextIfSensitive(
        _ userText: String,
        error: any Error,
        kind: WorkspaceMemoryFailureKind
    ) -> String {
        guard isSensitiveContent(error) else { return userText }
        return MemoryRedactionReviewPayload.redactedUserText(action: kind, userText: userText)
    }

    private static func isSensitiveContent(_ error: any Error) -> Bool {
        if let writeError = error as? MemoryNoteWriteError {
            return writeError == .sensitiveContent
        }
        if let updateError = error as? MemoryNoteUpdateError {
            return updateError == .sensitiveContent
        }
        return false
    }
}
