import SwiftUI

struct QuillCodeAutomationWorkflowCard: View {
    var workflow: AutomationWorkflowSurface
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Text(workflow.title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
            Text(workflow.detail)
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
                .lineLimit(3)
            actions
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .background(QuillCodePalette.background.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(workflow.scheduleLabel)
                .font(.caption2.weight(.bold))
                .foregroundStyle(QuillCodePalette.blue)
            Spacer()
            Text(workflow.statusLabel)
                .font(.caption2.weight(.bold))
                .foregroundStyle(QuillCodePalette.muted)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if hasActions {
            Divider()
            HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                runButton
                primaryButton
                deleteButton
            }
            .font(.caption.weight(.semibold))
        }
    }

    private var hasActions: Bool {
        workflow.runCommandID != nil
            || workflow.primaryCommandID != nil
            || workflow.deleteCommandID != nil
    }

    @ViewBuilder
    private var runButton: some View {
        if let commandID = workflow.runCommandID,
           let actionTitle = workflow.runActionTitle {
            actionButton(
                title: actionTitle,
                commandID: commandID,
                tone: .primary
            )
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        if let commandID = workflow.primaryCommandID,
           let actionTitle = workflow.primaryActionTitle {
            actionButton(
                title: actionTitle,
                commandID: commandID
            )
        }
    }

    @ViewBuilder
    private var deleteButton: some View {
        if let commandID = workflow.deleteCommandID {
            Button("Delete", role: .destructive) {
                onCommand(automationCommand(id: commandID, title: "Delete automation"))
            }
            .buttonStyle(QuillCodeActionButtonStyle(.destructive))
            .quillCodeFormActionTarget()
        }
    }

    private func actionButton(
        title: String,
        commandID: String,
        tone: QuillCodeActionButtonStyle.Tone = .secondary
    ) -> some View {
        Button(title) {
            onCommand(automationCommand(id: commandID, title: title))
        }
        .buttonStyle(QuillCodeActionButtonStyle(tone))
        .quillCodeFormActionTarget()
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
