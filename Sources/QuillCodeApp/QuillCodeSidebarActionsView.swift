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
        VStack(spacing: 0) {
            ForEach(visibleCommands) { command in
                Button {
                    onCommand(command)
                } label: {
                    sidebarCommandLabel(command)
                }
                .buttonStyle(QuillCodePressableButtonStyle(enforcesMinimumHitTarget: false))
                .quillCodeFullRowButtonTarget(
                    minHeight: QuillCodeMetrics.sidebarVisibleRowHeight,
                    radius: QuillCodeMetrics.sidebarVisibleRowRadius
                )
                .disabled(!command.isEnabled)
                .accessibilityIdentifier("quillcode-sidebar-command-\(command.id)")
            }
        }
    }

    private func sidebarCommandLabel(_ command: WorkspaceCommandSurface) -> some View {
        HStack(spacing: 8) {
            Image(systemName: QuillCodeSidebarCommandPresentation.systemImage(for: command.id))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(command.isEnabled ? QuillCodePalette.muted : QuillCodePalette.muted.opacity(0.48))
                .frame(width: 18, alignment: .center)
                .accessibilityHidden(true)

            Text(QuillCodeSidebarCommandPresentation.displayTitle(for: command))
                .font(.system(size: 13.25, weight: command.id == "new-chat" ? .semibold : .medium))
                .foregroundStyle(command.isEnabled ? QuillCodePalette.text : QuillCodePalette.muted)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .quillCodeSidebarRowChrome()
    }
}
