import SwiftUI
import UniformTypeIdentifiers

enum QuillCodeProjectListMetrics {
    static let maxProjectListHeight: CGFloat = 220
    static let rowCornerRadius: CGFloat = 10
}

struct QuillCodeProjectListView: View {
    var projects: ProjectListSurface
    var onSelectProject: (UUID?) -> Void
    var onAddProjectRequested: () -> Void
    var onProjectAction: (ProjectItemActionSurface) -> Void
    var onMoveProjectBefore: (UUID, UUID) -> Bool

    @State private var draggedProjectID: UUID?
    @State private var dropTargetProjectID: UUID?

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
                        .projectDragReorderTarget(
                            projectID: project.id,
                            draggedProjectID: $draggedProjectID,
                            dropTargetProjectID: $dropTargetProjectID,
                            onMoveProjectBefore: onMoveProjectBefore
                        )
                    }
                }
            }
            .frame(maxHeight: QuillCodeProjectListMetrics.maxProjectListHeight)
        }
    }
}

private extension View {
    func projectDragReorderTarget(
        projectID: UUID,
        draggedProjectID: Binding<UUID?>,
        dropTargetProjectID: Binding<UUID?>,
        onMoveProjectBefore: @escaping (UUID, UUID) -> Bool
    ) -> some View {
        modifier(QuillCodeProjectDragReorderModifier(
            projectID: projectID,
            draggedProjectID: draggedProjectID,
            dropTargetProjectID: dropTargetProjectID,
            onMoveProjectBefore: onMoveProjectBefore
        ))
    }
}

private struct QuillCodeProjectDragReorderModifier: ViewModifier {
    let projectID: UUID
    @Binding var draggedProjectID: UUID?
    @Binding var dropTargetProjectID: UUID?
    let onMoveProjectBefore: (UUID, UUID) -> Bool

    func body(content: Content) -> some View {
        content
            .background(dropBackground)
            .onDrag {
                draggedProjectID = projectID
                return NSItemProvider(object: projectID.uuidString as NSString)
            }
            .onDrop(
                of: [UTType.text],
                delegate: QuillCodeProjectDropDelegate(
                    targetProjectID: projectID,
                    draggedProjectID: $draggedProjectID,
                    dropTargetProjectID: $dropTargetProjectID,
                    onMoveProjectBefore: onMoveProjectBefore
                )
            )
    }

    @ViewBuilder
    private var dropBackground: some View {
        if dropTargetProjectID == projectID {
            RoundedRectangle(cornerRadius: QuillCodeProjectListMetrics.rowCornerRadius)
                .fill(QuillCodePalette.blue.opacity(0.14))
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(QuillCodePalette.blue)
                        .frame(height: 2)
                        .padding(.horizontal, 8)
                }
        }
    }
}

private struct QuillCodeProjectDropDelegate: DropDelegate {
    let targetProjectID: UUID
    @Binding var draggedProjectID: UUID?
    @Binding var dropTargetProjectID: UUID?
    let onMoveProjectBefore: (UUID, UUID) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        guard let sourceID = draggedProjectID else {
            return info.hasItemsConforming(to: [UTType.text])
        }
        return sourceID != targetProjectID
    }

    func dropEntered(info: DropInfo) {
        guard draggedProjectID != targetProjectID else { return }
        dropTargetProjectID = targetProjectID
    }

    func dropExited(info: DropInfo) {
        if dropTargetProjectID == targetProjectID {
            dropTargetProjectID = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            draggedProjectID = nil
            dropTargetProjectID = nil
        }
        guard let sourceID = draggedProjectID, sourceID != targetProjectID else {
            return false
        }
        return onMoveProjectBefore(sourceID, targetProjectID)
    }
}
