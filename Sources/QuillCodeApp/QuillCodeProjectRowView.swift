import SwiftUI

struct QuillCodeProjectRowView: View {
    var project: ProjectItemSurface
    var onSelectProject: (UUID?) -> Void
    var onProjectAction: (ProjectItemActionSurface) -> Void

    var body: some View {
        HStack(spacing: QuillCodeMetrics.sidebarControlSpacing) {
            projectDragHandle
            projectButton
            projectActionMenu
        }
        .padding(.vertical, 0)
        .help("Drag to reorder project")
    }

    private var projectDragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(QuillCodePalette.muted.opacity(0.72))
            .frame(
                width: QuillCodeMetrics.sidebarIconTargetSize,
                height: QuillCodeMetrics.sidebarInteractionRowHeight
            )
            .accessibilityHidden(true)
    }

    private var projectButton: some View {
        Button {
            onSelectProject(project.id)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                projectTitleRow
                Text(project.path)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(1)
            }
            .quillCodeSidebarRowChrome(background: project.isSelected ? QuillCodePalette.selection : Color.clear)
        }
        .buttonStyle(QuillCodePressableButtonStyle(enforcesMinimumHitTarget: false))
        .accessibilityLabel(project.accessibilityLabel)
        .accessibilityHint("Selects this project. Drag the row to reorder it.")
    }

    private var projectTitleRow: some View {
        HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
            Text(project.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            if let selectionLabel = project.selectionLabel {
                Text(selectionLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(QuillCodePalette.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(QuillCodePalette.green.opacity(0.14))
                    .clipShape(Capsule())
            }
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
