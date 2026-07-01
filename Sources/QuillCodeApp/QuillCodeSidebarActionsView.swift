import SwiftUI

struct QuillCodeSidebarActionsView: View {
    var commands: [WorkspaceCommandSurface]
    var onCommand: (WorkspaceCommandSurface) -> Void

    private var visibleCommands: [WorkspaceCommandSurface] {
        QuillCodeSidebarCommandPresentation.primaryCommandIDs.compactMap { id in
            commands.first { $0.id == id }
        }
    }

    var body: some View {
        VStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            ForEach(visibleCommands) { command in
                Button {
                    onCommand(command)
                } label: {
                    Label(
                        QuillCodeSidebarCommandPresentation.displayTitle(for: command),
                        systemImage: QuillCodeSidebarCommandPresentation.systemImage(for: command.id)
                    )
                    .quillCodeFullRowButtonTarget()
                    .padding(.horizontal, 10)
                    .background(primaryCommandBackground(command))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(QuillCodePressableButtonStyle())
                .disabled(!command.isEnabled)
                .accessibilityIdentifier("quillcode-sidebar-command-\(command.id)")
            }
        }
    }

    private func primaryCommandBackground(_ command: WorkspaceCommandSurface) -> Color {
        command.id == "new-chat" ? QuillCodePalette.panel.opacity(0.74) : Color.clear
    }
}
