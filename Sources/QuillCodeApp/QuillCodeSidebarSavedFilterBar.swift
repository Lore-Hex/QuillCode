import SwiftUI

struct QuillCodeSidebarSavedFilterBar: View {
    var filters: [SidebarSavedFilterSurface]
    var savedSearches: [SidebarSavedSearchSurface]
    var createCommand: WorkspaceCommandSurface?
    var selectionCommand: WorkspaceCommandSurface?
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        Menu {
            Section("Chats") {
                ForEach(filters) { filter in
                    savedFilterButton(filter)
                }
            }
            QuillCodeSidebarSavedSearchMenuContent(
                savedSearches: savedSearches,
                createCommand: createCommand,
                onCommand: onCommand
            )
            if let selectionCommand {
                Section("Actions") {
                    Button {
                        onCommand(selectionCommand)
                    } label: {
                        Label("Select chats", systemImage: "checkmark.circle")
                    }
                    .quillCodePlatformMenuItemTarget(reason: menuGeometryReason)
                    .disabled(!selectionCommand.isEnabled)
                    .accessibilityIdentifier("quillcode-sidebar-select-chats")
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isRefined ? QuillCodePalette.blue : QuillCodePalette.muted)
                .quillCodeSidebarIconButtonTarget()
        }
        .buttonStyle(QuillCodePressableButtonStyle(enforcesMinimumHitTarget: false))
        .help(accessibilityLabel)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("quillcode-sidebar-filter-menu")
    }

    private func savedFilterButton(_ filter: SidebarSavedFilterSurface) -> some View {
        Button {
            onCommand(QuillCodeSidebarCommandAdapter.workspaceCommand(for: filter))
        } label: {
            Label(
                "\(filter.title) (\(filter.count))",
                systemImage: filter.isActive ? "checkmark" : "circle"
            )
        }
        .quillCodePlatformMenuItemTarget(reason: menuGeometryReason)
        .accessibilityLabel(filter.accessibilityLabel)
        .accessibilityIdentifier("quillcode-sidebar-filter-\(filter.kind.rawValue)")
    }

    private var activeScopeTitle: String {
        savedSearches.first(where: \.isActive)?.title
            ?? filters.first(where: \.isActive)?.title
            ?? "Custom"
    }

    private var activeScopeCount: Int {
        savedSearches.first(where: \.isActive)?.count
            ?? filters.first(where: \.isActive)?.count
            ?? 0
    }

    private var isRefined: Bool {
        savedSearches.contains(where: \.isActive)
            || filters.contains { $0.kind != .all && $0.isActive }
    }

    private var accessibilityLabel: String {
        "Filter chats, \(activeScopeTitle), \(activeScopeCount)"
    }

    private var menuGeometryReason: String {
        "AppKit owns chat-filter menu row geometry; the visible filter trigger carries the custom hit-target contract."
    }
}
