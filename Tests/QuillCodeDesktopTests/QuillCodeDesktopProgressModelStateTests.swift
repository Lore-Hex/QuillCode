import XCTest
import QuillCodeCore
@testable import QuillCodeApp
@testable import quill_code_desktop

@MainActor
final class QuillCodeDesktopProgressModelStateTests: XCTestCase {
    func testAgentProgressKeepsLiveComposerAndTerminalDraftOwnership() {
        let thread = ChatThread(messages: [ChatMessage(role: .user, content: "Start")])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))
        var surface = model.surface()
        var draft = "half-typed message"
        var terminalDraft = "half-typed command"
        var browserAddressDraft = "https://old.example"
        model.root.threads[0].messages.append(ChatMessage(role: .assistant, content: "Streaming"))
        model.setBrowserAddressDraft("https://new.example")

        QuillCodeDesktopModelStateCoordinator().refreshProgressState(
            from: model,
            scope: .agent,
            surface: &surface,
            draft: &draft,
            terminalDraft: &terminalDraft,
            browserAddressDraft: &browserAddressDraft,
            isComposerTaskRunning: true
        )

        XCTAssertEqual(draft, "half-typed message")
        XCTAssertEqual(surface.composer.draft, "half-typed message")
        XCTAssertEqual(surface.transcript.messages.last?.text, "Streaming")
        XCTAssertEqual(terminalDraft, "half-typed command")
        XCTAssertEqual(browserAddressDraft, "https://new.example")
    }

    func testTerminalProgressDoesNotTouchComposerOrBrowserDrafts() {
        let thread = ChatThread(messages: [ChatMessage(role: .user, content: "Start")])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))
        let previousComposer = model.surface().composer
        var surface = model.surface()
        var draft = "local composer"
        var terminalDraft = "local terminal"
        var browserAddressDraft = "https://local.example"
        model.setDraft("new model composer")
        model.setBrowserAddressDraft("https://model.example")
        model.terminal = TerminalState(
            isVisible: true,
            draft: "",
            isRunning: true,
            entries: [TerminalCommandState(
                command: "make test",
                stdout: "running",
                stderr: "",
                exitCode: nil,
                ok: true,
                status: .running
            )]
        )

        QuillCodeDesktopModelStateCoordinator().refreshProgressState(
            from: model,
            scope: .terminal,
            surface: &surface,
            draft: &draft,
            terminalDraft: &terminalDraft,
            browserAddressDraft: &browserAddressDraft
        )

        XCTAssertEqual(surface.composer, previousComposer)
        XCTAssertEqual(draft, "local composer")
        XCTAssertEqual(terminalDraft, "local terminal")
        XCTAssertEqual(browserAddressDraft, "https://local.example")
        XCTAssertEqual(surface.terminal.entries.last?.stdout, "running")
    }
}
