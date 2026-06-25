import SwiftUI
import QuillCodeCore

struct QuillCodeWorkspaceSheetsModifier: ViewModifier {
    var surface: WorkspaceSurface
    @Binding var isSearchPresented: Bool
    @Binding var searchQuery: String
    @Binding var isCommandPalettePresented: Bool
    @Binding var commandQuery: String
    @Binding var isSettingsPresented: Bool
    @Binding var settingsDraft: QuillCodeSettingsDraft
    @Binding var isKeyboardShortcutsPresented: Bool
    @Binding var worktreeSheet: QuillCodeWorktreeSheet?
    @Binding var createWorktreeDraft: QuillCodeWorktreeCreateDraft
    @Binding var openWorktreeDraft: QuillCodeWorktreeOpenDraft
    @Binding var removeWorktreeDraft: QuillCodeWorktreeRemoveDraft
    @Binding var renameThreadDraft: QuillCodeThreadRenameDraft?
    @Binding var renameProjectDraft: QuillCodeProjectRenameDraft?
    var onSelectThread: (UUID) -> Void
    var onSaveSettings: (WorkspaceSettingsUpdate) -> Void
    var onStartTrustedRouterSignIn: () -> Void
    var onCommand: (WorkspaceCommandSurface) -> Void
    var onCreateWorktree: (WorkspaceWorktreeCreateRequest) -> Void
    var onOpenWorktree: (WorkspaceWorktreeOpenRequest) -> Void
    var onRemoveWorktree: (WorkspaceWorktreeRemoveRequest) -> Void
    var onRenameThread: (UUID, String) -> Void
    var onRenameProject: (UUID, String) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isSettingsPresented) {
                QuillCodeSettingsView(
                    settings: surface.settings,
                    draft: $settingsDraft,
                    onCancel: dismissSettings,
                    onSave: saveSettings,
                    onStartTrustedRouterSignIn: onStartTrustedRouterSignIn,
                    onCommand: onCommand
                )
            }
            .onChange(of: isSettingsPresented) { _, isPresented in
                if isPresented {
                    settingsDraft = QuillCodeSettingsDraft(settings: surface.settings)
                }
            }
            .sheet(isPresented: $isSearchPresented) {
                QuillCodeSearchView(
                    sidebar: surface.sidebar,
                    query: $searchQuery,
                    onSelectThread: selectSearchThread,
                    onClose: dismissSearch
                )
            }
            .sheet(isPresented: $isKeyboardShortcutsPresented) {
                QuillCodeKeyboardShortcutsView(
                    commands: surface.commands,
                    onClose: dismissKeyboardShortcuts
                )
            }
            .sheet(isPresented: $isCommandPalettePresented) {
                QuillCodeCommandPaletteView(
                    commands: surface.commands.filter { $0.id != "command-palette" },
                    query: $commandQuery,
                    onSelectCommand: selectCommandPaletteCommand,
                    onClose: dismissCommandPalette
                )
            }
            .sheet(item: $worktreeSheet) { sheet in
                switch sheet {
                case .create:
                    QuillCodeWorktreeCreateView(
                        draft: $createWorktreeDraft,
                        onCancel: dismissWorktreeSheet,
                        onCreate: createWorktree
                    )
                case .open:
                    QuillCodeWorktreeOpenView(
                        draft: $openWorktreeDraft,
                        onCancel: dismissWorktreeSheet,
                        onOpen: openWorktree
                    )
                case .remove:
                    QuillCodeWorktreeRemoveView(
                        draft: $removeWorktreeDraft,
                        onCancel: dismissWorktreeSheet,
                        onRemove: removeWorktree
                    )
                }
            }
            .sheet(item: $renameThreadDraft) { draft in
                QuillCodeThreadRenameView(
                    draft: draft,
                    onCancel: dismissThreadRename,
                    onSave: saveThreadRename
                )
            }
            .sheet(item: $renameProjectDraft) { draft in
                QuillCodeProjectRenameView(
                    draft: draft,
                    onCancel: dismissProjectRename,
                    onSave: saveProjectRename
                )
            }
    }

    private func dismissSettings() {
        isSettingsPresented = false
    }

    private func saveSettings() {
        onSaveSettings(settingsDraft.update)
        isSettingsPresented = false
    }

    private func dismissSearch() {
        isSearchPresented = false
    }

    private func selectSearchThread(_ threadID: UUID) {
        onSelectThread(threadID)
        isSearchPresented = false
    }

    private func dismissKeyboardShortcuts() {
        isKeyboardShortcutsPresented = false
    }

    private func dismissCommandPalette() {
        isCommandPalettePresented = false
    }

    private func selectCommandPaletteCommand(_ command: WorkspaceCommandSurface) {
        isCommandPalettePresented = false
        onCommand(command)
    }

    private func dismissWorktreeSheet() {
        worktreeSheet = nil
    }

    private func createWorktree() {
        onCreateWorktree(createWorktreeDraft.request)
        worktreeSheet = nil
    }

    private func openWorktree() {
        onOpenWorktree(openWorktreeDraft.request)
        worktreeSheet = nil
    }

    private func removeWorktree() {
        onRemoveWorktree(removeWorktreeDraft.request)
        worktreeSheet = nil
    }

    private func dismissThreadRename() {
        renameThreadDraft = nil
    }

    private func saveThreadRename(threadID: UUID, title: String) {
        onRenameThread(threadID, title)
        renameThreadDraft = nil
    }

    private func dismissProjectRename() {
        renameProjectDraft = nil
    }

    private func saveProjectRename(projectID: UUID, name: String) {
        onRenameProject(projectID, name)
        renameProjectDraft = nil
    }
}

