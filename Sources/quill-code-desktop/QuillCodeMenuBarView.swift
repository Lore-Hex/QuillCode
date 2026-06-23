import SwiftUI
import QuillCodeApp

struct QuillCodeMenuBarView: View {
    var surface: WorkspaceSurface
    var onNewChat: () -> Void
    var onOpenProject: () -> Void
    var onCommandPalette: () -> Void
    var onKeyboardShortcuts: () -> Void
    var onSettings: () -> Void
    var onToggleTerminal: () -> Void
    var onToggleBrowser: () -> Void
    var onToggleExtensions: () -> Void
    var onToggleMemories: () -> Void
    var onStopAll: () -> Void
    var onComputerUseSetup: () -> Void
    var onQuit: () -> Void

    var body: some View {
        Text(surface.topBar.appName)
            .font(.headline)
        Text(surface.topBar.subtitle)
            .font(.caption)
        Divider()
        Label(surface.topBar.agentStatus, systemImage: statusSystemImage)
        if let issue = surface.runtimeIssue {
            Label(issue.title, systemImage: issue.severity == .error ? "xmark.octagon" : "exclamationmark.triangle")
            Text(issue.message)
                .font(.caption)
        }
        Text("Thread: \(surface.topBar.primaryTitle)")
        Text("Model: \(surface.topBar.modelLabel)")
        Text("Mode: \(surface.topBar.modeLabel)")
        Text("Computer Use: \(surface.topBar.computerUseLabel)")
        Divider()
        Button("New Chat", action: onNewChat)
        Button("Open Project...", action: onOpenProject)
        Button("Command Palette", action: onCommandPalette)
        Button("Keyboard Shortcuts", action: onKeyboardShortcuts)
        Button(surface.terminal.isVisible ? "Hide Terminal" : "Show Terminal", action: onToggleTerminal)
        Button(surface.browser.isVisible ? "Hide Browser" : "Show Browser", action: onToggleBrowser)
        Button(surface.memories.isVisible ? "Hide Memories" : "Show Memories", action: onToggleMemories)
        Button(surface.extensions.isVisible ? "Hide Extensions" : "Show Extensions", action: onToggleExtensions)
        if surface.topBar.showsComputerUseSetup {
            Button("Computer Use Setup", action: onComputerUseSetup)
        }
        Button("Settings...", action: onSettings)
        Divider()
        Button("Stop All", action: onStopAll)
            .disabled(!surface.composer.isSending && !surface.terminal.isRunning)
        Button("Disconnect All") {}
            .disabled(true)
        Divider()
        Button("Quit QuillCode", action: onQuit)
    }

    private var statusSystemImage: String {
        switch surface.topBar.agentStatus.lowercased() {
        case let status where status.contains("fail"):
            return "xmark.circle"
        case let status where status.contains("running") || status.contains("terminal"):
            return "arrow.triangle.2.circlepath"
        default:
            return "checkmark.circle"
        }
    }
}
