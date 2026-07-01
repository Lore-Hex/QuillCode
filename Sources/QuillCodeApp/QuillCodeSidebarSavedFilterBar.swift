import SwiftUI

struct QuillCodeSidebarSavedFilterBar: View {
    var filters: [SidebarSavedFilterSurface]
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        LazyVGrid(
            columns: columns,
            alignment: .leading,
            spacing: QuillCodeMetrics.denseControlClusterSpacing
        ) {
            ForEach(filters) { filter in
                savedFilterButton(filter)
            }
        }
    }

    private var columns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: 100),
                spacing: QuillCodeMetrics.denseControlClusterSpacing,
                alignment: .leading
            )
        ]
    }

    private func savedFilterButton(_ filter: SidebarSavedFilterSurface) -> some View {
        Button {
            onCommand(QuillCodeSidebarCommandAdapter.workspaceCommand(for: filter))
        } label: {
            HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                Text(filter.title)
                    .font(.caption.weight(.semibold))
                filterCountBadge(filter)
            }
            .lineLimit(1)
            .quillCodeCapsuleButtonTarget(minWidth: 66)
            .foregroundStyle(filter.isActive ? QuillCodePalette.background : QuillCodePalette.muted)
            .background(filter.isActive ? QuillCodePalette.blue : QuillCodePalette.panel.opacity(0.55))
            .clipShape(Capsule())
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .accessibilityLabel(filter.accessibilityLabel)
        .accessibilityAddTraits(filter.isActive ? .isSelected : [])
        .accessibilityIdentifier("quillcode-sidebar-filter-\(filter.kind.rawValue)")
    }

    private func filterCountBadge(_ filter: SidebarSavedFilterSurface) -> some View {
        Text("\(filter.count)")
            .font(.caption2.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(filter.isActive ? QuillCodePalette.background : QuillCodePalette.muted)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background((filter.isActive ? Color.white : QuillCodePalette.panel).opacity(0.28))
            .clipShape(Capsule())
    }
}
