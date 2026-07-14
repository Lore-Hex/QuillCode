import XCTest

final class ParityWorkspaceSettingsSheetGateTests: QuillCodeParityTestCase {
    func testWorkspaceSwiftUIViewDelegatesSheetPresentation() throws {
        let shellText = try Self.appSourceText(named: "WorkspaceSwiftUIView.swift")
        let sheetsText = try Self.appSourceText(named: "QuillCodeWorkspaceSheets.swift")
        let renameDialogsText = try Self.appSourceText(named: "QuillCodeWorkspaceDialogs.swift")
        let commandPaletteText = try Self.appSourceText(named: "QuillCodeCommandPaletteDialog.swift")
        let searchShortcutText = try Self.appSourceText(named: "QuillCodeSearchAndShortcutDialogs.swift")
        let worktreeDialogsText = try Self.appSourceText(named: "QuillCodeWorktreeDialogs.swift")
        let worktreeDraftsText = try Self.appSourceText(named: "QuillCodeWorktreeDrafts.swift")
        let worktreeChromeText = try Self.appSourceText(named: "QuillCodeWorktreeDialogChrome.swift")
        let worktreeCoordinatorText = try Self.appSourceText(named: "QuillCodeWorktreeDialogCoordinator.swift")
        let worktreeTasksText = try Self.appSourceText(named: "QuillCodeWorktreeDialogTasks.swift")
        let dialogChromeText = try Self.appSourceText(named: "QuillCodeDialogChrome.swift")

        for expected in [
            "struct QuillCodeWorkspaceSheetsModifier",
            "func quillCodeWorkspaceSheets(",
            "QuillCodeSettingsView(",
            "QuillCodeSearchView(",
            "QuillCodeKeyboardShortcutsView(",
            "QuillCodeCommandPaletteView(",
            "QuillCodeWorktreeCreateView(",
            "QuillCodeWorktreeRemoveView(",
            "QuillCodeThreadRenameView(",
            "QuillCodeProjectRenameView("
        ] {
            Self.assertSource(sheetsText, contains: expected)
        }
        for expected in [
            "struct QuillCodeWorktreeCreateDraft",
            "struct QuillCodeWorktreeOpenDraft",
            "struct QuillCodeWorktreeRemoveDraft",
            "struct QuillCodeWorktreePruneDraft"
        ] {
            Self.assertSource(worktreeDraftsText, contains: expected)
        }
        for expected in [
            "struct QuillCodeWorktreeChoiceSection",
            "struct QuillCodeWorktreeDialogFrame",
            "QuillCodePressableButtonStyle",
            "quillCodeFullRowButtonTarget"
        ] {
            Self.assertSource(worktreeChromeText, contains: expected)
        }
        Self.assertSource(commandPaletteText, contains: "struct QuillCodeCommandPaletteView")
        Self.assertSource(commandPaletteText, contains: "QuillCodeCommandIconCatalog.systemImage")
        Self.assertSource(commandPaletteText, excludes: "enum QuillCodeCommandIcon")
        Self.assertSource(searchShortcutText, contains: "struct QuillCodeSearchView")
        Self.assertSource(searchShortcutText, contains: "struct QuillCodeKeyboardShortcutsView")
        Self.assertSource(searchShortcutText, contains: "TextField(searchPlaceholder")
        Self.assertSource(searchShortcutText, contains: "accessibilityIdentifier(\"quillcode-shortcuts-search-input\")")
        Self.assertSource(searchShortcutText, contains: "editor.groups(commands: commands, query: query, mode: searchMode)")
        Self.assertSource(worktreeDialogsText, contains: "struct QuillCodeWorktreeCreateView")
        Self.assertSource(worktreeDialogsText, contains: "struct QuillCodeWorktreeRemoveView")
        Self.assertSource(worktreeCoordinatorText, contains: "final class QuillCodeWorktreeDialogCoordinator")
        Self.assertSource(worktreeCoordinatorText, contains: "func presentOpen(")
        Self.assertSource(worktreeCoordinatorText, contains: "guard self.sheet == sheet else { return }")
        Self.assertSource(worktreeCoordinatorText, contains: "private let tasks = QuillCodeWorktreeDialogTasks()")
        Self.assertSource(worktreeTasksText, contains: "final class QuillCodeWorktreeDialogTasks")
        Self.assertSource(worktreeTasksText, contains: "private enum Slot")
        Self.assertSource(worktreeTasksText, contains: "private var runningTasks: [Slot: Task<Void, Never>]")
        Self.assertSource(sheetsText, contains: ".onTapGesture(perform: onDismiss)")
        Self.assertSource(sheetsText, contains: ".onExitCommand(perform: onDismiss)")
        Self.assertSource(worktreeDialogsText, excludes: "struct QuillCodeWorktreeCreateDraft")
        Self.assertSource(worktreeDialogsText, excludes: "struct QuillCodeWorktreeChoiceSection")
        Self.assertSource(worktreeDialogsText, excludes: "struct QuillCodeWorktreeDialogFrame")
        Self.assertSource(dialogChromeText, contains: "struct QuillCodeDialogHeader")
        Self.assertSource(renameDialogsText, contains: "struct QuillCodeThreadRenameView")
        Self.assertSource(renameDialogsText, excludes: "struct QuillCodeCommandPaletteView")
        Self.assertSource(renameDialogsText, excludes: "struct QuillCodeSearchView")
        Self.assertSource(renameDialogsText, excludes: "struct QuillCodeWorktreeCreateView")
        Self.assertSource(shellText, contains: ".quillCodeWorkspaceSheets(")
        Self.assertSource(shellText, contains: "QuillCodeWorktreeDialogCoordinator()")
        Self.assertSource(shellText, excludes: "QuillCodeSettingsView(")
        Self.assertSource(shellText, excludes: "QuillCodeSearchView(")
        Self.assertSource(shellText, excludes: "QuillCodeCommandPaletteView(")
        Self.assertSource(shellText, excludes: "QuillCodeWorktreeCreateView(")
        Self.assertSource(shellText, excludes: "worktreeChoiceLoadTask")
        Self.assertSource(shellText, excludes: "worktreePrunePreviewTask")
        Self.assertSource(shellText, excludes: "QuillCodeThreadRenameView(")
        Self.assertSource(shellText, excludes: ".sheet(isPresented:")
        Self.assertSource(shellText, excludes: ".sheet(item:")
    }

