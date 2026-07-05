import Foundation

extension QuillCodeNativeHitTargetAudit {
    static func commandContracts(from commands: [WorkspaceCommandSurface]) -> [QuillCodeNativeHitTargetContract] {
        commands.map(commandContract)
    }

    private static func commandContract(_ command: WorkspaceCommandSurface) -> QuillCodeNativeHitTargetContract {
        let placement = commandPlacement(for: command.id)
        return contract(
            "command.\(command.id)",
            family: placement.family,
            surface: placement.surface,
            label: command.title,
            kind: placement.kind,
            minWidth: placement.minWidth,
            commandID: command.id,
            source: "WorkspaceCommandSurface"
        )
    }

    private static func commandPlacement(for id: String) -> CommandHitTargetPlacement {
        switch id {
        case "add-project":
            return CommandHitTargetPlacement(
                family: .sidebar,
                surface: "Project header",
                kind: .icon,
                minWidth: Double(QuillCodeMetrics.minimumHitTarget)
            )
        case "new-chat", "search", "toggle-extensions", "toggle-automations":
            return CommandHitTargetPlacement(
                family: .sidebar,
                surface: "Sidebar primary",
                kind: .fullRow
            )
        case "toggle-terminal", "toggle-browser", "toggle-memories", "toggle-activity", "command-palette":
            return CommandHitTargetPlacement(
                family: .sidebar,
                surface: "Sidebar tools",
                kind: .fullRow
            )
        case "computer-use-setup", "keyboard-shortcuts", "settings", "disconnect-all":
            return CommandHitTargetPlacement(
                family: .topBar,
                surface: "Top bar overflow",
                kind: .fullRow
            )
        default:
            return CommandHitTargetPlacement(
                family: .commandPalette,
                surface: "Command palette",
                kind: .fullRow
            )
        }
    }
}

private struct CommandHitTargetPlacement {
    var family: QuillCodeInteractionSurfaceFamily
    var surface: String
    var kind: QuillCodeNativeHitTargetKind
    var minWidth: Double?

    init(
        family: QuillCodeInteractionSurfaceFamily,
        surface: String,
        kind: QuillCodeNativeHitTargetKind,
        minWidth: Double? = nil
    ) {
        self.family = family
        self.surface = surface
        self.kind = kind
        self.minWidth = minWidth
    }
}
