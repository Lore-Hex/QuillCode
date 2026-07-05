import SwiftUI

struct QuillCodeSidebarSavedFilterBar: View {
    var filters: [SidebarSavedFilterSurface]
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        LazyVGrid(
            columns: columns,
            alignment: .leading,
            spacing: QuillCodeMetrics.minimumTargetClearance
        ) {
            ForEach(filters) { filter in
                savedFilterButton(filter)
            }
        }
    }

    private var columns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: 86),
                spacing: QuillCodeMetrics.minimumTargetClearance,
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
                    .font(.system(size: 12, weight: .semibold))
                filterCountBadge(filter)
            }
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(minWidth: 62, minHeight: 26)
            .foregroundStyle(filter.isActive ? QuillCodePalette.background : QuillCodePalette.muted)
            .background(filter.isActive ? QuillCodePalette.blue : QuillCodePalette.panel.opacity(0.55))
            .clipShape(Capsule())
            .quillCodeCapsuleButtonTarget(minWidth: 66)
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .accessibilityLabel(filter.accessibilityLabel)
        .accessibilityAddTraits(filter.isActive ? .isSelected : [])
        .accessibilityIdentifier("quillcode-sidebar-filter-\(filter.kind.rawValue)")
    }

    private func filterCountBadge(_ filter: SidebarSavedFilterSurface) -> some View {
        Text("\(filter.count)")
            .font(.system(size: 10, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(filter.isActive ? QuillCodePalette.background : QuillCodePalette.muted)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background((filter.isActive ? Color.white : QuillCodePalette.panel).opacity(0.28))
            .clipShape(Capsule())
    }
}
