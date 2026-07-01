import Foundation

public struct WorkspaceActivitySourceCommand: Equatable, Sendable {
    public enum Action: String, Sendable {
        case open
        case edit
    }

    public let action: Action
    public let path: String
    public let lineNumber: Int?

    public init(action: Action, path: String, lineNumber: Int? = nil) {
        self.action = action
        self.path = path
        self.lineNumber = lineNumber
    }

    public init?(commandID: String) {
        if let command = Self.lineCommand(commandID, action: .open) {
            self = command
            return
        }
        if let command = Self.lineCommand(commandID, action: .edit) {
            self = command
            return
        }
        if let path = Self.path(after: Self.prefix(for: .open), in: commandID) {
            self.init(action: .open, path: path)
            return
        }
        if let path = Self.path(after: Self.prefix(for: .edit), in: commandID) {
            self.init(action: .edit, path: path)
            return
        }
        return nil
    }

    public static func openCommandID(path: String, lineNumber: Int? = nil) -> String {
        commandID(action: .open, path: path, lineNumber: lineNumber)
    }

    public static func editCommandID(path: String, lineNumber: Int? = nil) -> String {
        commandID(action: .edit, path: path, lineNumber: lineNumber)
    }

    private static func commandID(action: Action, path: String, lineNumber: Int?) -> String {
        guard let lineNumber, lineNumber > 0 else {
            return "\(prefix(for: action))\(path)"
        }
        return "\(linePrefix(for: action))\(lineNumber):\(path)"
    }

    private static func lineCommand(_ commandID: String, action: Action) -> WorkspaceActivitySourceCommand? {
        let prefix = linePrefix(for: action)
        guard commandID.hasPrefix(prefix) else { return nil }
        let payload = commandID.dropFirst(prefix.count)
        guard let separator = payload.firstIndex(of: ":") else { return nil }
        let rawLineNumber = payload[..<separator]
        let rawPath = payload[payload.index(after: separator)...]
        guard let lineNumber = Int(rawLineNumber), lineNumber > 0,
              let path = normalizedPath(String(rawPath))
        else {
            return nil
        }
        return WorkspaceActivitySourceCommand(action: action, path: path, lineNumber: lineNumber)
    }

    private static func path(after prefix: String, in commandID: String) -> String? {
        guard commandID.hasPrefix(prefix) else { return nil }
        return normalizedPath(String(commandID.dropFirst(prefix.count)))
    }

    private static func normalizedPath(_ path: String) -> String? {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPath.isEmpty ? nil : trimmedPath
    }

    private static func prefix(for action: Action) -> String {
        "activity-source-\(action.rawValue):"
    }

    private static func linePrefix(for action: Action) -> String {
        "activity-source-\(action.rawValue)-line:"
    }
}
