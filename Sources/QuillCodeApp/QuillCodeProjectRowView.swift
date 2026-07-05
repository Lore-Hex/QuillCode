import SwiftUI

struct QuillCodeProjectRowView: View {
    var project: ProjectItemSurface
    var onSelectProject: (UUID?) -> Void
    var onProjectAction: (ProjectItemActionSurface) -> Void

    var body: some View {
        HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
            projectButton
            projectActionMenu
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 0)
    }

    private var projectButton: some View {
        Button {
            onSelectProject(project.id)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                projectTitleRow
                Text(project.path)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(1)
            }
            .padding(.horizontal, QuillCodeMetrics.sidebarVisibleRowHorizontalPadding)
            .frame(
                maxWidth: .infinity,
                minHeight: QuillCodeMetrics.sidebarVisibleRowHeight,
                alignment: .leading
            )
            .background(project.isSelected ? QuillCodePalette.selection : Color.clear)
            .clipShape(RoundedRectangle(
                cornerRadius: QuillCodeMetrics.sidebarVisibleRowRadius,
                style: .continuous
            ))
            .quillCodeFullRowButtonTarget()
        }
        .buttonStyle(QuillCodePressableButtonStyle())
    }

    private var projectTitleRow: some View {
        HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
            Text(project.name)
                .font(.callout.weight(.medium))
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
                .quillCodeIconButtonTarget()
                .foregroundStyle(QuillCodePalette.muted)
        }
        .buttonStyle(QuillCodePressableButtonStyle())
    }

    private var projectActionMenuGeometryReason: String {
        "AppKit owns project action menu rows; the ellipsis trigger carries the custom hit-target contract."
    }
}
