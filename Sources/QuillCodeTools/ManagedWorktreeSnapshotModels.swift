import Foundation

public enum ManagedWorktreeSnapshotError: Error, LocalizedError, Sendable, Equatable {
    case invalidBinding(String)
    case unregisteredWorktree(String)
    case repositoryMismatch
    case snapshotMissing(UUID)
    case snapshotCorrupt(String)
    case sourceChanged
    case destinationExists(String)
    case gitFailed(String, String)
    case filesystemFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidBinding(let detail):
            "This task does not own a disposable worktree: \(detail)"
        case .unregisteredWorktree(let path):
            "The managed worktree is not registered with git: \(path)"
        case .repositoryMismatch:
            "The snapshot belongs to a different git repository."
        case .snapshotMissing(let id):
            "The saved worktree snapshot is missing: \(id.uuidString)"
        case .snapshotCorrupt(let detail):
            "The saved worktree snapshot is invalid: \(detail)"
        case .sourceChanged:
            "The worktree changed while it was being archived, so it was kept in place."
        case .destinationExists(let path):
            "The worktree cannot be restored because the destination already exists: \(path)"
        case .gitFailed(let operation, let detail):
            "Git failed while \(operation): \(detail)"
        case .filesystemFailed(let detail):
            "The worktree snapshot could not be saved: \(detail)"
        }
    }
}

public struct ManagedWorktreeSnapshotRestoreResult: Sendable, Hashable {
    public var path: String
    public var restoredFileCount: Int

    public init(path: String, restoredFileCount: Int) {
        self.path = path
        self.restoredFileCount = restoredFileCount
    }
}