    func testNativeSettingsDelegatesFocusedViewsAndDraftState() throws {
        let settingsText = try Self.appSourceText(named: "QuillCodeSettingsView.swift")
        let computerUseText = try Self.appSourceText(named: "QuillCodeComputerUseSettingsCard.swift")
        let computerUseApprovalsText = try Self.appSourceText(
            named: "QuillCodeComputerUseApprovalSettingsCard.swift"
        )
        let runtimeIssueText = try Self.appSourceText(named: "QuillCodeRuntimeIssueView.swift")
        let draftText = try Self.appSourceText(named: "QuillCodeSettingsDraft.swift")

        Self.assertSource(settingsText, contains: "struct QuillCodeSettingsView")
        Self.assertSource(settingsText, contains: "QuillCodeComputerUseSettingsCard(")
        Self.assertSource(settingsText, contains: "QuillCodeComputerUseApprovalSettingsCard(")
        Self.assertSource(settingsText, contains: "QuillCodeRuntimeIssueView(")
        Self.assertSource(settingsText, contains: "accessibilityIdentifier(\"quillcode-settings-title\")")
        Self.assertSource(settingsText, contains: "accessibilityIdentifier(\"quillcode-settings-close\")")
        Self.assertSource(computerUseText, contains: "struct QuillCodeComputerUseSettingsCard")
        Self.assertSource(computerUseText, contains: "struct QuillCodePermissionRow")
        Self.assertSource(computerUseApprovalsText, contains: "struct QuillCodeComputerUseApprovalSettingsCard")
        Self.assertSource(computerUseApprovalsText, contains: "draft.clearComputerUseApprovals()")
        Self.assertSource(computerUseApprovalsText, contains: "draft.addComputerUseApproval")
        Self.assertSource(computerUseApprovalsText, contains: "Detected foreground app")
        Self.assertSource(computerUseApprovalsText, contains: "Allow Current App")
        Self.assertSource(computerUseApprovalsText, contains: ".quillCodeTextEntryTarget")
        Self.assertSource(computerUseApprovalsText, contains: ".quillCodeFormActionTarget")
        Self.assertSource(draftText, contains: "func addComputerUseApproval")
        Self.assertSource(draftText, contains: "func hasComputerUseApproval")
        Self.assertSource(runtimeIssueText, contains: "struct QuillCodeRuntimeIssueView")
        Self.assertSource(draftText, contains: "struct QuillCodeSettingsDraft")
        Self.assertSource(draftText, contains: "var update: WorkspaceSettingsUpdate")
        Self.assertSource(settingsText, excludes: "struct QuillCodeComputerUseSettingsCard")
        Self.assertSource(settingsText, excludes: "struct QuillCodePermissionRow")
        Self.assertSource(settingsText, excludes: "struct QuillCodeComputerUseApprovalSettingsCard")
        Self.assertSource(settingsText, excludes: "struct QuillCodeRuntimeIssueView")
        Self.assertSource(settingsText, excludes: "struct QuillCodeSettingsDraft")
    }
}
