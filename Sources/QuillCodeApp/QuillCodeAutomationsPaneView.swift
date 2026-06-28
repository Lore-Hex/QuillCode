import SwiftUI

struct QuillCodeAutomationsPaneView: View {
    var automations: WorkspaceAutomationsSurface
    var onCommand: (WorkspaceCommandSurface) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 220), spacing: 10, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if automations.workflows.isEmpty {
                QuillCodePaneEmptyStateView(
                    title: automations.emptyTitle,
                    subtitle: automations.emptySubtitle
                )
            } else {
                automationGrid
            }
        }
        .padding(14)
        .frame(minHeight: 190)
        .background(QuillCodePalette.panel)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(QuillCodePalette.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(automations.title)
                    .font(.headline)
                Text(automations.subtitle)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(2)
            }
            Spacer()
            createMenu
            Text(automations.statusLabel)
                .font(.caption.weight(.semibold))
                .fontDesign(.rounded)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(QuillCodePalette.blue.opacity(0.14))
                .foregroundStyle(QuillCodePalette.blue)
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private var createMenu: some View {
        if automations.createThreadFollowUpCommand != nil
            || automations.createWorkspaceScheduleCommand != nil
            || !automations.scheduleThreadFollowUpCommands.isEmpty
            || !automations.scheduleWorkspaceScheduleCommands.isEmpty {
            Menu {
                if let createCommand = automations.createThreadFollowUpCommand {
                    Button(createCommand.title) {
                        onCommand(createCommand)
                    }
                    .disabled(!createCommand.isEnabled)
                }
                if let createCommand = automations.createWorkspaceScheduleCommand {
                    Button(createCommand.title) {
                        onCommand(createCommand)
                    }
                    .disabled(!createCommand.isEnabled)
                }
                if !automations.scheduleThreadFollowUpCommands.isEmpty {
                    Divider()
                    ForEach(automations.scheduleThreadFollowUpCommands, id: \.id) { command in
                        Button(command.title) {
                            onCommand(command)
                        }
                        .disabled(!command.isEnabled)
                    }
                }
                if !automations.scheduleWorkspaceScheduleCommands.isEmpty {
                    Divider()
                    ForEach(automations.scheduleWorkspaceScheduleCommands, id: \.id) { command in
                        Button(command.title) {
                            onCommand(command)
                        }
                        .disabled(!command.isEnabled)
                    }
                }
            } label: {
                Label("Create", systemImage: "plus")
            }
            .buttonStyle(QuillCodeActionButtonStyle(.primary, minWidth: 90))
            .quillCodeFormActionTarget(minWidth: 90)
        }
    }

    private var automationGrid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(automations.workflows) { workflow in
                automationCard(workflow)
            }
        }
    }

    private func automationCard(_ workflow: AutomationWorkflowSurface) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(workflow.scheduleLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(QuillCodePalette.blue)
                Spacer()
                Text(workflow.statusLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(QuillCodePalette.muted)
            }
            Text(workflow.title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
            Text(workflow.detail)
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
                .lineLimit(3)
            automationActions(for: workflow)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .background(QuillCodePalette.background.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func automationActions(for workflow: AutomationWorkflowSurface) -> some View {
        if workflow.runCommandID != nil || workflow.primaryCommandID != nil || workflow.deleteCommandID != nil {
            Divider()
            HStack(spacing: 8) {
                if let commandID = workflow.runCommandID,
                   let actionTitle = workflow.runActionTitle {
                    Button(actionTitle) {
                        onCommand(automationCommand(id: commandID, title: actionTitle))
                    }
                    .buttonStyle(QuillCodeActionButtonStyle(.primary))
                    .quillCodeFormActionTarget()
                }
                if let commandID = workflow.primaryCommandID,
                   let actionTitle = workflow.primaryActionTitle {
                    Button(actionTitle) {
                        onCommand(automationCommand(id: commandID, title: actionTitle))
                    }
                    .buttonStyle(QuillCodeActionButtonStyle())
                    .quillCodeFormActionTarget()
                }
                if let commandID = workflow.deleteCommandID {
                    Button("Delete", role: .destructive) {
                        onCommand(automationCommand(id: commandID, title: "Delete automation"))
                    }
                    .buttonStyle(QuillCodeActionButtonStyle(.destructive))
                    .quillCodeFormActionTarget()
                }
            }
            .font(.caption.weight(.semibold))
        }
    }

    private func automationCommand(id: String, title: String) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(
            id: id,
            title: title,
            category: WorkspaceCommandPalette.automationsCategory,
            keywords: ["automation", "schedule", "follow-up"]
        )
    }
}
