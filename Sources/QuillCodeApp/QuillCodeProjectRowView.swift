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
    }

    private var projectButton: some View {
        Button {
            onSelectProject(project.id)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                projectTitleRow
                Text(project.path)
                    .font(.system(size: 11.25, weight: .regular))
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(1)
            }
            .quillCodeSidebarRowChrome(background: project.isSelected ? QuillCodePalette.selection : Color.clear)
        }
        .buttonStyle(QuillCodePressableButtonStyle(enforcesMinimumHitTarget: false))
    }

    private var projectTitleRow: some View {
        HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
            Text(project.name)
                .font(.system(size: 13.25, weight: .medium))
                .lineLimit(1)
            if project.isRemote {
                Text(project.connectionKindLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(QuillCodePalette.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(QuillCodePalette.blue.opacity(0.14))
                    .clipShape(Capsule())
            }
        }
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
                .disabled(!action.isEnabled)
                .help(action.disabledReason ?? action.kind.title)
            }
        } label: {
            Image(systemName: "ellipsis")
                .quillCodeSidebarIconButtonTarget()
                .foregroundStyle(QuillCodePalette.muted)
        }
        .buttonStyle(QuillCodePressableButtonStyle(enforcesMinimumHitTarget: false))
    }

    private var projectActionMenuGeometryReason: String {
        "AppKit owns project action menu rows; the ellipsis trigger carries the custom hit-target contract."
    }
}
