import XCTest
@testable import QuillCodeApp
@testable import QuillCodeTools

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

    func testTerminalCommandSurfaceRendersAnsiOutputToCleanDisplayText() {
        // Raw PTY output: a colored, carriage-return-redrawn progress line plus a colored stderr.
        let entry = TerminalCommandState(
            command: "build",
            stdout: "\u{1B}[36m[##    ] 33%\r[####  ] 66%\u{1B}[0m\ndone",
            stderr: "\u{1B}[31mwarning\u{1B}[0m\n",
            exitCode: 0,
            ok: true
        )
        let surface = TerminalCommandSurface(entry: entry)

        XCTAssertEqual(surface.stdout, "[####  ] 66%\ndone", "color codes stripped + \\r overwrite collapsed")
        XCTAssertEqual(surface.stderr, "warning\n")
        XCTAssertEqual(surface.stdoutRuns?.first?.style.foreground, .cyan)
        XCTAssertEqual(surface.stderrRuns?.first?.style.foreground, .red)
    }

    func testTerminalCommandSurfaceRendersCursorAddressedTUIOutputToLatestFrame() {
        let firstFrame = [
            "PID CPU MEM",
            "101  1  2",
            "102  3  4"
        ].joined(separator: "\n")
        let entry = TerminalCommandState(
            command: "top -b -n 2",
            stdout: firstFrame
                + "\u{1B}[H"
                + "PID CPU MEM"
                + "\u{1B}[2;6H9"
                + "\u{1B}[3;6H8",
            stderr: "",
            exitCode: 0,
            ok: true
        )

        let surface = TerminalCommandSurface(entry: entry)

        XCTAssertEqual(surface.stdout, "PID CPU MEM\n101  9  2\n102  8  4")
    }

    func testRunningTerminalSurfaceExposesMouseReportingMode() {
        let running = TerminalCommandSurface(entry: TerminalCommandState(
            command: "mouse-app",
            stdout: "\u{1B}[?1000;1006hmenu",
            stderr: "",
            exitCode: nil,
            ok: false,
            status: .running
        ))
        let completed = TerminalCommandSurface(entry: TerminalCommandState(
            command: "mouse-app",
            stdout: "\u{1B}[?1000;1006hmenu",
            stderr: "",
            exitCode: 0,
            ok: true,
            status: .done
        ))

        XCTAssertTrue(running.acceptsMouseInput)
        XCTAssertEqual(running.mouseReporting, TerminalMouseReporting(trackingMode: .button, encoding: .sgr))
        XCTAssertEqual(running.mouseInputLabel, "Mouse · SGR")
        XCTAssertFalse(completed.acceptsMouseInput)
        XCTAssertNil(completed.mouseInputLabel)
    }

    func testTerminalCommandSurfaceUsesInjectedAmbiguousWidthPolicyForLocaleFrames() {
        let raw = "ΩX\u{1B}[1;3HY"
        let entry = TerminalCommandState(
            command: "locale-sensitive-tui",
            stdout: raw,
            stderr: raw,
            exitCode: 0,
            ok: true
        )

        let narrow = TerminalCommandSurface(entry: entry, ambiguousWidthPolicy: .narrow)
        let wide = TerminalCommandSurface(
            entry: entry,
            ambiguousWidthPolicy: .automatic(localeIdentifier: "ja_JP", environment: [:])
        )

        XCTAssertEqual(narrow.stdout, "ΩXY")
        XCTAssertEqual(narrow.stderr, "ΩXY")
        XCTAssertEqual(wide.stdout, "ΩY")
        XCTAssertEqual(wide.stderr, "ΩY")
    }

    func testTerminalSurfacePassesAmbiguousWidthPolicyToEntries() {
        let terminal = TerminalState(
            isVisible: true,
            draft: "",
            entries: [
                TerminalCommandState(
                    command: "locale-sensitive-tui",
                    stdout: "ΩX\u{1B}[1;3HY",
                    stderr: "",
                    exitCode: 0,
                    ok: true
                )
            ]
        )

        let surface = TerminalSurface(
            terminal: terminal,
            cwd: URL(fileURLWithPath: "/workspace"),
            ambiguousWidthPolicy: .wide
        )

        XCTAssertEqual(surface.entries.first?.stdout, "ΩY")
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

    func testTerminalWindowSizeEstimatorMapsRenderedPointsToCells() {
        let size = TerminalWindowSizeEstimator.terminalWindowSize(for: CGSize(width: 840, height: 180))
        XCTAssertEqual(size?.rows, 10)
        XCTAssertEqual(size?.columns, 100)

        let tiny = TerminalWindowSizeEstimator.terminalWindowSize(for: CGSize(width: 10, height: 10))
        XCTAssertEqual(tiny?.rows, 4)
        XCTAssertEqual(tiny?.columns, 20)

        XCTAssertNil(TerminalWindowSizeEstimator.terminalWindowSize(for: .zero))
    }
}
