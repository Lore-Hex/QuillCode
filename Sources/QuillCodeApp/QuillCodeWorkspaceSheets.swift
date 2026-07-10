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
    @Binding var pruneWorktreeDraft: QuillCodeWorktreePruneDraft
    @Binding var renameThreadDraft: QuillCodeThreadRenameDraft?
    @Binding var renameProjectDraft: QuillCodeProjectRenameDraft?
    @Binding var sidebarSavedSearchDraft: QuillCodeSidebarSavedSearchDraft?
    var onSelectThread: (UUID) -> Void
    var onSaveSettings: (WorkspaceSettingsUpdate) -> Void
    var onStartTrustedRouterSignIn: () -> Void
    var onCommand: (WorkspaceCommandSurface) -> Void
    var onCreateWorktree: (WorkspaceWorktreeCreateRequest) -> Void
    var onRetryWorktreeChoices: (QuillCodeWorktreeSheet) -> Void
    var onOpenWorktree: (WorkspaceWorktreeOpenRequest) -> Void
    var onRemoveWorktree: (WorkspaceWorktreeRemoveRequest) -> Void
    var onRetryWorktreePrunePreview: () -> Void
    var onPruneWorktrees: (WorkspaceWorktreePruneRequest) -> Void
    var onRenameThread: (UUID, String) -> Void
    var onRenameProject: (UUID, String) -> Void
    var onSaveSidebarSavedSearch: (String, String) -> Void

    func body(content: Content) -> some View {
        content
            .overlay { modalLayer }
            .onChange(of: isSettingsPresented) { _, isPresented in
                if isPresented {
                    settingsDraft = QuillCodeSettingsDraft(settings: surface.settings)
                }
            }
    }

    @ViewBuilder
    private var modalLayer: some View {
        ZStack {
            if isSettingsPresented {
                dismissibleModal(accessibilityLabel: "Dismiss settings", onDismiss: dismissSettings) {
                    QuillCodeSettingsView(
                        settings: surface.settings,
                        draft: $settingsDraft,
                        onCancel: dismissSettings,
                        onSave: saveSettings,
                        onStartTrustedRouterSignIn: onStartTrustedRouterSignIn,
                        onCommand: onCommand
                    )
                }
                .zIndex(10)
            }
            if isSearchPresented {
                dismissibleModal(accessibilityLabel: "Dismiss search", onDismiss: dismissSearch) {
                    QuillCodeSearchView(
                        sidebar: surface.sidebar,
                        query: $searchQuery,
                        onSelectThread: selectSearchThread,
                        onClose: dismissSearch
                    )
                }
                .zIndex(20)
            }
            if isKeyboardShortcutsPresented {
                dismissibleModal(accessibilityLabel: "Dismiss keyboard shortcuts", onDismiss: dismissKeyboardShortcuts) {
                    QuillCodeKeyboardShortcutsView(
                        commands: surface.commands,
                        onClose: dismissKeyboardShortcuts
                    )
                }
                .zIndex(30)
            }
            if isCommandPalettePresented {
                dismissibleModal(accessibilityLabel: "Dismiss command palette", onDismiss: dismissCommandPalette) {
                    QuillCodeCommandPaletteView(
                        commands: surface.commands.filter { $0.id != "command-palette" },
                        query: $commandQuery,
                        onSelectCommand: selectCommandPaletteCommand,
                        onClose: dismissCommandPalette
                    )
                }
                .zIndex(40)
            }
            if let sheet = worktreeSheet {
                dismissibleModal(accessibilityLabel: "Dismiss worktree dialog", onDismiss: dismissWorktreeSheet) {
                    worktreeDialog(for: sheet)
                }
                .zIndex(50)
            }
            if let draft = renameThreadDraft {
                dismissibleModal(accessibilityLabel: "Dismiss rename thread", onDismiss: dismissThreadRename) {
                    QuillCodeThreadRenameView(
                        draft: draft,
                        onCancel: dismissThreadRename,
                        onSave: saveThreadRename
                    )
                }
                .zIndex(60)
            }
            if let draft = renameProjectDraft {
                dismissibleModal(accessibilityLabel: "Dismiss rename project", onDismiss: dismissProjectRename) {
                    QuillCodeProjectRenameView(
                        draft: draft,
                        onCancel: dismissProjectRename,
                        onSave: saveProjectRename
                    )
                }
                .zIndex(70)
            }
            if let draft = sidebarSavedSearchDraft {
                dismissibleModal(accessibilityLabel: "Dismiss saved search", onDismiss: dismissSidebarSavedSearch) {
                    QuillCodeSidebarSavedSearchView(
                        draft: draft,
                        onCancel: dismissSidebarSavedSearch,
                        onSave: saveSidebarSavedSearch
                    )
                }
                .zIndex(80)
            }
        }
        .animation(.easeOut(duration: 0.16), value: isSettingsPresented)
        .animation(.easeOut(duration: 0.16), value: isSearchPresented)
        .animation(.easeOut(duration: 0.16), value: isCommandPalettePresented)
    }

    private func dismissibleModal<Dialog: View>(
        accessibilityLabel: String,
        onDismiss: @escaping () -> Void,
        @ViewBuilder dialog: () -> Dialog
    ) -> some View {
        ZStack {
            Color.black.opacity(0.52)
                .ignoresSafeArea()
                .quillCodeOwnedGestureTarget()
                .accessibilityLabel(accessibilityLabel)
                .onTapGesture(perform: onDismiss)

            dialog()
                .clipShape(RoundedRectangle(cornerRadius: QuillCodeMetrics.dialogRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: QuillCodeMetrics.dialogRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.38), radius: 34, x: 0, y: 18)
                .accessibilityAddTraits(.isModal)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
        .onExitCommand(perform: onDismiss)
    }

    @ViewBuilder
    private func worktreeDialog(for sheet: QuillCodeWorktreeSheet) -> some View {
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
                onOpen: openWorktree,
                onRetryChoices: retryOpenWorktreeChoices
            )
        case .remove:
            QuillCodeWorktreeRemoveView(
                draft: $removeWorktreeDraft,
                onCancel: dismissWorktreeSheet,
                onRemove: removeWorktree,
                onRetryChoices: retryRemoveWorktreeChoices
            )
        case .prune:
            QuillCodeWorktreePruneView(
                draft: $pruneWorktreeDraft,
                onCancel: dismissWorktreeSheet,
                onPrune: pruneWorktrees,
                onRetryPreview: onRetryWorktreePrunePreview
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

    private func retryOpenWorktreeChoices() {
        onRetryWorktreeChoices(.open)
    }

    private func removeWorktree() {
        onRemoveWorktree(removeWorktreeDraft.request)
        worktreeSheet = nil
    }

    private func retryRemoveWorktreeChoices() {
        onRetryWorktreeChoices(.remove)
    }

    private func pruneWorktrees() {
        onPruneWorktrees(pruneWorktreeDraft.confirmRequest)
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

    private func dismissSidebarSavedSearch() {
        sidebarSavedSearchDraft = nil
    }

    private func saveSidebarSavedSearch(title: String, query: String) {
        onSaveSidebarSavedSearch(title, query)
        sidebarSavedSearchDraft = nil
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
        pruneWorktreeDraft: Binding<QuillCodeWorktreePruneDraft>,
        renameThreadDraft: Binding<QuillCodeThreadRenameDraft?>,
        renameProjectDraft: Binding<QuillCodeProjectRenameDraft?>,
        sidebarSavedSearchDraft: Binding<QuillCodeSidebarSavedSearchDraft?>,
        onSelectThread: @escaping (UUID) -> Void,
        onSaveSettings: @escaping (WorkspaceSettingsUpdate) -> Void,
        onStartTrustedRouterSignIn: @escaping () -> Void,
        onCommand: @escaping (WorkspaceCommandSurface) -> Void,
        onCreateWorktree: @escaping (WorkspaceWorktreeCreateRequest) -> Void,
        onRetryWorktreeChoices: @escaping (QuillCodeWorktreeSheet) -> Void,
        onOpenWorktree: @escaping (WorkspaceWorktreeOpenRequest) -> Void,
        onRemoveWorktree: @escaping (WorkspaceWorktreeRemoveRequest) -> Void,
        onRetryWorktreePrunePreview: @escaping () -> Void,
        onPruneWorktrees: @escaping (WorkspaceWorktreePruneRequest) -> Void,
        onRenameThread: @escaping (UUID, String) -> Void,
        onRenameProject: @escaping (UUID, String) -> Void,
        onSaveSidebarSavedSearch: @escaping (String, String) -> Void
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
            pruneWorktreeDraft: pruneWorktreeDraft,
            renameThreadDraft: renameThreadDraft,
            renameProjectDraft: renameProjectDraft,
            sidebarSavedSearchDraft: sidebarSavedSearchDraft,
            onSelectThread: onSelectThread,
            onSaveSettings: onSaveSettings,
            onStartTrustedRouterSignIn: onStartTrustedRouterSignIn,
            onCommand: onCommand,
            onCreateWorktree: onCreateWorktree,
            onRetryWorktreeChoices: onRetryWorktreeChoices,
            onOpenWorktree: onOpenWorktree,
            onRemoveWorktree: onRemoveWorktree,
            onRetryWorktreePrunePreview: onRetryWorktreePrunePreview,
            onPruneWorktrees: onPruneWorktrees,
            onRenameThread: onRenameThread,
            onRenameProject: onRenameProject,
            onSaveSidebarSavedSearch: onSaveSidebarSavedSearch
        ))
    }
}
