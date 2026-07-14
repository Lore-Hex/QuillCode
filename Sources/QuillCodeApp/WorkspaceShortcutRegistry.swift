import Foundation
import QuillCodeCore

public struct WorkspaceShortcut: Sendable, Hashable, Identifiable {
    public typealias Modifier = KeyboardShortcutModifier

    public var id: String { bindingSignature + ":" + commandID }
    public var commandID: String
    public var key: String
    public var modifiers: [Modifier]

    public var bindingSignature: String {
        let modifierKey = modifiers.map(\.rawValue).joined(separator: "+")
        return modifierKey + ":" + key.lowercased()
    }

    public var displayLabel: String {
        let keyLabel: String
        switch key {
        case "arrowLeft":
            keyLabel = "←"
        case "arrowRight":
            keyLabel = "→"
        case "arrowUp":
            keyLabel = "↑"
        case "arrowDown":
            keyLabel = "↓"
        case "escape":
            keyLabel = "Esc"
        case "tab":
            keyLabel = "Tab"
        case "`", ",", "[", "]", "/", "+", "-":
            keyLabel = key
        default:
            keyLabel = key.uppercased()
        }
        let modifierLabels = Modifier.allCases.compactMap { modifier in
            modifiers.contains(modifier) ? modifier.displayLabel : nil
        }
        return (modifierLabels + [keyLabel]).joined(separator: "+")
    }

    public init(commandID: String, key: String, modifiers: [Modifier]) {
        self.commandID = commandID
        self.key = key
        self.modifiers = Modifier.allCases.filter(Set(modifiers).contains)
    }

    public init(_ override: KeyboardShortcutOverride) {
        self.init(
            commandID: override.commandID,
            key: override.key,
            modifiers: override.modifiers
        )
    }

    public var override: KeyboardShortcutOverride {
        KeyboardShortcutOverride(commandID: commandID, key: key, modifiers: modifiers)
    }
}

public struct WorkspaceShortcutConflict: Sendable, Hashable, Identifiable {
    public var id: String { shortcut.bindingSignature }
    public var shortcut: WorkspaceShortcut
    public var commandIDs: [String]

    public init(shortcut: WorkspaceShortcut, commandIDs: [String]) {
        self.shortcut = shortcut
        self.commandIDs = commandIDs.sorted()
    }
}

public struct WorkspaceShortcutProfile: Sendable, Hashable {
    public var shortcuts: [WorkspaceShortcut]

    public init(shortcuts: [WorkspaceShortcut]) {
        self.shortcuts = shortcuts
    }

    public func shortcuts(for commandID: String) -> [WorkspaceShortcut] {
        shortcuts.filter { $0.commandID == commandID }
    }

    public func shortcut(for commandID: String) -> WorkspaceShortcut? {
        shortcuts.first { $0.commandID == commandID }
    }

    public func label(for commandID: String) -> String? {
        shortcut(for: commandID)?.displayLabel
    }

    public var conflicts: [WorkspaceShortcutConflict] {
        Dictionary(grouping: shortcuts, by: \.bindingSignature)
            .values
            .compactMap { matches in
                let commandIDs = Array(Set(matches.map(\.commandID)))
                guard commandIDs.count > 1, let shortcut = matches.first else { return nil }
                return WorkspaceShortcutConflict(shortcut: shortcut, commandIDs: commandIDs)
            }
            .sorted { $0.shortcut.displayLabel < $1.shortcut.displayLabel }
    }
}

