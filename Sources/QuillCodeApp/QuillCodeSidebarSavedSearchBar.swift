import SwiftUI

struct QuillCodeSidebarSavedSearchBar: View {
    var savedSearches: [SidebarSavedSearchSurface]
    var createCommand: WorkspaceCommandSurface
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: QuillCodeMetrics.denseControlClusterSpacing) {
            header
            if !savedSearches.isEmpty {
                savedSearchRows
            }
        }
    }

    private var header: some View {
        HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
            Text("Saved searches")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
                .lineLimit(1)
            Spacer()
            Button {
                onCommand(createCommand)
            } label: {
                Label("Save", systemImage: "plus")
                    .labelStyle(.titleAndIcon)
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(QuillCodePressableButtonStyle())
            .quillCodeTextButtonTarget(minWidth: 64)
            .foregroundStyle(QuillCodePalette.blue)
            .accessibilityIdentifier("quillcode-sidebar-saved-search-create")
        }
    }

    private var savedSearchRows: some View {
        VStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
            ForEach(savedSearches) { savedSearch in
                savedSearchRow(savedSearch)
            }
        }
    }

    private func savedSearchRow(_ savedSearch: SidebarSavedSearchSurface) -> some View {
        HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
            savedSearchButton(savedSearch)
            savedSearchMoveButton(savedSearch, direction: .up, systemImage: "chevron.up")
            savedSearchMoveButton(savedSearch, direction: .down, systemImage: "chevron.down")
            savedSearchDeleteButton(savedSearch)
        }
    }

    private func savedSearchButton(_ savedSearch: SidebarSavedSearchSurface) -> some View {
        Button {
            onCommand(QuillCodeSidebarCommandAdapter.workspaceCommand(for: savedSearch))
        } label: {
            HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .imageScale(.small)
                Text(savedSearch.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                savedSearchCountBadge(savedSearch)
            }
            .padding(.horizontal, 8)
            .frame(minWidth: 124, minHeight: 30, alignment: .leading)
            .foregroundStyle(savedSearch.isActive ? QuillCodePalette.background : QuillCodePalette.muted)
            .background(savedSearch.isActive ? QuillCodePalette.blue : QuillCodePalette.panel.opacity(0.45))
            .clipShape(Capsule())
            .quillCodeCapsuleButtonTarget(minWidth: 124, alignment: .leading)
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .accessibilityLabel(savedSearch.accessibilityLabel)
        .accessibilityAddTraits(savedSearch.isActive ? .isSelected : [])
        .help(savedSearch.query)
        .accessibilityIdentifier("quillcode-sidebar-saved-search")
    }

    private func savedSearchCountBadge(_ savedSearch: SidebarSavedSearchSurface) -> some View {
        Text("\(savedSearch.count)")
            .font(.caption2.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(savedSearch.isActive ? QuillCodePalette.background : QuillCodePalette.muted)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background((savedSearch.isActive ? Color.white : QuillCodePalette.panel).opacity(0.28))
            .clipShape(Capsule())
    }

    private func savedSearchMoveButton(
        _ savedSearch: SidebarSavedSearchSurface,
        direction: SidebarSavedSearchMoveDirection,
        systemImage: String
    ) -> some View {
        let command = QuillCodeSidebarCommandAdapter.moveWorkspaceCommand(
            for: savedSearch,
            direction: direction
        )
        return Button {
            onCommand(command)
        } label: {
            Image(systemName: systemImage)
                .imageScale(.small)
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .quillCodeIconButtonTarget()
        .foregroundStyle(command.isEnabled ? QuillCodePalette.blue : QuillCodePalette.muted)
        .disabled(!command.isEnabled)
        .accessibilityLabel("Move saved search \(savedSearch.title) \(direction.rawValue)")
        .accessibilityIdentifier("quillcode-sidebar-saved-search-move-\(direction.rawValue)")
    }

    private func savedSearchDeleteButton(_ savedSearch: SidebarSavedSearchSurface) -> some View {
        Button {
            onCommand(QuillCodeSidebarCommandAdapter.deleteWorkspaceCommand(for: savedSearch))
        } label: {
            Image(systemName: "trash")
                .imageScale(.small)
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .quillCodeIconButtonTarget()
        .foregroundStyle(QuillCodePalette.red)
        .accessibilityLabel("Delete saved search \(savedSearch.title)")
        .accessibilityIdentifier("quillcode-sidebar-saved-search-delete")
    }
}
