import Foundation
import QuillCodeCore

enum WorkspaceMemoryMutationFactory {
    typealias Refresh = WorkspaceMemoryRefresh
    typealias Mutation = WorkspaceMemoryMutation

    static func saved(userText: String, note: MemoryNote, refresh: Refresh) -> Mutation {
        mutation(
            for: WorkspaceMemoryMutationOutcome.saved(userText: userText, note: note),
            refresh: refresh
        )
    }

    static func updated(userText: String, note: MemoryNote, refresh: Refresh) -> Mutation {
        mutation(
            for: WorkspaceMemoryMutationOutcome.updated(userText: userText, note: note),
            refresh: refresh
        )
    }

    static func deleted(note: MemoryNote, refresh: Refresh) -> Mutation {
        mutation(for: WorkspaceMemoryMutationOutcome.deleted(note: note), refresh: refresh)
    }

    static func saveFailed(
        userText: String,
        error: any Error,
        refresh: Refresh
    ) -> Mutation {
        mutation(
            for: WorkspaceMemoryMutationOutcome.saveFailed(
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
    ) -> Mutation {
        mutation(
            for: WorkspaceMemoryMutationOutcome.updateFailed(
                userText: userText,
                message: errorMessage(for: error)
            ),
            refresh: refresh
        )
    }

    static func deleteFailed(error: any Error, refresh: Refresh) -> Mutation {
        mutation(
            for: WorkspaceMemoryMutationOutcome.deleteFailed(message: errorMessage(for: error)),
            refresh: refresh
        )
    }

    private static func mutation(
        for outcome: WorkspaceMemoryMutationOutcome,
        refresh: Refresh
    ) -> Mutation {
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
