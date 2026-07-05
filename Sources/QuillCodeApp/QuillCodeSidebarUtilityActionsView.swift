import SwiftUI

struct QuillCodeSidebarUtilityActionsView: View {
    var commands: [WorkspaceCommandSurface]
    var onCommand: (WorkspaceCommandSurface) -> Void

    private var visibleCommandGroups: [QuillCodeSidebarVisibleCommandGroup] {
        QuillCodeSidebarCommandPresentation.visibleUtilityCommandGroups(from: commands)
    }

    private var settingsCommand: WorkspaceCommandSurface? {
        commands.first { $0.id == "settings" }
    }

    var body: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            toolsMenu
            if let settingsCommand {
                settingsButton(settingsCommand)
            }
        }
        .padding(.top, 6)
    }

    private var toolsMenu: some View {
        Menu {
            ForEach(visibleCommandGroups) { group in
                Section(group.title) {
                    ForEach(group.commands) { command in
                        Button {
                            onCommand(command)
                        } label: {
                            Label(
                                QuillCodeSidebarCommandPresentation.displayTitle(for: command),
                                systemImage: QuillCodeSidebarCommandPresentation.systemImage(for: command.id)
                            )
                        }
                        .quillCodePlatformMenuItemTarget(reason: menuGeometryReason)
                        .disabled(!command.isEnabled)
                    }
                }
            }
        } label: {
            Label("Tools", systemImage: "wrench.and.screwdriver")
                .font(.callout.weight(.medium))
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .center)
                .foregroundStyle(QuillCodePalette.muted)
                .background(QuillCodePalette.panel.opacity(0.50))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .quillCodeFullRowButtonTarget(alignment: .center, radius: 10)
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .help("Tools")
        .accessibilityIdentifier("quillcode-sidebar-tools-button")
    }

    private func settingsButton(_ command: WorkspaceCommandSurface) -> some View {
        Button {
            onCommand(command)
        } label: {
            Label(
                QuillCodeSidebarCommandPresentation.displayTitle(for: command),
                systemImage: QuillCodeSidebarCommandPresentation.systemImage(for: command.id)
            )
            .font(.callout.weight(.medium))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .center)
            .foregroundStyle(settingsForeground(command))
            .background(QuillCodePalette.panel.opacity(0.50))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .quillCodeFullRowButtonTarget(alignment: .center, radius: 10)
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .disabled(!command.isEnabled)
        .help(QuillCodeSidebarCommandPresentation.displayTitle(for: command))
        .accessibilityLabel(QuillCodeSidebarCommandPresentation.displayTitle(for: command))
        .accessibilityIdentifier("quillcode-sidebar-command-\(command.id)")
    }

    private func settingsForeground(_ command: WorkspaceCommandSurface) -> Color {
        let enabledOpacity = 1.0
        let disabledOpacity = 0.45
        return QuillCodePalette.muted.opacity(command.isEnabled ? enabledOpacity : disabledOpacity)
    }

    private var menuGeometryReason: String {
        "AppKit owns menu row geometry; the visible sidebar trigger carries the custom hit-target contract."
    }
}
