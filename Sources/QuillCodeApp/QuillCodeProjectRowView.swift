import SwiftUI

struct QuillCodeProjectRowView: View {
    var project: ProjectItemSurface
    var onSelectProject: (UUID?) -> Void
    var onProjectAction: (ProjectItemActionSurface) -> Void

    var body: some View {
        HStack(spacing: QuillCodeMetrics.sidebarControlSpacing) {
            projectButton
            projectActionMenu
        }
        .padding(.vertical, 0)
        .help("\(project.path) · Drag to reorder")
    }

    private var projectButton: some View {
        Button {
            onSelectProject(project.id)
        } label: {
            HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                Image(systemName: project.isRemote ? "network" : "folder")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(project.isRemote ? QuillCodePalette.blue : QuillCodePalette.muted)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Text(project.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .layoutPriority(1)
                if project.isRemote {
                    Text("SSH")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(QuillCodePalette.blue)
                }
                Spacer(minLength: 0)
            }
            .quillCodeSidebarRowChrome(background: project.isSelected ? QuillCodePalette.selection : Color.clear)
        }
        .buttonStyle(QuillCodePressableButtonStyle(enforcesMinimumHitTarget: false))
        .accessibilityLabel(project.accessibilityLabel)
        .accessibilityHint("Selects this project. Drag the row to reorder it.")
    }

    private var projectActionMenu: some View {
        Menu {
            ForEach(project.actions) { action in
                Button(role: action.kind == .remove ? .destructive : nil) {
                    onProjectAction(action)
                } label: {
                    Text(action.kind.title)
                }
                .quillCodePlatformMenuItemTarget(reason: projectActionMenuGeometryReason)
                .accessibilityLabel(action.accessibilityLabel(projectName: project.name))
                .disabled(!action.isEnabled)
                .help(action.helpText(projectName: project.name))
            }
        } label: {
            Image(systemName: "ellipsis")
                .quillCodeSidebarIconButtonTarget()
                .foregroundStyle(QuillCodePalette.muted)
        }
        .buttonStyle(QuillCodePressableButtonStyle(enforcesMinimumHitTarget: false))
        .accessibilityLabel(project.actionMenuAccessibilityLabel)
        .accessibilityHint(project.actionMenuHelp)
        .help(project.actionMenuHelp)
    }

    private var projectActionMenuGeometryReason: String {
        "AppKit owns project action menu rows; the ellipsis trigger carries the custom hit-target contract."
    }
}
