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
        VStack(spacing: 2) {
            ForEach(visibleCommands) { command in
                Button {
                    onCommand(command)
                } label: {
                    Label(
                        QuillCodeSidebarCommandPresentation.displayTitle(for: command),
                        systemImage: QuillCodeSidebarCommandPresentation.systemImage(for: command.id)
                    )
                    .font(.callout.weight(.medium))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                    .foregroundStyle(command.isEnabled ? QuillCodePalette.text : QuillCodePalette.muted)
                    .background(primaryCommandBackground(command))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .quillCodeFullRowButtonTarget()
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
