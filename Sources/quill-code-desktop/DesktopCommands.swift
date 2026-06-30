import Foundation
import SwiftUI
import QuillCodeApp

struct QuillCodeDesktopCommands: Commands {
    var body: some Commands {
        CommandMenu("QuillCode") {
            Button("New Chat") {
                NotificationCenter.default.post(name: .quillCodeNewChat, object: nil)
            }
            .quillCodeShortcut("new-chat")
            Button("Cycle Approval Mode") {
                NotificationCenter.default.post(name: .quillCodeCycleMode, object: nil)
            }
            .quillCodeShortcut("cycle-mode")
            Button("Open Project...") {
                NotificationCenter.default.post(name: .quillCodeOpenProject, object: nil)
            }
            .quillCodeShortcut("add-project")
            Button("Toggle Terminal") {
                NotificationCenter.default.post(name: .quillCodeToggleTerminal, object: nil)
            }
            .quillCodeShortcut("toggle-terminal")
            Button("Toggle Browser") {
                NotificationCenter.default.post(name: .quillCodeToggleBrowser, object: nil)
            }
            .quillCodeShortcut("toggle-browser")
            Button("Browser Back") {
                NotificationCenter.default.post(name: .quillCodeBrowserBack, object: nil)
            }
            .quillCodeShortcut("browser-back")
            Button("Browser Forward") {
                NotificationCenter.default.post(name: .quillCodeBrowserForward, object: nil)
            }
            .quillCodeShortcut("browser-forward")
            Button("Browser Reload") {
                NotificationCenter.default.post(name: .quillCodeBrowserReload, object: nil)
            }
            .quillCodeShortcut("browser-reload")
            Button("Toggle Extensions") {
                NotificationCenter.default.post(name: .quillCodeToggleExtensions, object: nil)
            }
            Button("Toggle Memories") {
                NotificationCenter.default.post(name: .quillCodeToggleMemories, object: nil)
            }
            Button("Command Palette") {
                NotificationCenter.default.post(name: .quillCodeCommandPalette, object: nil)
            }
            .quillCodeShortcut("command-palette")
            Button("Keyboard Shortcuts") {
                NotificationCenter.default.post(name: .quillCodeKeyboardShortcuts, object: nil)
            }
            .quillCodeShortcut("keyboard-shortcuts")
            Button("Settings...") {
                NotificationCenter.default.post(name: .quillCodeOpenSettings, object: nil)
            }
            .quillCodeShortcut("settings")
            Button("Stop All") {
                NotificationCenter.default.post(name: .quillCodeStopAll, object: nil)
            }
            .quillCodeShortcut("stop-all")
            Button("Retry Last Turn") {
                NotificationCenter.default.post(name: .quillCodeRetryLastTurn, object: nil)
            }
            .quillCodeShortcut("retry-last-turn")
        }
    }
}

extension Notification.Name {
    static let quillCodeNewChat = Notification.Name("QuillCodeNewChat")
    static let quillCodeCycleMode = Notification.Name("QuillCodeCycleMode")
    static let quillCodeOpenProject = Notification.Name("QuillCodeOpenProject")
    static let quillCodeCommandPalette = Notification.Name("QuillCodeCommandPalette")
    static let quillCodeKeyboardShortcuts = Notification.Name("QuillCodeKeyboardShortcuts")
    static let quillCodeToggleTerminal = Notification.Name("QuillCodeToggleTerminal")
    static let quillCodeToggleBrowser = Notification.Name("QuillCodeToggleBrowser")
    static let quillCodeBrowserBack = Notification.Name("QuillCodeBrowserBack")
    static let quillCodeBrowserForward = Notification.Name("QuillCodeBrowserForward")
    static let quillCodeBrowserReload = Notification.Name("QuillCodeBrowserReload")
    static let quillCodeToggleExtensions = Notification.Name("QuillCodeToggleExtensions")
    static let quillCodeToggleMemories = Notification.Name("QuillCodeToggleMemories")
    static let quillCodeOpenSettings = Notification.Name("QuillCodeOpenSettings")
    static let quillCodeStopAll = Notification.Name("QuillCodeStopAll")
    static let quillCodeRetryLastTurn = Notification.Name("QuillCodeRetryLastTurn")
}

extension View {
    @ViewBuilder
    func quillCodeShortcut(_ commandID: String) -> some View {
        if let shortcut = WorkspaceShortcutRegistry.shortcut(for: commandID) {
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
        case "`":
            return "`"
        case ",":
            return ","
        default:
            return KeyEquivalent(Character(key))
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
