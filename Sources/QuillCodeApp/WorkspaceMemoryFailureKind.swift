import Foundation

enum WorkspaceMemoryFailureKind {
    case save
    case update
    case delete

    func transcript(_ userText: String, _ message: String) -> WorkspaceLocalCommandTranscript {
        switch self {
        case .save:
            WorkspaceMemoryCommandTranscriptPlanner.memoryNotSaved(userText: userText, message: message)
        case .update:
            WorkspaceMemoryCommandTranscriptPlanner.memoryNotUpdated(userText: userText, message: message)
        case .delete:
            WorkspaceMemoryCommandTranscriptPlanner.memoryNotDeleted(userText: userText, message: message)
        }
    }
}
