import Foundation
import QuillCodeCore

struct WorkspaceMemoryMutationOutcome: Sendable, Equatable {
    let transcript: WorkspaceLocalCommandTranscript
    let noticeSummary: String?
    let noticeRelativePath: String?

    static func changed(
        _ kind: WorkspaceMemoryChangeKind,
        userText: String,
        note: MemoryNote
    ) -> Self {
        changed(
            transcript: kind.transcript(userText: userText, noteTitle: note.title),
            summary: kind.summary(noteTitle: note.title),
            note: note
        )
    }

    static func failed(
        _ kind: WorkspaceMemoryFailureKind,
        userText: String,
        message: String
    ) -> Self {
        failed(transcript: kind.transcript(userText, message))
    }

    private static func changed(
        transcript: WorkspaceLocalCommandTranscript,
        summary: String,
        note: MemoryNote
    ) -> Self {
        Self(
            transcript: transcript,
            noticeSummary: summary,
            noticeRelativePath: note.relativePath
        )
    }

    private static func failed(transcript: WorkspaceLocalCommandTranscript) -> Self {
        Self(
            transcript: transcript,
            noticeSummary: nil,
            noticeRelativePath: nil
        )
    }
}
