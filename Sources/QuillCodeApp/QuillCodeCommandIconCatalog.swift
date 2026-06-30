enum QuillCodeCommandIconCatalog {
    static func systemImage(for commandID: String, fallback: String = "command") -> String {
        if commandID.hasPrefix(SlashCommandCatalog.commandPaletteIDPrefix) {
            return "slash.circle"
        }
        if commandID.hasPrefix("local-env:") {
            return "hammer"
        }
        if let pullRequestIcon = WorkspacePullRequestCommandCatalog.systemImage(for: commandID) {
            return pullRequestIcon
        }

        switch commandID {
        case "new-chat":
            return "square.and.pencil"
        case "cycle-mode":
            return "arrow.triangle.2.circlepath"
        case "focus-composer":
            return "text.cursor"
        case "toggle-sidebar":
            return "sidebar.leading"
        case "workspace-back":
            return "chevron.left"
        case "workspace-forward":
            return "chevron.right"
        case "search":
            return "magnifyingglass"
        case "command-palette":
            return "command"
        case "find-in-chat":
            return "text.magnifyingglass"
        case "add-project":
            return "folder.badge.plus"
        case "project-new-chat":
            return "plus.message"
        case "project-refresh-context":
            return "arrow.clockwise"
        case "project-init":
            return "doc.badge.plus"
        case "project-rename":
            return "text.cursor"
        case "project-remove":
            return "minus.circle"
        case "toggle-terminal":
            return "terminal"
        case "terminal-clear":
            return "clear"
        case "toggle-browser":
            return "globe"
        case "open-browser-session":
            return "person.crop.circle.badge.checkmark"
        case "toggle-activity":
            return "list.bullet.rectangle"
        case "toggle-automations":
            return "clock.arrow.circlepath"
        case "toggle-memories", "memory-add":
            return "brain.head.profile"
        case "toggle-extensions":
            return "puzzlepiece.extension"
        case "git-worktree-list":
            return "point.3.connected.trianglepath.dotted"
        case "git-worktree-create":
            return "plus.rectangle.on.folder"
        case "git-worktree-open":
            return "rectangle.on.rectangle"
        case "git-worktree-remove":
            return "minus.rectangle"
        case "git-worktree-prune":
            return "trash.slash"
        case "settings":
            return "gearshape"
        case "keyboard-shortcuts":
            return "keyboard"
        case "computer-use-setup":
            return "display"
        case "stop-all":
            return "stop.circle"
        case "disconnect-all":
            return "network.slash"
        default:
            return fallback
        }
    }
}