public enum WorkspaceShortcutRegistry {
    /// Codex-compatible defaults come first. QuillCode-specific commands follow and deliberately
    /// avoid every binding in the documented Codex desktop command table.
    public static let shortcuts: [WorkspaceShortcut] = [
        WorkspaceShortcut(commandID: "command-palette", key: "k", modifiers: [.command]),
        WorkspaceShortcut(commandID: "command-palette", key: "p", modifiers: [.command, .shift]),
        WorkspaceShortcut(commandID: "settings", key: ",", modifiers: [.command]),
        WorkspaceShortcut(commandID: "keyboard-shortcuts", key: "/", modifiers: [.command, .shift]),
        WorkspaceShortcut(commandID: "add-project", key: "o", modifiers: [.command]),
        WorkspaceShortcut(commandID: "workspace-back", key: "[", modifiers: [.command]),
        WorkspaceShortcut(commandID: "workspace-forward", key: "]", modifiers: [.command]),
        WorkspaceShortcut(commandID: "increase-font-size", key: "+", modifiers: [.command]),
        WorkspaceShortcut(commandID: "decrease-font-size", key: "-", modifiers: [.command]),
        WorkspaceShortcut(commandID: "toggle-sidebar", key: "b", modifiers: [.command]),
        WorkspaceShortcut(commandID: "git-diff", key: "g", modifiers: [.control, .shift]),
        WorkspaceShortcut(commandID: "toggle-review-panel", key: "b", modifiers: [.command, .option]),
        WorkspaceShortcut(commandID: "toggle-bottom-panel", key: "j", modifiers: [.command]),
        WorkspaceShortcut(commandID: "toggle-terminal", key: "`", modifiers: [.control]),
        WorkspaceShortcut(commandID: "terminal-clear", key: "l", modifiers: [.control]),
        WorkspaceShortcut(commandID: "quick-chat", key: "n", modifiers: [.command, .option]),
        WorkspaceShortcut(commandID: "new-chat", key: "n", modifiers: [.command]),
        WorkspaceShortcut(commandID: "new-chat", key: "o", modifiers: [.command, .shift]),
        WorkspaceShortcut(commandID: "search", key: "g", modifiers: [.command]),
        WorkspaceShortcut(commandID: "find-in-chat", key: "f", modifiers: [.command]),
        WorkspaceShortcut(commandID: "previous-task", key: "[", modifiers: [.command, .shift]),
        WorkspaceShortcut(commandID: "next-task", key: "]", modifiers: [.command, .shift]),
        WorkspaceShortcut(commandID: "dictation", key: "d", modifiers: [.control, .shift]),

        WorkspaceShortcut(commandID: "cycle-mode", key: "tab", modifiers: [.shift]),
        WorkspaceShortcut(commandID: "retry-last-turn", key: "r", modifiers: [.command, .shift]),
        WorkspaceShortcut(commandID: "focus-composer", key: "l", modifiers: [.command]),
        WorkspaceShortcut(commandID: "copy-conversation", key: "c", modifiers: [.command, .shift]),
        WorkspaceShortcut(commandID: "toggle-browser", key: "b", modifiers: [.command, .shift]),
        WorkspaceShortcut(commandID: "toggle-activity", key: "a", modifiers: [.command, .shift]),
        WorkspaceShortcut(commandID: "toggle-automations", key: "a", modifiers: [.command, .option]),
        WorkspaceShortcut(commandID: "toggle-memories", key: "m", modifiers: [.command, .shift]),
        WorkspaceShortcut(commandID: "toggle-extensions", key: "x", modifiers: [.command, .shift]),
        WorkspaceShortcut(commandID: "browser-reload", key: "r", modifiers: [.command]),
        WorkspaceShortcut(commandID: "stop-all", key: "escape", modifiers: [])
    ]

    public static let defaults = WorkspaceShortcutProfile(shortcuts: shortcuts)

    public static func profile(
        preferences: KeyboardShortcutPreferences
    ) -> WorkspaceShortcutProfile {
        guard !preferences.overrides.isEmpty else { return defaults }
        let knownCommandIDs = Set(shortcuts.map(\.commandID))
        var acceptedOverrides: [String: WorkspaceShortcut] = [:]
        for override in preferences.overrides
        where knownCommandIDs.contains(override.commandID) && override.isValid {
            acceptedOverrides[override.commandID] = WorkspaceShortcut(override)
        }

        while true {
            let overriddenCommandIDs = Set(acceptedOverrides.keys)
            let resolved = shortcuts.filter { !overriddenCommandIDs.contains($0.commandID) }
                + Array(acceptedOverrides.values)
            let profile = WorkspaceShortcutProfile(shortcuts: resolved)
            let conflictingOverrides = Set(profile.conflicts.flatMap { $0.commandIDs })
                .intersection(overriddenCommandIDs)
            guard !conflictingOverrides.isEmpty else { return profile }
            conflictingOverrides.forEach { acceptedOverrides[$0] = nil }
        }
    }

    public static func shortcut(for commandID: String) -> WorkspaceShortcut? {
        defaults.shortcut(for: commandID)
    }

    public static func shortcuts(for commandID: String) -> [WorkspaceShortcut] {
        defaults.shortcuts(for: commandID)
    }

    public static func label(for commandID: String) -> String? {
        defaults.label(for: commandID)
    }
}

private extension KeyboardShortcutModifier {
    var displayLabel: String {
        switch self {
        case .command:
            "Cmd"
        case .control:
            "Ctrl"
        case .option:
            "Option"
        case .shift:
            "Shift"
        }
    }
}
