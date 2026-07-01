import Foundation

enum WorkspaceRemoteProjectMemoryUpdateError: Error, Equatable, LocalizedError {
    case invalidMemoryID
    case missingKnownMemory
    case invalidConnection
    case updateFailed(String)
    case deleteFailed(String)
    case refreshFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidMemoryID:
            return "Remote project memory edits must target a loaded .quillcode/memories file."
        case .missingKnownMemory:
            return "Memory was not found in the selected remote project. Refresh context and try again."
        case .invalidConnection:
            return "SSH Remote project is missing a usable host."
        case .updateFailed(let message),
             .deleteFailed(let message),
             .refreshFailed(let message):
            return message
        }
    }
}
