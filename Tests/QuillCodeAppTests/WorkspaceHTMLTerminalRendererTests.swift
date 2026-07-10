import XCTest
import QuillCodeCore
@testable import QuillCodeApp

@MainActor
final class WorkspaceHTMLTerminalRendererTests: XCTestCase {
    func testHTMLRendererIncludesVisibleTerminalPane() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()
        model.toggleTerminal()
        await model.runTerminalCommand("printf renderer-ok", workspaceRoot: root)

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="terminal-pane""#))
        XCTAssertTrue(html.contains(#"data-testid="terminal-cwd""#))
        XCTAssertTrue(html.contains(#"data-testid="terminal-entry""#))
        XCTAssertTrue(html.contains(#"data-testid="terminal-clear""#))
        XCTAssertTrue(html.contains("renderer-ok"))
    }

    func testHTMLRendererLabelsRunningAndStoppedTerminalEntries() {
        let model = QuillCodeWorkspaceModel(terminal: TerminalState(
            isVisible: true,
            isRunning: true,
            entries: [
                TerminalCommandState(
                    command: "sleep 5",
                    stdout: "",
                    stderr: "",
                    exitCode: nil,
                    ok: false,
                    status: .running
                ),
                TerminalCommandState(
                    command: "sleep 10",
                    stdout: "",
                    stderr: "Command stopped.",
                    exitCode: nil,
                    ok: false,
                    status: .stopped
                )
            ]
        ))

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains("Running · running"))
        XCTAssertTrue(html.contains("Stopped · stopped"))
        XCTAssertTrue(html.contains(#"class="terminal-status running""#))
        XCTAssertTrue(html.contains(#"class="terminal-status stopped""#))
    }

    func testHTMLRendererPreservesTerminalColorAndEmphasisRuns() {
        let model = QuillCodeWorkspaceModel(terminal: TerminalState(
            isVisible: true,
            entries: [
                TerminalCommandState(
                    command: "ansi-demo",
                    stdout: "\u{1B}[1;3;4;38;2;12;34;56mstyled\u{1B}[0m",
                    stderr: "\u{1B}[31mwarning\u{1B}[0m",
                    exitCode: 0,
                    ok: true
                )
            ]
        ))

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains("ansi-bold"))
        XCTAssertTrue(html.contains("ansi-italic"))
        XCTAssertTrue(html.contains("ansi-underline"))
        XCTAssertTrue(html.contains("color:#0C2238"))
        XCTAssertTrue(html.contains("color:#CD0000"))
        XCTAssertTrue(html.contains(">styled</span>"))
        XCTAssertTrue(html.contains(">warning</span>"))
    }

    func testHTMLRendererExposesActiveTerminalMouseMode() {
        let model = QuillCodeWorkspaceModel(terminal: TerminalState(
            isVisible: true,
            isRunning: true,
            entries: [
                TerminalCommandState(
                    command: "mouse-app",
                    stdout: "\u{1B}[?1002;1006hmenu",
                    stderr: "",
                    exitCode: nil,
                    ok: false,
                    status: .running
                )
            ]
        ))

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="terminal-mouse-mode">Mouse · SGR"#))
        XCTAssertTrue(html.contains(#"data-terminal-mouse-input="true""#))
        XCTAssertTrue(html.contains(#"data-terminal-mouse-encoding="sgr""#))
    }
}
