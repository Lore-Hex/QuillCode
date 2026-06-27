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
    var onOpenBrowserSession: () -> Void
    var onToggleExtensions: () -> Void
    var onToggleMemories: () -> Void
    var onStopAll: () -> Void
    var onDisconnectAll: () -> Void
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
        menuActionButton("New Chat", action: onNewChat)
        menuActionButton("Open Project...", action: onOpenProject)
        menuActionButton("Command Palette", action: onCommandPalette)
        menuActionButton("Keyboard Shortcuts", action: onKeyboardShortcuts)
        menuActionButton(surface.terminal.isVisible ? "Hide Terminal" : "Show Terminal", action: onToggleTerminal)
        menuActionButton(surface.browser.isVisible ? "Hide Browser" : "Show Browser", action: onToggleBrowser)
        menuActionButton(
            "Open Browser Session",
            isDisabled: surface.browser.currentURL == nil && !surface.browser.canOpen,
            action: onOpenBrowserSession
        )
        menuActionButton(surface.memories.isVisible ? "Hide Memories" : "Show Memories", action: onToggleMemories)
        menuActionButton(surface.extensions.isVisible ? "Hide Extensions" : "Show Extensions", action: onToggleExtensions)
        if surface.topBar.showsComputerUseSetup {
            menuActionButton("Computer Use Setup", action: onComputerUseSetup)
        }
        menuActionButton("Settings...", action: onSettings)
        Divider()
        menuActionButton("Stop All", isDisabled: stopAllCommand?.isEnabled != true, action: onStopAll)
        menuActionButton(
            "Disconnect All",
            isDisabled: disconnectAllCommand?.isEnabled != true,
            action: onDisconnectAll
        )
        Divider()
        menuActionButton("Quit QuillCode", action: onQuit)
    }

    private var stopAllCommand: WorkspaceCommandSurface? {
        surface.commands.first { $0.id == "stop-all" }
    }

    private var disconnectAllCommand: WorkspaceCommandSurface? {
        surface.commands.first { $0.id == "disconnect-all" }
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

    private func menuActionButton(
        _ title: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(QuillCodePressableButtonStyle())
            .quillCodeFullRowButtonTarget()
            .disabled(isDisabled)
    }
}
