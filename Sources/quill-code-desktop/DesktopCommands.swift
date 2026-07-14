import Foundation
import SwiftUI
import QuillCodeApp

struct QuillCodeDesktopCommands: Commands {
    var commands: [WorkspaceCommandSurface]
    var shortcutProfile: WorkspaceShortcutProfile

    private var commandsByID: [String: WorkspaceCommandSurface] {
        Dictionary(uniqueKeysWithValues: commands.map { ($0.id, $0) })
    }

    var body: some Commands {
        CommandMenu("QuillCode") {
            command("New Chat", id: "new-chat")
            command("Quick Chat", id: "quick-chat")
            command("Open Project...", id: "add-project")

            Divider()

            command("Search Chats", id: "search")
            command("Find in Chat", id: "find-in-chat")
            command("Back", id: "workspace-back")
            command("Forward", id: "workspace-forward")
            command("Previous Chat", id: "previous-task")
            command("Next Chat", id: "next-task")

            Divider()

            command("Toggle Sidebar", id: "toggle-sidebar")
            command("Open Review", id: "git-diff")
            command("Toggle Review Panel", id: "toggle-review-panel")
            command("Toggle Bottom Panel", id: "toggle-bottom-panel")
            command("Toggle Terminal", id: "toggle-terminal")
            command("Clear Terminal", id: "terminal-clear")
            command("Increase Font Size", id: "increase-font-size")
            command("Decrease Font Size", id: "decrease-font-size")

            Divider()

            command("Start Dictation", id: "dictation")
            command("Focus Message", id: "focus-composer")
            command("Cycle Approval Mode", id: "cycle-mode")
            command("Retry Last Turn", id: "retry-last-turn")
            command("Copy Conversation", id: "copy-conversation")
            command("Export Conversation as Markdown...", id: "export-conversation-markdown")

            Divider()

            command("Toggle Browser", id: "toggle-browser")
            command("Reload Browser", id: "browser-reload")
            command("Toggle Activity", id: "toggle-activity")
            command("Toggle Automations", id: "toggle-automations")
            command("Toggle Memories", id: "toggle-memories")
            command("Toggle Extensions", id: "toggle-extensions")

            Divider()

            command("Command Palette", id: "command-palette")
            command("Keyboard Shortcuts", id: "keyboard-shortcuts")
            command("Settings...", id: "settings")
            command("Stop All", id: "stop-all")
        }
    }

    private func command(_ title: String, id commandID: String) -> some View {
        Button(title) {
            NotificationCenter.default.post(
                name: .quillCodeRunCommand,
                object: commandID
            )
        }
        .disabled(commandsByID[commandID]?.isEnabled != true)
        .quillCodeShortcut(commandID, profile: shortcutProfile)
    }
}

extension Notification.Name {
    static let quillCodeRunCommand = Notification.Name("QuillCodeRunCommand")
}

extension View {
    @ViewBuilder
    func quillCodeShortcut(
        _ commandID: String,
        profile: WorkspaceShortcutProfile
    ) -> some View {
        if let shortcut = profile.shortcut(for: commandID) {
            keyboardShortcut(shortcut.keyEquivalent, modifiers: shortcut.eventModifiers)
        } else {
            self
        }
    }
}

private extension WorkspaceShortcut {
    var keyEquivalent: KeyEquivalent {
        switch key {
        case "escape":
            return .escape
        case "tab":
            return .tab
        case "arrowLeft":
            return .leftArrow
        case "arrowRight":
            return .rightArrow
        case "arrowUp":
            return .upArrow
        case "arrowDown":
            return .downArrow
        default:
            return KeyEquivalent(key.first ?? " ")
        }
    }

    var eventModifiers: EventModifiers {
        var result: EventModifiers = []
        if modifiers.contains(.command) {
            result.insert(.command)
        }
        if modifiers.contains(.control) {
            result.insert(.control)
        }
        if modifiers.contains(.option) {
            result.insert(.option)
        }
        if modifiers.contains(.shift) {
            result.insert(.shift)
        }
        return result
    }
}
