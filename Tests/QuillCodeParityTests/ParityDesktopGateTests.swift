import XCTest

final class ParityDesktopGateTests: QuillCodeParityTestCase {
    func testDesktopDefinesNativeMenuBarWidget() throws {
        let text = try Self.desktopSourceText()
        let commandsText = try Self.desktopSourceText(named: "DesktopCommands.swift")
        let appText = try Self.desktopSourceText(named: "QuillCodeDesktopApp.swift")

        Self.assertSource(text, contains: "MenuBarExtra")
        Self.assertSource(text, contains: "QuillCodeMenuBarIcon.image")
        let menuIconText = try Self.desktopSourceText(named: "QuillCodeMenuBarIcon.swift")
        Self.assertSource(menuIconText, contains: "QuillCodeMenuBarTemplate")
        Self.assertSource(menuIconText, contains: "isTemplate = true")
        for label in ["New Chat", "Open Project", "Command Palette", "Keyboard Shortcuts", "Open Browser Session", "Computer Use Setup", "Settings", "Stop All", "Disconnect All"] {
            Self.assertSource(text, contains: label)
        }
        for commandID in [
            "workspace-back",
            "workspace-forward",
            "browser-back",
            "browser-forward",
            "browser-reload",
            "cycle-mode",
            "focus-composer"
        ] {
            Self.assertSource(commandsText, contains: ".quillCodeShortcut(\"\(commandID)\")")
            Self.assertSource(appText, contains: "$0.runWorkspaceCommand(\"\(commandID)\")")
        }
        for commandID in ["toggle-activity", "toggle-automations", "toggle-extensions", "toggle-memories"] {
            Self.assertSource(commandsText, contains: ".quillCodeShortcut(\"\(commandID)\")")
        }
        Self.assertSource(appText, contains: "$0.toggleActivity()")
        Self.assertSource(appText, contains: "$0.toggleAutomations()")
        Self.assertSource(appText, contains: "$0.toggleExtensions()")
        Self.assertSource(appText, contains: "$0.toggleMemories()")
        // retry-last-turn has a dedicated controller action (prepares the retry draft + sends),
        // not the generic command executor — but its keyboard shortcut must still be bound.
        Self.assertSource(commandsText, contains: ".quillCodeShortcut(\"retry-last-turn\")")
        Self.assertSource(appText, contains: "$0.retryLastTurn()")
        Self.assertSource(commandsText, contains: "Copy Conversation")
        Self.assertSource(commandsText, contains: ".quillCodeShortcut(\"copy-conversation\")")
        Self.assertSource(commandsText, contains: "quillCodeCopyConversation")
        Self.assertSource(appText, contains: "$0.copyCurrentConversation()")
        Self.assertSource(commandsText, contains: "Export Conversation as Markdown...")
        Self.assertSource(commandsText, contains: "quillCodeExportConversationMarkdown")
        Self.assertSource(appText, contains: "$0.exportCurrentConversationMarkdown()")

        let menuText = try Self.desktopSourceText(named: "QuillCodeMenuBarView.swift")
        Self.assertSource(menuText, contains: "onDisconnectAll")
        Self.assertSource(menuText, contains: "onOpenBrowserSession")
        XCTAssertFalse(menuText.contains(#"Button("Disconnect All") {}"#), "Disconnect All must not regress to a no-op button.")
        Self.assertSource(menuText, excludes: ".disabled(true)")
    }

}
