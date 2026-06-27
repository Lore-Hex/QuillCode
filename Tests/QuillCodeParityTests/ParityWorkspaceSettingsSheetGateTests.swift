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
        let dialogChromeText = try Self.appSourceText(named: "QuillCodeDialogChrome.swift")

        XCTAssertTrue(sheetsText.contains("struct QuillCodeWorkspaceSheetsModifier"), "Workspace sheet presentation should live in a focused modifier.")
        XCTAssertTrue(sheetsText.contains("func quillCodeWorkspaceSheets("), "Workspace sheet presentation should expose one root-shell modifier.")
        XCTAssertTrue(sheetsText.contains("QuillCodeSettingsView("), "Settings sheet wiring should live in the sheet presenter.")
        XCTAssertTrue(sheetsText.contains("QuillCodeSearchView("), "Search sheet wiring should live in the sheet presenter.")
        XCTAssertTrue(sheetsText.contains("QuillCodeKeyboardShortcutsView("), "Keyboard shortcut sheet wiring should live in the sheet presenter.")
        XCTAssertTrue(sheetsText.contains("QuillCodeCommandPaletteView("), "Command palette sheet wiring should live in the sheet presenter.")
        XCTAssertTrue(sheetsText.contains("QuillCodeWorktreeCreateView("), "Worktree create sheet wiring should live in the sheet presenter.")
        XCTAssertTrue(sheetsText.contains("QuillCodeWorktreeRemoveView("), "Worktree remove sheet wiring should live in the sheet presenter.")
        XCTAssertTrue(sheetsText.contains("QuillCodeThreadRenameView("), "Thread rename sheet wiring should live in the sheet presenter.")
        XCTAssertTrue(sheetsText.contains("QuillCodeProjectRenameView("), "Project rename sheet wiring should live in the sheet presenter.")
        XCTAssertTrue(commandPaletteText.contains("struct QuillCodeCommandPaletteView"), "Command palette UI should live in its focused dialog file.")
        XCTAssertTrue(commandPaletteText.contains("QuillCodeCommandIconCatalog.systemImage"), "Command palette rows should consume the shared command icon catalog.")
        XCTAssertFalse(commandPaletteText.contains("enum QuillCodeCommandIcon"), "Command palette should not maintain a duplicate command icon map.")
        XCTAssertTrue(searchShortcutText.contains("struct QuillCodeSearchView"), "Chat search dialog UI should live with shortcut/search dialogs.")
        XCTAssertTrue(searchShortcutText.contains("struct QuillCodeKeyboardShortcutsView"), "Keyboard shortcut dialog UI should live with shortcut/search dialogs.")
        XCTAssertTrue(worktreeDialogsText.contains("struct QuillCodeWorktreeCreateView"), "Worktree create UI should live in the worktree dialog file.")
        XCTAssertTrue(worktreeDialogsText.contains("struct QuillCodeWorktreeRemoveView"), "Worktree remove UI should live in the worktree dialog file.")
        XCTAssertTrue(worktreeDraftsText.contains("struct QuillCodeWorktreeCreateDraft"), "Worktree draft/request state should live in a focused value file.")
        XCTAssertTrue(worktreeDraftsText.contains("struct QuillCodeWorktreeOpenDraft"), "Worktree open draft state should live in a focused value file.")
        XCTAssertTrue(worktreeDraftsText.contains("struct QuillCodeWorktreeRemoveDraft"), "Worktree remove draft state should live in a focused value file.")
        XCTAssertTrue(worktreeDraftsText.contains("struct QuillCodeWorktreePruneDraft"), "Worktree prune draft state should live in a focused value file.")
        XCTAssertTrue(worktreeChromeText.contains("struct QuillCodeWorktreeChoiceSection"), "Shared worktree choice rows should live in focused worktree dialog chrome.")
        XCTAssertTrue(worktreeChromeText.contains("struct QuillCodeWorktreeDialogFrame"), "Shared worktree sheet frame should live in focused worktree dialog chrome.")
        XCTAssertTrue(worktreeChromeText.contains("QuillCodePressableButtonStyle"), "Worktree choice rows should use shared 0.96 press feedback.")
        XCTAssertTrue(worktreeChromeText.contains("QuillCodeMetrics.minimumHitTarget"), "Worktree choice rows should preserve minimum hit targets.")
        XCTAssertTrue(worktreeCoordinatorText.contains("final class QuillCodeWorktreeDialogCoordinator"), "Worktree dialog lifecycle should live in a focused coordinator.")
        XCTAssertTrue(worktreeCoordinatorText.contains("func presentOpen("), "Worktree open sheet presentation/loading should live in the coordinator.")
        XCTAssertTrue(worktreeCoordinatorText.contains("guard self.sheet == sheet else { return }"), "Worktree choice loading should guard stale sheet results.")
        XCTAssertTrue(worktreeCoordinatorText.contains("choiceLoadTask?.cancel()"), "Worktree choice loading should cancel stale tasks in the coordinator.")
        XCTAssertFalse(worktreeDialogsText.contains("struct QuillCodeWorktreeCreateDraft"), "Worktree dialogs should not own draft/request state.")
        XCTAssertFalse(worktreeDialogsText.contains("struct QuillCodeWorktreeChoiceSection"), "Worktree dialogs should not own shared choice-row chrome.")
        XCTAssertFalse(worktreeDialogsText.contains("struct QuillCodeWorktreeDialogFrame"), "Worktree dialogs should not own shared sheet chrome.")
        XCTAssertTrue(dialogChromeText.contains("struct QuillCodeDialogHeader"), "Shared dialog chrome should live in one reusable file.")
        XCTAssertTrue(renameDialogsText.contains("struct QuillCodeThreadRenameView"), "Rename sheets should remain in the small workspace rename dialog file.")
        XCTAssertFalse(renameDialogsText.contains("struct QuillCodeCommandPaletteView"), "Workspace rename dialogs should not own command palette UI.")
        XCTAssertFalse(renameDialogsText.contains("struct QuillCodeSearchView"), "Workspace rename dialogs should not own search UI.")
        XCTAssertFalse(renameDialogsText.contains("struct QuillCodeWorktreeCreateView"), "Workspace rename dialogs should not own worktree UI.")
        XCTAssertTrue(shellText.contains(".quillCodeWorkspaceSheets("), "Workspace shell should compose the extracted sheet presenter.")
        XCTAssertFalse(shellText.contains("QuillCodeSettingsView("), "Workspace shell should not own settings sheet wiring.")
        XCTAssertFalse(shellText.contains("QuillCodeSearchView("), "Workspace shell should not own search sheet wiring.")
        XCTAssertFalse(shellText.contains("QuillCodeCommandPaletteView("), "Workspace shell should not own command palette sheet wiring.")
        XCTAssertFalse(shellText.contains("QuillCodeWorktreeCreateView("), "Workspace shell should not own worktree create sheet wiring.")
        XCTAssertTrue(shellText.contains("QuillCodeWorktreeDialogCoordinator()"), "Workspace shell should delegate worktree dialog lifecycle.")
        XCTAssertFalse(shellText.contains("worktreeChoiceLoadTask"), "Workspace shell should not own worktree choice loading tasks.")
        XCTAssertFalse(shellText.contains("worktreePrunePreviewTask"), "Workspace shell should not own worktree prune preview tasks.")
        XCTAssertFalse(shellText.contains("QuillCodeThreadRenameView("), "Workspace shell should not own thread rename sheet wiring.")
        XCTAssertFalse(shellText.contains(".sheet(isPresented:"), "Workspace shell should not own sheet presentation modifiers.")
        XCTAssertFalse(shellText.contains(".sheet(item:"), "Workspace shell should not own item sheet presentation modifiers.")
    }

    func testNativeSettingsDelegatesFocusedViewsAndDraftState() throws {
        let settingsText = try Self.appSourceText(named: "QuillCodeSettingsView.swift")
        let computerUseText = try Self.appSourceText(named: "QuillCodeComputerUseSettingsCard.swift")
        let runtimeIssueText = try Self.appSourceText(named: "QuillCodeRuntimeIssueView.swift")
        let draftText = try Self.appSourceText(named: "QuillCodeSettingsDraft.swift")

        XCTAssertTrue(settingsText.contains("struct QuillCodeSettingsView"), "Settings shell should remain in the settings view file.")
        XCTAssertTrue(settingsText.contains("QuillCodeComputerUseSettingsCard("), "Settings shell should compose focused Computer Use onboarding.")
        XCTAssertTrue(settingsText.contains("QuillCodeRuntimeIssueView("), "Settings shell should compose the focused runtime issue callout.")
        XCTAssertTrue(computerUseText.contains("struct QuillCodeComputerUseSettingsCard"), "Computer Use settings UI should live in a focused file.")
        XCTAssertTrue(computerUseText.contains("struct QuillCodePermissionRow"), "Computer Use permission rows should live beside the Computer Use card.")
        XCTAssertTrue(runtimeIssueText.contains("struct QuillCodeRuntimeIssueView"), "Reusable runtime issue callout should live in a focused file.")
        XCTAssertTrue(draftText.contains("struct QuillCodeSettingsDraft"), "Settings draft/update state should live in a focused file.")
        XCTAssertTrue(draftText.contains("var update: WorkspaceSettingsUpdate"), "Settings draft should own update projection.")
        XCTAssertFalse(settingsText.contains("struct QuillCodeComputerUseSettingsCard"), "Settings shell should not own Computer Use card internals.")
        XCTAssertFalse(settingsText.contains("struct QuillCodePermissionRow"), "Settings shell should not own Computer Use permission rows.")
        XCTAssertFalse(settingsText.contains("struct QuillCodeRuntimeIssueView"), "Settings shell should not own runtime issue callout internals.")
        XCTAssertFalse(settingsText.contains("struct QuillCodeSettingsDraft"), "Settings shell should not own settings draft state.")
    }

    func testNativeCompactPlainControlsKeepExplicitHitTargets() throws {
        let computerUseText = try Self.appSourceText(named: "QuillCodeComputerUseSettingsCard.swift")
        let activityText = try Self.appSourceText(named: "WorkspaceActivityPaneView.swift")

        XCTAssertTrue(
            computerUseText.contains(".quillCodeHitTarget(minWidth: 112, alignment: .leading)"),
            "Computer Use refresh should not rely on borderless button default sizing."
        )
        XCTAssertTrue(
            activityText.contains(".frame(maxWidth: .infinity, minHeight: QuillCodeMetrics.minimumHitTarget, alignment: .leading)"),
            "Activity section toggles should keep a full-row 44 pt hit target."
        )
        XCTAssertTrue(
            activityText.contains(".contentShape(Rectangle())"),
            "Activity section toggles should make the full row clickable."
        )
        XCTAssertTrue(
            activityText.contains("QuillCodePressableButtonStyle()"),
            "Activity section toggles should keep shared 0.96 press feedback."
        )
    }

    func testNativeSearchDialogsKeepLocalTypingState() throws {
        let searchShortcutText = try Self.appSourceText(named: "QuillCodeSearchAndShortcutDialogs.swift")
        let commandPaletteText = try Self.appSourceText(named: "QuillCodeCommandPaletteDialog.swift")

        XCTAssertTrue(searchShortcutText.contains("@State private var localQuery"), "Chat search should keep keystrokes in local dialog state while the sheet is active.")
        XCTAssertTrue(searchShortcutText.contains("TextField(\"Search chats\", text: $localQuery)"), "Chat search text entry should not be wired directly to root workspace state.")
        XCTAssertTrue(searchShortcutText.contains(".accessibilityIdentifier(\"quillcode-search-input\")"), "Chat search needs a stable native UI automation identifier.")
        XCTAssertTrue(searchShortcutText.contains("@State private var highlightedThreadID"), "Chat search should keep keyboard result highlight state inside the dialog.")
        XCTAssertTrue(searchShortcutText.contains(".onMoveCommand"), "Chat search should support ArrowUp/ArrowDown result navigation.")
        XCTAssertTrue(searchShortcutText.contains("selectHighlightedResult()"), "Chat search Enter should select the highlighted result.")
        XCTAssertTrue(searchShortcutText.contains("private func focusSearchField()"), "Chat search should refocus after sheet presentation settles.")
        XCTAssertTrue(commandPaletteText.contains("@State private var localQuery"), "Command palette should keep keystrokes in local dialog state while the sheet is active.")
        XCTAssertTrue(commandPaletteText.contains("TextField(\"Search commands, > actions, / slash\", text: $localQuery)"), "Command palette text entry should not be wired directly to root workspace state.")
        XCTAssertTrue(commandPaletteText.contains(".accessibilityIdentifier(\"quillcode-command-palette-input\")"), "Command palette needs a stable native UI automation identifier.")
        XCTAssertTrue(commandPaletteText.contains("private func focusSearchField()"), "Command palette should refocus after sheet presentation settles.")
    }

    func testWorkspaceSurfaceDelegatesSettingsSurfaceContract() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let settingsText = try Self.appSourceText(named: "QuillCodeSettingsSurface.swift")

        XCTAssertTrue(settingsText.contains("public struct WorkspaceSettingsSurface"), "Settings surface records should live beside settings-specific copy and compatibility behavior.")
        XCTAssertTrue(settingsText.contains("public struct WorkspaceSettingsUpdate"), "Settings update records should live beside the settings surface contract.")
        XCTAssertTrue(settingsText.contains("public struct ComputerUseRequirementSurface"), "Computer Use requirement rows should live beside settings permission copy.")
        XCTAssertTrue(settingsText.contains("private static func computerUseStatusLabel"), "Computer Use status copy should be directly guarded outside the aggregate surface file.")
        XCTAssertTrue(settingsText.contains("TrustedRouterDefaults.loopbackCallbackURL"), "TrustedRouter sign-in copy should stay with the settings contract.")
        XCTAssertFalse(surfaceText.contains("public struct WorkspaceSettingsSurface"), "WorkspaceSurface should not own settings surface records.")
        XCTAssertFalse(surfaceText.contains("public struct WorkspaceSettingsUpdate"), "WorkspaceSurface should not own settings update records.")
        XCTAssertFalse(surfaceText.contains("public struct ComputerUseRequirementSurface"), "WorkspaceSurface should not own Computer Use requirement rows.")
        XCTAssertFalse(surfaceText.contains("private static func computerUseStatusLabel"), "WorkspaceSurface should not own Computer Use settings copy.")
        XCTAssertFalse(surfaceText.contains("TrustedRouterDefaults.loopbackCallbackURL"), "WorkspaceSurface should not own TrustedRouter sign-in copy.")
    }

    func testPlaywrightSettingsAndRuntimeFlowsStayInFocusedSpec() throws {
        let testRoot = Self.packageRoot().appendingPathComponent("E2E/playwright/tests")
        let settingsSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("settings.spec.ts"),
            encoding: .utf8
        )
        let coreSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("core.spec.ts"),
            encoding: .utf8
        )
        let settingsFlowNames = [
            "shows actionable Computer Use setup in settings",
            "shows actionable TrustedRouter runtime issue",
            "retries the last user turn from a runtime issue",
            "shows runtime diagnostics in settings",
            "opens model picker from malformed model issue",
            "surfaces rate limits with model-switch recovery and diagnostics",
            "surfaces provider outages with model-switch recovery and diagnostics"
        ]

        XCTAssertTrue(settingsSpecText.contains("harnessURL()"), "Focused settings/runtime flows should reuse the shared harness URL helper.")
        XCTAssertTrue(settingsSpecText.contains("openSettings"), "Focused settings/runtime flows should reuse shared top-bar settings navigation.")
        XCTAssertTrue(settingsSpecText.contains("computer-use-settings"), "Focused settings flows should cover Computer Use onboarding.")
        XCTAssertTrue(settingsSpecText.contains("runtime-diagnostics"), "Focused runtime flows should cover diagnostic redaction.")
        XCTAssertTrue(settingsSpecText.contains("TrustedRouter rate limit reached"), "Focused runtime flows should cover rate-limit recovery.")
        XCTAssertTrue(settingsSpecText.contains("TrustedRouter provider unavailable"), "Focused runtime flows should cover provider-outage recovery.")
        for flowName in settingsFlowNames {
            XCTAssertTrue(settingsSpecText.contains(flowName), "\(flowName) should live in settings.spec.ts.")
            XCTAssertFalse(coreSpecText.contains(flowName), "\(flowName) should not drift back into core.spec.ts.")
        }
    }
}