extension View {
    func quillCodeWorkspaceSheets(
        surface: WorkspaceSurface,
        isSearchPresented: Binding<Bool>,
        searchQuery: Binding<String>,
        isCommandPalettePresented: Binding<Bool>,
        commandQuery: Binding<String>,
        isSettingsPresented: Binding<Bool>,
        settingsDraft: Binding<QuillCodeSettingsDraft>,
        isKeyboardShortcutsPresented: Binding<Bool>,
        worktreeSheet: Binding<QuillCodeWorktreeSheet?>,
        createWorktreeDraft: Binding<QuillCodeWorktreeCreateDraft>,
        openWorktreeDraft: Binding<QuillCodeWorktreeOpenDraft>,
        removeWorktreeDraft: Binding<QuillCodeWorktreeRemoveDraft>,
        renameThreadDraft: Binding<QuillCodeThreadRenameDraft?>,
        renameProjectDraft: Binding<QuillCodeProjectRenameDraft?>,
        onSelectThread: @escaping (UUID) -> Void,
        onSaveSettings: @escaping (WorkspaceSettingsUpdate) -> Void,
        onStartTrustedRouterSignIn: @escaping () -> Void,
        onCommand: @escaping (WorkspaceCommandSurface) -> Void,
        onCreateWorktree: @escaping (WorkspaceWorktreeCreateRequest) -> Void,
        onOpenWorktree: @escaping (WorkspaceWorktreeOpenRequest) -> Void,
        onRemoveWorktree: @escaping (WorkspaceWorktreeRemoveRequest) -> Void,
        onRenameThread: @escaping (UUID, String) -> Void,
        onRenameProject: @escaping (UUID, String) -> Void
    ) -> some View {
        modifier(QuillCodeWorkspaceSheetsModifier(
            surface: surface,
            isSearchPresented: isSearchPresented,
            searchQuery: searchQuery,
            isCommandPalettePresented: isCommandPalettePresented,
            commandQuery: commandQuery,
            isSettingsPresented: isSettingsPresented,
            settingsDraft: settingsDraft,
            isKeyboardShortcutsPresented: isKeyboardShortcutsPresented,
            worktreeSheet: worktreeSheet,
            createWorktreeDraft: createWorktreeDraft,
            openWorktreeDraft: openWorktreeDraft,
            removeWorktreeDraft: removeWorktreeDraft,
            renameThreadDraft: renameThreadDraft,
            renameProjectDraft: renameProjectDraft,
            onSelectThread: onSelectThread,
            onSaveSettings: onSaveSettings,
            onStartTrustedRouterSignIn: onStartTrustedRouterSignIn,
            onCommand: onCommand,
            onCreateWorktree: onCreateWorktree,
            onOpenWorktree: onOpenWorktree,
            onRemoveWorktree: onRemoveWorktree,
            onRenameThread: onRenameThread,
            onRenameProject: onRenameProject
        ))
    }
}
