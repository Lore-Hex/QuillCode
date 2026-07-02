import Foundation

enum WorkspaceMemoryFailureKind {
    case save
    case update
    case delete

    var redactionActionLabel: String? {
        switch self {
        case .save:
            return "save"
        case .update:
            return "update"
        case .delete:
            return nil
        }
    }

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
