import Foundation

struct WorkspaceMemoryCommandTranscriptPlanner {
    static func memorySaved(userText: String, noteTitle: String) -> WorkspaceLocalCommandTranscript {
        transcript(
            userText: userText,
            assistantText: "\(memorySavedSummary(noteTitle: noteTitle)). It will be included as background context in future turns.",
            title: "Memory: \(noteTitle)"
        )
    }

    static func memoryNotSaved(userText: String, message: String) -> WorkspaceLocalCommandTranscript {
        transcript(
            userText: userText,
            assistantText: message,
            title: "Memory not saved"
        )
    }

    static func memoryForgotten(userText: String, noteTitle: String) -> WorkspaceLocalCommandTranscript {
        transcript(
            userText: userText,
            assistantText: "\(memoryForgottenSummary(noteTitle: noteTitle)). It will no longer be included as background context.",
            title: "Forgot memory: \(noteTitle)"
        )
    }

    static func memoryUpdated(userText: String, noteTitle: String) -> WorkspaceLocalCommandTranscript {
        transcript(
            userText: userText,
            assistantText: "\(memoryUpdatedSummary(noteTitle: noteTitle)). Future turns will use the revised memory.",
            title: "Updated memory: \(noteTitle)"
        )
    }

    static func memoryNotUpdated(userText: String, message: String) -> WorkspaceLocalCommandTranscript {
        transcript(
            userText: userText,
            assistantText: message,
            title: "Memory not updated"
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

    static func memorySavedSummary(noteTitle: String) -> String {
        "Saved memory: \(noteTitle)"
    }

    static func memoryUpdatedSummary(noteTitle: String) -> String {
        "Updated memory: \(noteTitle)"
    }

    private static func transcript(userText: String, assistantText: String, title: String) -> WorkspaceLocalCommandTranscript {
        WorkspaceLocalCommandTranscript(
            userText: userText,
            assistantText: assistantText,
            title: title
        )
    }
}
