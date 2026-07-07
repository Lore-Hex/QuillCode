import SwiftUI

struct QuillCodeAutomationCreateMenu: View {
    var automations: WorkspaceAutomationsSurface
    var onCommand: (WorkspaceCommandSurface) -> Void

    private static let menuTargetReason =
        "AppKit owns automation menu row geometry; the Create trigger carries the custom hit-target contract."

    var body: some View {
        if hasCreateCommands {
            Menu {
                ForEach(commandGroups) { group in
                    if group.startsNewSection {
                        Divider()
                    }
                    ForEach(group.commands, id: \.id) { command in
                        Button(command.title) { onCommand(command) }
                            .quillCodePlatformMenuItemTarget(reason: Self.menuTargetReason)
                            .disabled(!command.isEnabled)
                    }
                }
            } label: {
                Label("Create", systemImage: "plus")
            }
            .buttonStyle(QuillCodeActionButtonStyle(.primary, minWidth: 90))
            .quillCodeFormActionTarget(minWidth: 90)
            .accessibilityIdentifier("quillcode-automation-create")
        }
    }

    private var hasCreateCommands: Bool {
        automations.createThreadFollowUpCommand != nil
            || automations.createWorkspaceScheduleCommand != nil
            || automations.createMonitorCommand != nil
            || !automations.scheduleThreadFollowUpCommands.isEmpty
            || !automations.scheduleWorkspaceScheduleCommands.isEmpty
    }

    private var commandGroups: [CommandGroup] {
        [
            CommandGroup(commands: primaryCreateCommands),
            CommandGroup(
                commands: automations.scheduleThreadFollowUpCommands,
                startsNewSection: true
            ),
            CommandGroup(
                commands: automations.scheduleWorkspaceScheduleCommands,
                startsNewSection: true
            )
        ]
        .filter { !$0.commands.isEmpty }
    }

    private var primaryCreateCommands: [WorkspaceCommandSurface] {
        [
            automations.createThreadFollowUpCommand,
            automations.createWorkspaceScheduleCommand,
            automations.createMonitorCommand
        ].compactMap { $0 }
    }

    private struct CommandGroup: Identifiable {
        var id: String { commands.map(\.id).joined(separator: "|") }
        var commands: [WorkspaceCommandSurface]
        var startsNewSection = false
    }
}
