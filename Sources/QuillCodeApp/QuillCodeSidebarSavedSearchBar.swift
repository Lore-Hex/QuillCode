import SwiftUI

struct QuillCodeSidebarSavedSearchMenuContent: View {
    var savedSearches: [SidebarSavedSearchSurface]
    var createCommand: WorkspaceCommandSurface?
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        if !savedSearches.isEmpty || createCommand != nil {
            Section("Saved searches") {
                ForEach(savedSearches) { savedSearch in
                    savedSearchButton(savedSearch)
                }
                if let createCommand {
                    Button {
                        onCommand(createCommand)
                    } label: {
                        Label("Save current search…", systemImage: "plus")
                    }
                    .quillCodePlatformMenuItemTarget(reason: menuGeometryReason)
                    .accessibilityIdentifier("quillcode-sidebar-saved-search-create")
                }
            }
            if !savedSearches.isEmpty {
                Section("Manage saved searches") {
                    ForEach(savedSearches) { savedSearch in
                        savedSearchManagementMenu(savedSearch)
                    }
                }
            }
        }
    }

    private func savedSearchButton(_ savedSearch: SidebarSavedSearchSurface) -> some View {
        Button {
            onCommand(QuillCodeSidebarCommandAdapter.workspaceCommand(for: savedSearch))
        } label: {
            Label(
                "\(savedSearch.title) (\(savedSearch.count))",
                systemImage: savedSearch.isActive ? "checkmark" : "circle"
            )
        }
        .quillCodePlatformMenuItemTarget(reason: menuGeometryReason)
        .accessibilityLabel(savedSearch.accessibilityLabel)
        .help(savedSearch.query)
        .accessibilityIdentifier("quillcode-sidebar-saved-search")
    }

    private func savedSearchManagementMenu(_ savedSearch: SidebarSavedSearchSurface) -> some View {
        Menu(savedSearch.title) {
            savedSearchMoveButton(savedSearch, direction: .up, systemImage: "chevron.up")
            savedSearchMoveButton(savedSearch, direction: .down, systemImage: "chevron.down")
            Divider()
            savedSearchDeleteButton(savedSearch)
        }
        .quillCodePlatformMenuItemTarget(reason: menuGeometryReason)
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
            Label("Move \(direction.rawValue)", systemImage: systemImage)
        }
        .quillCodePlatformMenuItemTarget(reason: menuGeometryReason)
        .disabled(!command.isEnabled)
        .accessibilityLabel("Move saved search \(savedSearch.title) \(direction.rawValue)")
        .accessibilityIdentifier("quillcode-sidebar-saved-search-move-\(direction.rawValue)")
    }

    private func savedSearchDeleteButton(_ savedSearch: SidebarSavedSearchSurface) -> some View {
        Button {
            onCommand(QuillCodeSidebarCommandAdapter.deleteWorkspaceCommand(for: savedSearch))
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .quillCodePlatformMenuItemTarget(reason: menuGeometryReason)
        .accessibilityLabel("Delete saved search \(savedSearch.title)")
        .accessibilityIdentifier("quillcode-sidebar-saved-search-delete")
    }

    private var menuGeometryReason: String {
        "AppKit owns saved-search menu row geometry; the visible filter trigger carries the custom hit-target contract."
    }
}
