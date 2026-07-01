import SwiftUI

struct QuillCodeTopBarNavigationView: View {
    var topBar: TopBarSurface
    var commands: [WorkspaceCommandSurface]
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
            navigationButton(
                commandID: "workspace-back",
                systemImage: "chevron.left",
                accessibilityLabel: "Back",
                fallbackEnabled: topBar.canNavigateBack
            )
            navigationButton(
                commandID: "workspace-forward",
                systemImage: "chevron.right",
                accessibilityLabel: "Forward",
                fallbackEnabled: topBar.canNavigateForward
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspace navigation")
    }

    @ViewBuilder
    private func navigationButton(
        commandID: String,
        systemImage: String,
        accessibilityLabel: String,
        fallbackEnabled: Bool
    ) -> some View {
        let command = command(for: commandID, title: accessibilityLabel, fallbackEnabled: fallbackEnabled)
        Button {
            guard command.isEnabled else { return }
            onCommand(command)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(command.isEnabled ? QuillCodePalette.muted : QuillCodePalette.muted.opacity(0.42))
                .accessibilityHidden(true)
        }
        .quillCodeIconButtonTarget()
        .background(QuillCodePalette.selection.opacity(command.isEnabled ? 0.18 : 0.12))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(QuillCodePalette.selection.opacity(command.isEnabled ? 0.34 : 0.24), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .buttonStyle(QuillCodePressableButtonStyle())
        .disabled(!command.isEnabled)
        .help(command.isEnabled ? command.title : "\(accessibilityLabel) unavailable")
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("quillcode-top-bar-\(commandID)")
    }

    private func command(
        for commandID: String,
        title: String,
        fallbackEnabled: Bool
    ) -> WorkspaceCommandSurface {
        commands.first { $0.id == commandID } ?? WorkspaceCommandSurface(
            id: commandID,
            title: title,
            category: WorkspaceCommandPalette.navigationCategory,
            keywords: [],
            isEnabled: fallbackEnabled
        )
    }
}
