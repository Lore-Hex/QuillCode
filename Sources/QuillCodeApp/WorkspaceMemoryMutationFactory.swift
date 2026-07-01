import Foundation
import QuillCodeCore

typealias MemoryMutation = WorkspaceMemoryMutation

enum WorkspaceMemoryMutationFactory {
    static func saved(
        userText: String,
        note: MemoryNote,
        refresh: WorkspaceMemoryRefresh
    ) -> MemoryMutation {
        changed(.saved, userText, note, refresh)
    }

    static func updated(
        userText: String,
        note: MemoryNote,
        refresh: WorkspaceMemoryRefresh
    ) -> MemoryMutation {
        changed(.updated, userText, note, refresh)
    }

    static func deleted(note: MemoryNote, refresh: WorkspaceMemoryRefresh) -> MemoryMutation {
        changed(.deleted, "Forget memory: \(note.title)", note, refresh)
    }

    static func saveFailed(
        userText: String,
        error: any Error,
        refresh: WorkspaceMemoryRefresh
    ) -> MemoryMutation {
        failed(.save, userText, error, refresh)
    }

    static func updateFailed(
        userText: String,
        error: any Error,
        refresh: WorkspaceMemoryRefresh
    ) -> MemoryMutation {
        failed(.update, userText, error, refresh)
    }

    static func deleteFailed(error: any Error, refresh: WorkspaceMemoryRefresh) -> MemoryMutation {
        failed(.delete, "Forget memory", error, refresh)
    }

    private static func changed(
        _ kind: WorkspaceMemoryChangeKind,
        _ userText: String,
        _ note: MemoryNote,
        _ refresh: WorkspaceMemoryRefresh
    ) -> MemoryMutation {
        mutation(
            transcript: kind.transcript(userText: userText, noteTitle: note.title),
            refresh: refresh,
            noticeSummary: kind.summary(noteTitle: note.title),
            noticeRelativePath: note.relativePath
        )
    }

    private static func failed(
        _ kind: WorkspaceMemoryFailureKind,
        _ userText: String,
        _ error: any Error,
        _ refresh: WorkspaceMemoryRefresh
    ) -> MemoryMutation {
        mutation(
            transcript: kind.transcript(
                userText,
                WorkspaceMemoryErrorMessageBuilder.userFacingMessage(for: error)
            ),
            refresh: refresh,
            noticeSummary: nil,
            noticeRelativePath: nil
        )
    }

    private static func mutation(
        transcript: WorkspaceLocalCommandTranscript,
        refresh: WorkspaceMemoryRefresh,
        noticeSummary: String?,
        noticeRelativePath: String?
    ) -> MemoryMutation {
        WorkspaceMemoryMutation(
            transcript: transcript,
            updatedGlobalMemories: refresh.global,
            updatedProjectMemories: refresh.project,
            noticeSummary: noticeSummary,
            noticeRelativePath: noticeRelativePath
        )
    }
}
