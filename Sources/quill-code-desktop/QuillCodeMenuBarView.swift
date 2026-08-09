import SwiftUI
import QuillCodeApp

struct QuillCodeMenuBarView: View {
    @Environment(\.openWindow) private var openWindow

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
    var onStopWorkflowRecording: () -> Void
    var onToggleMemories: () -> Void
    var onStopAll: () -> Void
    var onDisconnectAll: () -> Void
    var onComputerUseSetup: () -> Void
    var onCheckForUpdates: () -> Void
    var onReportIssue: () -> Void
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
        if surface.extensions.workflowRecording?.isRecording == true {
            Label("Recording workflow", systemImage: "record.circle.fill")
            menuActionButton("Stop Recording", action: onStopWorkflowRecording)
        }
        Divider()
        menuActionButton("New Chat", revealsMainWindow: true, action: onNewChat)
        menuActionButton("Open Project...", revealsMainWindow: true, action: onOpenProject)
        menuActionButton("Command Palette", revealsMainWindow: true, action: onCommandPalette)
        menuActionButton("Keyboard Shortcuts", revealsMainWindow: true, action: onKeyboardShortcuts)
        menuActionButton(
            surface.terminal.isVisible ? "Hide Terminal" : "Show Terminal",
            revealsMainWindow: true,
            action: onToggleTerminal
        )
        menuActionButton(
            surface.browser.isVisible ? "Hide Browser" : "Show Browser",
            revealsMainWindow: true,
            action: onToggleBrowser
        )
        menuActionButton(
            "Open Browser Session",
            isDisabled: surface.browser.currentURL == nil && !surface.browser.canOpen,
            action: onOpenBrowserSession
        )
        menuActionButton(
            surface.memories.isVisible ? "Hide Memories" : "Show Memories",
            revealsMainWindow: true,
            action: onToggleMemories
        )
        menuActionButton(
            surface.extensions.isVisible ? "Hide Extensions" : "Show Extensions",
            revealsMainWindow: true,
            action: onToggleExtensions
        )
        if surface.topBar.showsComputerUseSetup {
            menuActionButton("Computer Use Setup", revealsMainWindow: true, action: onComputerUseSetup)
        }
        menuActionButton("Settings...", revealsMainWindow: true, action: onSettings)
        menuActionButton("Check for Updates...", revealsMainWindow: true, action: onCheckForUpdates)
        menuActionButton("Report an Issue...", action: onReportIssue)
        Divider()
        menuActionButton("Stop All", isDisabled: stopAllCommand?.isEnabled != true, action: onStopAll)
        menuActionButton(
            "Disconnect All",
            isDisabled: disconnectAllCommand?.isEnabled != true,
            action: onDisconnectAll
        )
        Divider()
        menuActionButton("Quit \(QuillCodeProduct.displayName)", action: onQuit)
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
        revealsMainWindow: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(title) {
            if revealsMainWindow {
                openWindow(id: QuillCodeDesktopSceneID.mainWindow)
            }
            action()
        }
            .buttonStyle(QuillCodePressableButtonStyle())
            .quillCodeFullRowButtonTarget()
            .disabled(isDisabled)
    }
}
