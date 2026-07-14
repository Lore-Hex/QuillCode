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
    @Binding var newWorktreeTaskDraft: QuillCodeNewWorktreeTaskDraft
    @Binding var createWorktreeDraft: QuillCodeWorktreeCreateDraft
    @Binding var createWorktreeBranchDraft: QuillCodeWorktreeCreateBranchDraft
    @Binding var finishWorktreeDraft: QuillCodeWorktreeFinishDraft
    @Binding var openWorktreeDraft: QuillCodeWorktreeOpenDraft
    @Binding var removeWorktreeDraft: QuillCodeWorktreeRemoveDraft
    @Binding var pruneWorktreeDraft: QuillCodeWorktreePruneDraft
    @Binding var renameThreadDraft: QuillCodeThreadRenameDraft?
    @Binding var renameProjectDraft: QuillCodeProjectRenameDraft?
    @Binding var sidebarSavedSearchDraft: QuillCodeSidebarSavedSearchDraft?
    @Binding var subagentTranscript: WorkspaceSubagentTranscriptSurface?
    @ObservedObject var agentImportDialog: QuillCodeAgentImportDialogCoordinator
    var agentImportActions: QuillCodeAgentImportActions?
    var onSelectThread: (UUID) -> Void
    var onSaveSettings: (WorkspaceSettingsUpdate) -> Void
    var onSaveKeyboardShortcuts: (KeyboardShortcutPreferences) -> Void
    var onStartTrustedRouterSignIn: () -> Void
    var onCommand: (WorkspaceCommandSurface) -> Void
    var onCreateWorktreeThread: (WorkspaceNewWorktreeThreadRequest) -> Void
    var onCreateWorktree: (WorkspaceWorktreeCreateRequest) -> Void
    var onCreateWorktreeBranch: (WorkspaceWorktreeCreateBranchRequest) -> Void
    var onFinishWorktree: () -> Void
    var onRetryWorktreeChoices: (QuillCodeWorktreeSheet) -> Void
    var onOpenWorktree: (WorkspaceWorktreeOpenRequest) -> Void
    var onRemoveWorktree: (WorkspaceWorktreeRemoveRequest) -> Void
    var onRetryWorktreePrunePreview: () -> Void
    var onPruneWorktrees: (WorkspaceWorktreePruneRequest) -> Void
    var onRenameThread: (UUID, String) -> Void
    var onRenameProject: (UUID, String) -> Void
    var onSaveSidebarSavedSearch: (String, String) -> Void
    var onToolCardAction: (ToolCardActionSurface) -> Void
    var onCopyTranscriptItem: (String, String) -> Void

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
            settingsModal
            agentImportModal
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
                        preferences: surface.settings.keyboardShortcuts,
                        onSave: onSaveKeyboardShortcuts,
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
            if let transcript = subagentTranscript {
                dismissibleModal(accessibilityLabel: "Dismiss delegated transcript", onDismiss: dismissSubagentTranscript) {
                    QuillCodeSubagentTranscriptSheet(
                        surface: transcript,
                        onClose: dismissSubagentTranscript,
                        onToolCardAction: runSubagentToolCardAction,
                        onCopyTranscriptItem: onCopyTranscriptItem
                    )
                }
                .zIndex(90)
            }
        }
        .animation(.easeOut(duration: 0.16), value: isSettingsPresented)
        .animation(.easeOut(duration: 0.16), value: agentImportDialog.phase)
        .animation(.easeOut(duration: 0.16), value: isSearchPresented)
        .animation(.easeOut(duration: 0.16), value: isCommandPalettePresented)
        .animation(.easeOut(duration: 0.16), value: subagentTranscript?.id)
    }

    @ViewBuilder
    private var settingsModal: some View {
        if isSettingsPresented {
            dismissibleModal(accessibilityLabel: "Dismiss settings", onDismiss: dismissSettings) {
                QuillCodeSettingsView(
                    settings: surface.settings,
                    draft: $settingsDraft,
                    onCancel: dismissSettings,
                    onSave: saveSettings,
                    onStartTrustedRouterSignIn: onStartTrustedRouterSignIn,
                    onOpenAgentImport: agentImportActions.map { _ in openAgentImport },
                    onCommand: onCommand
                )
            }
            .zIndex(10)
        }
    }

    @ViewBuilder
    private var agentImportModal: some View {
        if agentImportDialog.isPresented {
            dismissibleModal(accessibilityLabel: "Dismiss import", onDismiss: dismissAgentImport) {
                QuillCodeAgentImportView(
                    coordinator: agentImportDialog,
                    onClose: dismissAgentImport,
                    onImport: performAgentImport
                )
            }
            .zIndex(15)
        }
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
        case .newTask:
            QuillCodeNewWorktreeTaskView(
                draft: $newWorktreeTaskDraft,
                onCancel: dismissWorktreeSheet,
                onCreate: createWorktreeThread
            )
        case .create:
            QuillCodeWorktreeCreateView(
                draft: $createWorktreeDraft,
                onCancel: dismissWorktreeSheet,
                onCreate: createWorktree
            )
        case .createBranch:
            QuillCodeWorktreeCreateBranchView(
                draft: $createWorktreeBranchDraft,
                onCancel: dismissWorktreeSheet,
                onCreate: createWorktreeBranch
            )
        case .finish:
            QuillCodeWorktreeFinishView(
                draft: finishWorktreeDraft,
                onCancel: dismissWorktreeSheet,
                onFinish: finishWorktree
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

    private func openAgentImport() {
        guard let agentImportActions else { return }
        isSettingsPresented = false
        agentImportDialog.begin(using: agentImportActions)
    }

    private func dismissAgentImport() {
        agentImportDialog.dismiss()
    }

    private func performAgentImport() {
        guard let agentImportActions else { return }
        agentImportDialog.perform(using: agentImportActions)
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

    private func createWorktreeThread() {
        onCreateWorktreeThread(newWorktreeTaskDraft.request)
        worktreeSheet = nil
    }

    private func createWorktreeBranch() {
        onCreateWorktreeBranch(createWorktreeBranchDraft.request)
        worktreeSheet = nil
    }

    private func finishWorktree() {
        onFinishWorktree()
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

    private func dismissSubagentTranscript() {
        subagentTranscript = nil
    }

    private func runSubagentToolCardAction(_ action: ToolCardActionSurface) {
        subagentTranscript = nil
        onToolCardAction(action)
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
        newWorktreeTaskDraft: Binding<QuillCodeNewWorktreeTaskDraft>,
        createWorktreeDraft: Binding<QuillCodeWorktreeCreateDraft>,
        createWorktreeBranchDraft: Binding<QuillCodeWorktreeCreateBranchDraft>,
        finishWorktreeDraft: Binding<QuillCodeWorktreeFinishDraft>,
        openWorktreeDraft: Binding<QuillCodeWorktreeOpenDraft>,
        removeWorktreeDraft: Binding<QuillCodeWorktreeRemoveDraft>,
        pruneWorktreeDraft: Binding<QuillCodeWorktreePruneDraft>,
        renameThreadDraft: Binding<QuillCodeThreadRenameDraft?>,
        renameProjectDraft: Binding<QuillCodeProjectRenameDraft?>,
        sidebarSavedSearchDraft: Binding<QuillCodeSidebarSavedSearchDraft?>,
        subagentTranscript: Binding<WorkspaceSubagentTranscriptSurface?>,
        agentImportDialog: QuillCodeAgentImportDialogCoordinator,
        agentImportActions: QuillCodeAgentImportActions?,
        onSelectThread: @escaping (UUID) -> Void,
        onSaveSettings: @escaping (WorkspaceSettingsUpdate) -> Void,
        onSaveKeyboardShortcuts: @escaping (KeyboardShortcutPreferences) -> Void,
        onStartTrustedRouterSignIn: @escaping () -> Void,
        onCommand: @escaping (WorkspaceCommandSurface) -> Void,
        onCreateWorktreeThread: @escaping (WorkspaceNewWorktreeThreadRequest) -> Void,
        onCreateWorktree: @escaping (WorkspaceWorktreeCreateRequest) -> Void,
        onCreateWorktreeBranch: @escaping (WorkspaceWorktreeCreateBranchRequest) -> Void,
        onFinishWorktree: @escaping () -> Void,
        onRetryWorktreeChoices: @escaping (QuillCodeWorktreeSheet) -> Void,
        onOpenWorktree: @escaping (WorkspaceWorktreeOpenRequest) -> Void,
        onRemoveWorktree: @escaping (WorkspaceWorktreeRemoveRequest) -> Void,
        onRetryWorktreePrunePreview: @escaping () -> Void,
        onPruneWorktrees: @escaping (WorkspaceWorktreePruneRequest) -> Void,
        onRenameThread: @escaping (UUID, String) -> Void,
        onRenameProject: @escaping (UUID, String) -> Void,
        onSaveSidebarSavedSearch: @escaping (String, String) -> Void,
        onToolCardAction: @escaping (ToolCardActionSurface) -> Void,
        onCopyTranscriptItem: @escaping (String, String) -> Void
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
            newWorktreeTaskDraft: newWorktreeTaskDraft,
            createWorktreeDraft: createWorktreeDraft,
            createWorktreeBranchDraft: createWorktreeBranchDraft,
            finishWorktreeDraft: finishWorktreeDraft,
            openWorktreeDraft: openWorktreeDraft,
            removeWorktreeDraft: removeWorktreeDraft,
            pruneWorktreeDraft: pruneWorktreeDraft,
            renameThreadDraft: renameThreadDraft,
            renameProjectDraft: renameProjectDraft,
            sidebarSavedSearchDraft: sidebarSavedSearchDraft,
            subagentTranscript: subagentTranscript,
            agentImportDialog: agentImportDialog,
            agentImportActions: agentImportActions,
            onSelectThread: onSelectThread,
            onSaveSettings: onSaveSettings,
            onSaveKeyboardShortcuts: onSaveKeyboardShortcuts,
            onStartTrustedRouterSignIn: onStartTrustedRouterSignIn,
            onCommand: onCommand,
            onCreateWorktreeThread: onCreateWorktreeThread,
            onCreateWorktree: onCreateWorktree,
            onCreateWorktreeBranch: onCreateWorktreeBranch,
            onFinishWorktree: onFinishWorktree,
            onRetryWorktreeChoices: onRetryWorktreeChoices,
            onOpenWorktree: onOpenWorktree,
            onRemoveWorktree: onRemoveWorktree,
            onRetryWorktreePrunePreview: onRetryWorktreePrunePreview,
            onPruneWorktrees: onPruneWorktrees,
            onRenameThread: onRenameThread,
            onRenameProject: onRenameProject,
            onSaveSidebarSavedSearch: onSaveSidebarSavedSearch,
            onToolCardAction: onToolCardAction,
            onCopyTranscriptItem: onCopyTranscriptItem
        ))
    }
}
