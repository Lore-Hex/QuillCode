import Foundation

@MainActor
protocol QuillCodeDesktopCommandPerforming: AnyObject {
    func newChat()
    func requestAddProject()
    func toggleTerminal()
    func toggleBrowser()
    func openBrowserSession()
    func toggleExtensions()
    func stopWorkflowRecording()
    func toggleMemories()
    func toggleActivity()
    func toggleAutomations()
    func openCommandPalette()
    func openKeyboardShortcuts()
    func openSearch()
    func openFind()
    func startDictation()
    func openSettings()
    func openComputerUseSystemSettings(_ destination: MacSystemSettingsOpener.Destination)
    func refreshComputerUseStatus()
    func stopAll()
    func disconnectAll()
    func retryLastTurn()
    func copyCurrentConversation()
    func exportCurrentConversationMarkdown()
    func runWorkspaceCommand(_ commandID: String)
}

@MainActor
struct QuillCodeDesktopCommandCoordinator {
    func run(
        _ action: QuillCodeDesktopCommandAction,
        performer: any QuillCodeDesktopCommandPerforming
    ) {
        switch action {
        case .newChat:
            performer.newChat()
        case .addProject:
            performer.requestAddProject()
        case .toggleTerminal:
            performer.toggleTerminal()
        case .toggleBrowser:
            performer.toggleBrowser()
        case .openBrowserSession:
            performer.openBrowserSession()
        case .toggleExtensions:
            performer.toggleExtensions()
        case .stopWorkflowRecording:
            performer.stopWorkflowRecording()
        case .toggleMemories:
            performer.toggleMemories()
        case .toggleActivity:
            performer.toggleActivity()
        case .toggleAutomations:
            performer.toggleAutomations()
        case .commandPalette:
            performer.openCommandPalette()
        case .keyboardShortcuts:
            performer.openKeyboardShortcuts()
        case .search:
            performer.openSearch()
        case .find:
            performer.openFind()
        case .dictation:
            performer.startDictation()
        case .settings:
            performer.openSettings()
        case .openComputerUseSystemSettings(let destination):
            performer.openComputerUseSystemSettings(destination)
        case .refreshComputerUseStatus:
            performer.refreshComputerUseStatus()
        case .stopAll:
            performer.stopAll()
        case .disconnectAll:
            performer.disconnectAll()
        case .retryLastTurn:
            performer.retryLastTurn()
        case .copyConversation:
            performer.copyCurrentConversation()
        case .exportConversationMarkdown:
            performer.exportCurrentConversationMarkdown()
        case .workspaceCommand(let commandID):
            performer.runWorkspaceCommand(commandID)
        }
    }
}
