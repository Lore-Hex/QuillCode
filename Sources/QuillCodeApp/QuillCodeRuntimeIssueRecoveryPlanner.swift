enum RuntimeIssueRecoveryAction: Hashable, Sendable {
    case command(WorkspaceCommandSurface)
    case presentModelPicker
}

struct RuntimeIssueRecoveryPlanner: Sendable, Hashable {
    var commands: [WorkspaceCommandSurface]

    func action(for issue: RuntimeIssueSurface?) -> RuntimeIssueRecoveryAction? {
        if let recovery = issue?.recovery {
            return action(for: recovery)
        }
        guard let actionLabel = issue?.actionLabel else { return nil }

        switch actionLabel {
        case "Open Settings", "Add key", "Fix key":
            return enabledCommand(id: "settings").map(RuntimeIssueRecoveryAction.command)
        case "Retry":
            return enabledCommand(id: "retry-last-turn").map(RuntimeIssueRecoveryAction.command)
        case "Switch model":
            return .presentModelPicker
        default:
            return nil
        }
    }

    private func action(for recovery: RuntimeRecoveryTelemetry) -> RuntimeIssueRecoveryAction? {
        switch recovery.route {
        case .settings:
            return enabledCommand(id: recovery.commandID ?? "settings").map(RuntimeIssueRecoveryAction.command)
        case .retryLastTurn:
            return enabledCommand(id: recovery.commandID ?? "retry-last-turn").map(RuntimeIssueRecoveryAction.command)
        case .modelPicker:
            return .presentModelPicker
        }
    }

    private func enabledCommand(id: String) -> WorkspaceCommandSurface? {
        commands.first { $0.id == id && $0.isEnabled }
    }
}
