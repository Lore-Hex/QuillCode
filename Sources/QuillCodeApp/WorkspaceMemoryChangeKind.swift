import Foundation

enum WorkspaceMemoryChangeKind {
    case saved
    case updated
    case deleted

    func transcript(userText: String, noteTitle: String) -> WorkspaceLocalCommandTranscript {
        switch self {
        case .saved:
            WorkspaceMemoryCommandTranscriptPlanner.memorySaved(userText: userText, noteTitle: noteTitle)
        case .updated:
            WorkspaceMemoryCommandTranscriptPlanner.memoryUpdated(userText: userText, noteTitle: noteTitle)
        case .deleted:
            WorkspaceMemoryCommandTranscriptPlanner.memoryForgotten(userText: userText, noteTitle: noteTitle)
        }
    }

    func summary(noteTitle: String) -> String {
        switch self {
        case .saved:
            WorkspaceMemoryCommandTranscriptPlanner.memorySavedSummary(noteTitle: noteTitle)
        case .updated:
            WorkspaceMemoryCommandTranscriptPlanner.memoryUpdatedSummary(noteTitle: noteTitle)
        case .deleted:
            WorkspaceMemoryCommandTranscriptPlanner.memoryForgottenSummary(noteTitle: noteTitle)
        }
    }
}
