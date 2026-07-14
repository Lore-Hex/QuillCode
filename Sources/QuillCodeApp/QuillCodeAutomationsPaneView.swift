import SwiftUI

struct QuillCodeAutomationsPaneView: View {
    var automations: WorkspaceAutomationsSurface
    var onClose: () -> Void
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
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(QuillCodePalette.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(automations.title)
                    .font(.headline)
                    .accessibilityIdentifier("quillcode-automations-title")
                Text(automations.subtitle)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(2)
            }
            Spacer()
            QuillCodeAutomationCreateMenu(
                automations: automations,
                onCommand: onCommand
            )
            Text(automations.statusLabel)
                .font(.caption.weight(.semibold))
                .fontDesign(.rounded)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(QuillCodePalette.blue.opacity(0.14))
                .foregroundStyle(QuillCodePalette.blue)
                .clipShape(Capsule())
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .quillCodeIconButtonTarget()
            }
            .buttonStyle(QuillCodePressableButtonStyle())
            .help("Close Automations")
            .accessibilityLabel("Close Automations")
            .accessibilityIdentifier("quillcode-automations-close")
        }
    }

    private var automationGrid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(automations.workflows) { workflow in
                QuillCodeAutomationWorkflowCard(
                    workflow: workflow,
                    onCommand: onCommand
                )
            }
        }
    }
}
