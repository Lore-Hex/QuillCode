import Foundation

public enum MemoryNoteWriteError: Error, Equatable, LocalizedError {
    case empty
    case tooLarge(actual: Int, maximum: Int)
    case sensitiveContent
    case unavailable
    case writeFailed

    public var errorDescription: String? {
        switch self {
        case .empty:
            return "Nothing to remember. Use `/remember a durable preference or fact`."
        case .tooLarge(let actual, let maximum):
            return MemoryNoteErrorMessages.tooLarge(actual: actual, maximum: maximum)
        case .sensitiveContent:
            return MemoryNoteErrorMessages.sensitiveContent(action: "saved")
        case .unavailable:
            return "Memory saving is unavailable in this runtime."
        case .writeFailed:
            return "Memory could not be written."
        }
    }
}

public enum MemoryNoteDeleteError: Error, Equatable, LocalizedError {
    case notFound
    case deleteFailed

    public var errorDescription: String? {
        switch self {
        case .notFound:
            return "Memory was not found. It may already have been removed."
        case .deleteFailed:
            return "Memory could not be deleted."
        }
    }
}

public enum MemoryNoteUpdateError: Error, Equatable, LocalizedError {
    case notFound
    case empty
    case tooLarge(actual: Int, maximum: Int)
    case sensitiveContent
    case updateFailed

    public var errorDescription: String? {
        switch self {
        case .notFound:
            return "Memory was not found. It may already have been removed."
        case .empty:
            return "Memory cannot be empty."
        case .tooLarge(let actual, let maximum):
            return MemoryNoteErrorMessages.tooLarge(actual: actual, maximum: maximum)
        case .sensitiveContent:
            return MemoryNoteErrorMessages.sensitiveContent(action: "updated")
        case .updateFailed:
            return "Memory could not be updated."
        }
    }
}

private enum MemoryNoteErrorMessages {
    static func tooLarge(actual: Int, maximum: Int) -> String {
        "Memory is too large (\(actual) bytes). Keep explicit memories under \(maximum) bytes."
    }

    static func sensitiveContent(action: String) -> String {
        "Memory was not \(action) because it looks like it contains a credential, token, password, or private key."
    }
}
