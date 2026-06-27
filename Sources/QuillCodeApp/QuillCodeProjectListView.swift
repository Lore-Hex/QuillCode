import SwiftUI

private enum QuillCodeProjectListMetrics {
    static let maxProjectListHeight: CGFloat = 220
    static let rowCornerRadius: CGFloat = 10
}

struct QuillCodeProjectListView: View {
    var projects: ProjectListSurface
    var onSelectProject: (UUID?) -> Void
    var onAddProjectRequested: () -> Void
    var onProjectAction: (ProjectItemActionSurface) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            projectHeader
            projectRows
        }
    }

    private var projectHeader: some View {
        HStack {
            Text(projects.title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
            Spacer()
            Button(action: onAddProjectRequested) {
                Image(systemName: "plus.circle")
                    .imageScale(.small)
                    .quillCodeIconButtonTarget()
            }
            .buttonStyle(QuillCodePressableButtonStyle())
            .foregroundStyle(QuillCodePalette.muted)
            .help("Open project")
            Button {
                onSelectProject(nil)
            } label: {
                Image(systemName: "xmark.circle")
                    .imageScale(.small)
                    .quillCodeIconButtonTarget()
            }
            .buttonStyle(QuillCodePressableButtonStyle())
            .foregroundStyle(QuillCodePalette.muted)
            .help("Clear project")
        }
    }

    @ViewBuilder
    private var projectRows: some View {
        if projects.items.isEmpty {
            Text(projects.emptyTitle)
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(projects.items) { project in
                        QuillCodeProjectRowView(
                            project: project,
                            onSelectProject: onSelectProject,
                            onProjectAction: onProjectAction
                        )
                    }
                }
            }
            .frame(maxHeight: QuillCodeProjectListMetrics.maxProjectListHeight)
        }
    }
}

private struct QuillCodeProjectRowView: View {
    var project: ProjectItemSurface
    var onSelectProject: (UUID?) -> Void
    var onProjectAction: (ProjectItemActionSurface) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button {
                onSelectProject(project.id)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(project.name)
                            .font(.callout.weight(.semibold))
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
                    Text(project.path)
                        .font(.caption)
                        .foregroundStyle(QuillCodePalette.muted)
                        .lineLimit(1)
                }
                .quillCodeFullRowButtonTarget()
            }
            .buttonStyle(QuillCodePressableButtonStyle())

            Menu {
                ForEach(project.actions) { action in
                    Button(role: action.kind == .remove ? .destructive : nil) {
                        onProjectAction(action)
                    } label: {
                        Text(action.kind.title)
                    }
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
        .padding(10)
        .background(project.isSelected ? QuillCodePalette.selection : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: QuillCodeProjectListMetrics.rowCornerRadius, style: .continuous))
    }
}
