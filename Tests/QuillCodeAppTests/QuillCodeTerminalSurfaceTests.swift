import XCTest
@testable import QuillCodeApp

final class QuillCodeTerminalSurfaceTests: XCTestCase {
    func testTerminalSurfaceUsesExplicitCWDAndRunClearRules() {
        let terminal = TerminalState(
            currentDirectoryPath: "/fallback",
            isVisible: true,
            draft: "  swift test  ",
            isRunning: false,
            entries: [
                TerminalCommandState(
                    command: "whoami",
                    stdout: "quill\n",
                    stderr: "",
                    exitCode: 0,
                    ok: true
                )
            ]
        )

        let surface = TerminalSurface(
            terminal: terminal,
            cwd: URL(fileURLWithPath: "/workspace")
        )

        XCTAssertTrue(surface.isVisible)
        XCTAssertEqual(surface.cwdLabel, "/workspace")
        XCTAssertEqual(surface.draft, "  swift test  ")
        XCTAssertTrue(surface.canRun)
        XCTAssertTrue(surface.canSubmitDraft)
        XCTAssertTrue(surface.canClear)
        XCTAssertEqual(surface.commandPlaceholder, "Run command")
        XCTAssertEqual(surface.commandActionTitle, "Run")
        XCTAssertEqual(surface.entries.first?.statusLabel, "Done")
        XCTAssertEqual(surface.entries.first?.exitCodeLabel, "exit 0")
    }

    func testTerminalSurfaceDisablesRunAndClearButAllowsInputSubmitWhileRunning() {
        let terminal = TerminalState(
            currentDirectoryPath: "/workspace",
            isVisible: true,
            draft: "tail -f log",
            isRunning: true,
            entries: [
                TerminalCommandState(
                    command: "tail -f log",
                    stdout: "line\n",
                    stderr: "",
                    exitCode: nil,
                    ok: false,
                    status: .running
                )
            ]
        )

        let surface = TerminalSurface(terminal: terminal, cwd: nil)

        XCTAssertEqual(surface.cwdLabel, "/workspace")
        XCTAssertFalse(surface.canRun)
        XCTAssertTrue(surface.canSubmitDraft)
        XCTAssertFalse(surface.canClear)
        XCTAssertEqual(surface.commandPlaceholder, "Send input")
        XCTAssertEqual(surface.commandActionTitle, "Send")
        XCTAssertTrue(surface.entries[0].isRunning)
        XCTAssertEqual(surface.entries[0].statusLabel, "Running")
        XCTAssertEqual(surface.entries[0].exitCodeLabel, "running")
    }

    func testTerminalCommandSurfaceMapsFailureStoppedAndExecutionContext() {
        let failed = TerminalCommandSurface(
            entry: TerminalCommandState(
                command: "false",
                stdout: "",
                stderr: "nope\n",
                exitCode: 1,
                ok: false,
                executionContext: .local(path: "/workspace")
            )
        )
        let stopped = TerminalCommandSurface(
            entry: TerminalCommandState(
                command: "sleep 100",
                stdout: "",
                stderr: "",
                exitCode: nil,
                ok: false,
                status: .stopped,
                executionContext: ExecutionContextSurface(
                    kind: .sshRemote,
                    label: "SSH Remote",
                    detail: "feather.local"
                )
            )
        )

        XCTAssertFalse(failed.isSuccess)
        XCTAssertFalse(failed.isRunning)
        XCTAssertFalse(failed.isStopped)
        XCTAssertEqual(failed.statusLabel, "Failed")
        XCTAssertEqual(failed.exitCodeLabel, "exit 1")
        XCTAssertEqual(failed.executionContext?.kind, .local)
        XCTAssertTrue(stopped.isStopped)
        XCTAssertEqual(stopped.statusLabel, "Stopped")
        XCTAssertEqual(stopped.exitCodeLabel, "stopped")
        XCTAssertEqual(stopped.executionContext?.kind, .sshRemote)
    }

    func testTerminalSurfaceUsesNoProjectWhenCWDIsUnavailable() {
        let terminal = TerminalState(isVisible: true, draft: "   ")
        let surface = TerminalSurface(terminal: terminal, cwd: nil)

        XCTAssertEqual(surface.cwdLabel, "No project")
        XCTAssertFalse(surface.canRun)
        XCTAssertFalse(surface.canSubmitDraft)
        XCTAssertFalse(surface.canClear)
        XCTAssertTrue(surface.entries.isEmpty)
    }
}
