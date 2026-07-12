import Foundation
import QuillCodeCore

struct ManagedWorktreeTransferLimits: Sendable, Hashable {
    var maximumPatchBytes: Int64 = 16 * 1_024 * 1_024
    var maximumCandidateListBytes = 1 * 1_024 * 1_024
    var maximumFiles = 256
    var maximumFileBytes: Int64 = 8 * 1_024 * 1_024
    var maximumTotalFileBytes: Int64 = 32 * 1_024 * 1_024
}

enum ManagedWorktreeMaterializationError: Error, CustomStringConvertible {
    case commandFailed(String, ToolResult)
    case candidateListTooLarge(Int)
    case tooManyFiles(Int)
    case fileTooLarge(String, Int64)
    case totalFilesTooLarge(Int64)
    case unsupportedFilename(String)
    case unsafeSource(String)
    case patchTooLarge(String, Int64)
    case fileInspectionFailed(String, String)
    case fileCopyFailed(String, String)
    case sourceChanged(String)
    case destinationAlreadyExists(String)

    var description: String {
        switch self {
        case .commandFailed(let operation, let result):
            let detail = result.error ?? result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "Managed worktree \(operation) failed." : "Managed worktree \(operation) failed: \(detail)"
        case .candidateListTooLarge(let bytes):
            return "Managed worktree local-file inventory is too large (\(bytes) bytes). Narrow .worktreeinclude first."
        case .tooManyFiles(let count):
            return "Managed worktree would copy \(count) local files; the safe limit is 256. Narrow .worktreeinclude first."
        case .fileTooLarge(let path, let bytes):
            return "Managed worktree local file is too large to copy safely: \(path) (\(bytes) bytes)."
        case .totalFilesTooLarge(let bytes):
            return "Managed worktree local files exceed the 32 MiB safe transfer limit (\(bytes) bytes)."
        case .unsupportedFilename(let path):
            return "Managed worktree cannot safely transfer a non-UTF-8 filename: \(path)"
        case .unsafeSource(let path):
            return "Managed worktree local file escapes the project or uses an unsafe path: \(path)"
        case .patchTooLarge(let label, let bytes):
            return "Managed worktree \(label) patch exceeds the 16 MiB safe transfer limit (\(bytes) bytes)."
        case .fileInspectionFailed(let path, let detail):
            return "Managed worktree could not inspect local file \(path): \(detail)"
        case .fileCopyFailed(let path, let detail):
            return "Managed worktree could not copy local file \(path): \(detail)"
        case .sourceChanged(let path):
            return "Managed worktree local file changed type while it was being captured: \(path)"
        case .destinationAlreadyExists(let path):
            return "Managed worktree refused to overwrite an existing destination file: \(path)"
        }
    }
}
