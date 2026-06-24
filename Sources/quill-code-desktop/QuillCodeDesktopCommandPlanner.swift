import QuillCodeApp

enum QuillCodeDesktopCommandAction {
    case newChat
    case addProject
    case toggleTerminal
    case toggleBrowser
    case openBrowserSession
    case toggleExtensions
    case toggleMemories
    case commandPalette
    case settings
    case openComputerUseSystemSettings(MacSystemSettingsOpener.Destination)
    case refreshComputerUseStatus
    case stopAll
    case disconnectAll
    case retryLastTurn
    case workspaceCommand(String)
}

enum QuillCodeDesktopCommandPlanner {
    static func action(for command: WorkspaceCommandSurface) -> QuillCodeDesktopCommandAction {
        switch command.id {
        case "new-chat":
            return .newChat
        case "add-project":
            return .addProject
        case "toggle-terminal":
            return .toggleTerminal
        case "toggle-browser":
            return .toggleBrowser
        case "open-browser-session":
            return .openBrowserSession
        case "toggle-extensions":
            return .toggleExtensions
        case "toggle-memories":
            return .toggleMemories
        case "command-palette":
            return .commandPalette
        case "settings", "computer-use-setup":
            return .settings
        case "computer-use-open-screen-recording":
            return .openComputerUseSystemSettings(.screenRecording)
        case "computer-use-open-accessibility":
            return .openComputerUseSystemSettings(.accessibility)
        case "computer-use-refresh":
            return .refreshComputerUseStatus
        case "stop-all":
            return .stopAll
        case "disconnect-all":
            return .disconnectAll
        case "retry-last-turn":
            return .retryLastTurn
        default:
            return .workspaceCommand(command.id)
        }
    }
}
