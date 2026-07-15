import XCTest

final class ParityDesktopGateTests: QuillCodeParityTestCase {
    func testDesktopDefinesNativeMenuBarWidgetAndUnifiedCommandRouting() throws {
        let text = try Self.desktopSourceText()
        let commandsText = try Self.desktopSourceText(named: "DesktopCommands.swift")
        let appText = try Self.desktopSourceText(named: "QuillCodeDesktopApp.swift")
        let shortcutMonitorText = try Self.desktopSourceText(
            named: "QuillCodeDesktopShortcutMonitor.swift"
        )

        Self.assertSource(text, contains: "MenuBarExtra")
        Self.assertSource(text, contains: "QuillCodeMenuBarIcon.image")
        let menuIconText = try Self.desktopSourceText(named: "QuillCodeMenuBarIcon.swift")
        Self.assertSource(menuIconText, contains: "QuillCodeMenuBarTemplate")
        Self.assertSource(menuIconText, contains: "isTemplate = true")

        for label in [
            "New Chat",
            "Open Project",
            "Command Palette",
            "Keyboard Shortcuts",
            "Open Browser Session",
            "Computer Use Setup",
            "Settings",
            "Stop All",
            "Disconnect All"
        ] {
            Self.assertSource(text, contains: label)
        }

        for commandID in [
            "new-chat",
            "quick-chat",
            "search",
            "find-in-chat",
            "workspace-back",
            "workspace-forward",
            "previous-task",
            "next-task",
            "toggle-sidebar",
            "git-diff",
            "toggle-review-panel",
            "toggle-bottom-panel",
            "toggle-terminal",
            "terminal-clear",
            "increase-font-size",
            "decrease-font-size",
            "dictation",
            "command-palette",
            "keyboard-shortcuts"
        ] {
            Self.assertSource(commandsText, contains: "id: \"\(commandID)\"")
        }

        Self.assertSource(commandsText, contains: ".quillCodeRunCommand")
        Self.assertSource(commandsText, contains: ".quillCodeShortcut(commandID, profile: shortcutProfile)")
        Self.assertSource(commandsText, contains: ".disabled(commandsByID[commandID]?.isEnabled != true)")
        Self.assertSource(commandsText, contains: "accessibilityIdentifier(\"quillcode-menu-command-\\(commandID)\")")
        Self.assertSource(appText, contains: "controller.runCommand(commandID: commandID)")
        Self.assertSource(appText, contains: "QuillCodeSecondaryShortcutResolver.commandID")
        Self.assertSource(shortcutMonitorText, contains: "event.charactersIgnoringModifiers?.first")
        Self.assertSource(shortcutMonitorText, contains: "commandsWithPrimaryBinding")

        let menuText = try Self.desktopSourceText(named: "QuillCodeMenuBarView.swift")
        Self.assertSource(menuText, contains: "onDisconnectAll")
        Self.assertSource(menuText, contains: "onOpenBrowserSession")
        XCTAssertFalse(
            menuText.contains(#"Button("Disconnect All") {}"#),
            "Disconnect All must not regress to a no-op button."
        )
        Self.assertSource(menuText, excludes: ".disabled(true)")
    }
}
