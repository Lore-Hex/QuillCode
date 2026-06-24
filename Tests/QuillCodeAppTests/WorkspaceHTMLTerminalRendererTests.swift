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
}
