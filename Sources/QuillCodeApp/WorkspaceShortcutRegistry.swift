import Foundation

public struct WorkspaceShortcut: Codable, Sendable, Hashable, Identifiable {
    public enum Modifier: String, Codable, Sendable, Hashable, CaseIterable {
        case command = "Cmd"
        case control = "Ctrl"
        case option = "Option"
        case shift = "Shift"
    }

    public var id: String { commandID }
    public var commandID: String
    public var key: String
    public var modifiers: [Modifier]

    public var displayLabel: String {
        let keyLabel: String
        switch key {
        case "escape":
            keyLabel = "Esc"
        case "`", ",":
            keyLabel = key
        default:
            keyLabel = key.uppercased()
        }
        let modifierLabels = Modifier.allCases.compactMap { modifier in
            modifiers.contains(modifier) ? modifier.rawValue : nil
        }
        return (modifierLabels + [keyLabel]).joined(separator: "+")
    }

    public init(commandID: String, key: String, modifiers: [Modifier]) {
        self.commandID = commandID
        self.key = key
        self.modifiers = modifiers
    }
}

public enum WorkspaceShortcutRegistry {
    public static let shortcuts: [WorkspaceShortcut] = [
        WorkspaceShortcut(commandID: "new-chat", key: "n", modifiers: [.command]),
        WorkspaceShortcut(commandID: "search", key: "k", modifiers: [.command]),
        WorkspaceShortcut(commandID: "find-in-chat", key: "f", modifiers: [.command]),
        WorkspaceShortcut(commandID: "add-project", key: "o", modifiers: [.command]),
        WorkspaceShortcut(commandID: "toggle-terminal", key: "`", modifiers: [.control]),
        WorkspaceShortcut(commandID: "toggle-browser", key: "b", modifiers: [.command, .shift]),
        WorkspaceShortcut(commandID: "command-palette", key: "p", modifiers: [.command, .shift]),
        WorkspaceShortcut(commandID: "keyboard-shortcuts", key: "/", modifiers: [.command]),
        WorkspaceShortcut(commandID: "settings", key: ",", modifiers: [.command]),
        WorkspaceShortcut(commandID: "stop-all", key: "escape", modifiers: [])
    ]

    public static func shortcut(for commandID: String) -> WorkspaceShortcut? {
        shortcuts.first { $0.commandID == commandID }
    }

    public static func label(for commandID: String) -> String? {
        shortcut(for: commandID)?.displayLabel
    }
}
