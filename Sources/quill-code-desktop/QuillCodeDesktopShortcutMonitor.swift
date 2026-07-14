import AppKit
import QuillCodeApp

struct QuillCodeDesktopShortcutEvent: Sendable, Hashable {
    var key: String
    var modifiers: [WorkspaceShortcut.Modifier]

    init(key: String, modifiers: [WorkspaceShortcut.Modifier]) {
        self.key = key
        self.modifiers = WorkspaceShortcut.Modifier.allCases.filter(Set(modifiers).contains)
    }

    init?(_ event: NSEvent) {
        guard let key = Self.key(for: event) else { return nil }
        self.init(key: key, modifiers: Self.modifiers(for: event.modifierFlags))
    }

    private static func key(for event: NSEvent) -> String? {
        switch event.keyCode {
        case 48:
            return "tab"
        case 53:
            return "escape"
        case 123:
            return "arrowLeft"
        case 124:
            return "arrowRight"
        case 125:
            return "arrowDown"
        case 126:
            return "arrowUp"
        default:
            guard let character = event.charactersIgnoringModifiers?.first
                ?? event.characters?.first
            else { return nil }
            return String(character).lowercased()
        }
    }

    private static func modifiers(
        for flags: NSEvent.ModifierFlags
    ) -> [WorkspaceShortcut.Modifier] {
        var modifiers: [WorkspaceShortcut.Modifier] = []
        if flags.contains(.command) { modifiers.append(.command) }
        if flags.contains(.control) { modifiers.append(.control) }
        if flags.contains(.option) { modifiers.append(.option) }
        if flags.contains(.shift) { modifiers.append(.shift) }
        return modifiers
    }
}

enum QuillCodeSecondaryShortcutResolver {
    static func commandID(
        for event: QuillCodeDesktopShortcutEvent,
        profile: WorkspaceShortcutProfile
    ) -> String? {
        let eventSignature = WorkspaceShortcut(
            commandID: "event",
            key: event.key,
            modifiers: event.modifiers
        ).bindingSignature
        var commandsWithPrimaryBinding: Set<String> = []

        for shortcut in profile.shortcuts {
            guard !commandsWithPrimaryBinding.insert(shortcut.commandID).inserted else {
                continue
            }
            if shortcut.bindingSignature == eventSignature {
                return shortcut.commandID
            }
        }
        return nil
    }
}
