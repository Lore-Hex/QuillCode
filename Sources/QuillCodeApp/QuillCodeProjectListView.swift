import SwiftUI

enum QuillCodeProjectListMetrics {
    static let maxProjectListHeight: CGFloat = 220
    static let rowCornerRadius: CGFloat = 10
}

struct QuillCodeProjectListView: View {
    var projects: ProjectListSurface
    var onSelectProject: (UUID?) -> Void
    var onAddProjectRequested: () -> Void
    var onProjectAction: (ProjectItemActionSurface) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            projectHeader
            projectRows
        }
    }

    private var projectHeader: some View {
        HStack(spacing: QuillCodeMetrics.minimumTargetClearance) {
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
            .accessibilityLabel("Open project")
            .accessibilityIdentifier("quillcode-sidebar-command-add-project")
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
            .accessibilityLabel("Clear project")
            .accessibilityIdentifier("quillcode-project-clear-button")
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
                LazyVStack(spacing: 2) {
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
