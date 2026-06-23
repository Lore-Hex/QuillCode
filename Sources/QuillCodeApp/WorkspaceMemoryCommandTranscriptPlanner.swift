import Foundation

struct WorkspaceMemoryCommandTranscriptPlanner {
    static func memoryForgotten(userText: String, noteTitle: String) -> WorkspaceLocalCommandTranscript {
        transcript(
            userText: userText,
            assistantText: "\(memoryForgottenSummary(noteTitle: noteTitle)). It will no longer be included as background context.",
            title: "Forgot memory: \(noteTitle)"
        )
    }

    static func memoryNotDeleted(userText: String, message: String) -> WorkspaceLocalCommandTranscript {
        transcript(
            userText: userText,
            assistantText: message,
            title: "Memory not deleted"
        )
    }

    static func memoryForgottenSummary(noteTitle: String) -> String {
        "Forgot memory: \(noteTitle)"
    }

    private static func transcript(userText: String, assistantText: String, title: String) -> WorkspaceLocalCommandTranscript {
        WorkspaceLocalCommandTranscript(
            userText: userText,
            assistantText: assistantText,
            title: title
        )
    }
}
