import Foundation
import QuillCodeCore

enum WorkspaceShortcutSearchMode: String, CaseIterable, Identifiable {
    case action = "Action"
    case keystroke = "Keystroke"

    var id: String { rawValue }
}

enum WorkspaceShortcutAssignmentResult: Sendable, Hashable {
    case assigned
    case conflict(commandIDs: [String])
    case invalid(reason: String)
}

struct WorkspaceShortcutEditor: Sendable, Hashable {
    private(set) var preferences: KeyboardShortcutPreferences

    init(preferences: KeyboardShortcutPreferences = KeyboardShortcutPreferences()) {
        self.preferences = preferences
    }

    var profile: WorkspaceShortcutProfile {
        WorkspaceShortcutRegistry.profile(preferences: preferences)
    }

    var hasOverrides: Bool {
        !preferences.overrides.isEmpty
    }

    func groups(
        commands: [WorkspaceCommandSurface],
        query: String,
        mode: WorkspaceShortcutSearchMode
    ) -> [WorkspaceCommandGroupSurface] {
        let surfaced = commands.compactMap { command -> WorkspaceCommandSurface? in
            guard let label = profile.label(for: command.id) else { return nil }
            var command = command
            command.shortcut = label
            return command
        }

        switch mode {
        case .action:
            return WorkspaceCommandPalette.groupedActionCommands(surfaced, matching: query)
        case .keystroke:
            let needle = Self.normalizedShortcutSearchText(query)
            let matches = needle.isEmpty ? surfaced : surfaced.filter { command in
                Self.normalizedShortcutSearchText(command.shortcut ?? "").contains(needle)
            }
            return WorkspaceCommandPalette.groupedActionCommands(matches, matching: "")
        }
    }

    func shortcut(for commandID: String) -> WorkspaceShortcut? {
        profile.shortcut(for: commandID)
    }

    func isCustomized(_ commandID: String) -> Bool {
        preferences.override(for: commandID) != nil
    }

    mutating func assign(_ shortcut: WorkspaceShortcut) -> WorkspaceShortcutAssignmentResult {
        guard shortcut.override.hasSupportedKey else {
            return .invalid(reason: "Use a letter, number, punctuation key, arrow, Tab, or Escape.")
        }
        guard shortcut.override.isSafeGlobalBinding else {
            return .invalid(reason: "Add Command, Control, or Option so typing stays uninterrupted.")
        }

        let conflicts = profile.shortcuts.filter {
            $0.commandID != shortcut.commandID && $0.bindingSignature == shortcut.bindingSignature
        }
        guard conflicts.isEmpty else {
            return .conflict(commandIDs: Array(Set(conflicts.map(\.commandID))).sorted())
        }

        let defaultBindings = WorkspaceShortcutRegistry.defaults.shortcuts(for: shortcut.commandID)
        var overrides = preferences.overrides.filter { $0.commandID != shortcut.commandID }
        if !defaultBindings.contains(where: { $0.bindingSignature == shortcut.bindingSignature }) {
            overrides.append(shortcut.override)
        }
        preferences = KeyboardShortcutPreferences(overrides: overrides)
        return .assigned
    }

    mutating func reset(commandID: String) {
        preferences = KeyboardShortcutPreferences(
            overrides: preferences.overrides.filter { $0.commandID != commandID }
        )
    }

    mutating func resetAll() {
        preferences = KeyboardShortcutPreferences()
    }

    private static func normalizedShortcutSearchText(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "command", with: "cmd")
            .filter { $0.isLetter || $0.isNumber || "-[]/,`←→↑↓".contains($0) }
    }
}
