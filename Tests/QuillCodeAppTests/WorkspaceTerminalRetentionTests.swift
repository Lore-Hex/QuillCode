import Foundation
import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

final class WorkspaceTerminalRetentionTests: XCTestCase {
    func testLiveOutputIsBoundedAcrossChunksAndKeepsNewestTail() {
        var terminal = TerminalState()
        let id = WorkspaceTerminalEngine.beginRun(command: "chatty", terminal: &terminal)
        let first = String(repeating: "a", count: ShellOutputCapper.defaultMaxBytes)
        let tail = "LATEST-TERMINAL-TAIL"

        WorkspaceTerminalEngine.appendOutput(id: id, stdout: first, terminal: &terminal)
        WorkspaceTerminalEngine.appendOutput(
            id: id,
            stdout: String(repeating: "b", count: ShellOutputCapper.defaultMaxBytes) + tail,
            terminal: &terminal
        )

        let output = terminal.entries[0].stdout
        XCTAssertTrue(output.contains("output truncated"), output.prefix(120).description)
        XCTAssertTrue(output.hasSuffix(tail))
        XCTAssertFalse(output.contains(String(repeating: "a", count: 100)))
        XCTAssertLessThan(output.utf8.count, ShellOutputCapper.defaultMaxBytes + 200)
        XCTAssertFalse(output.contains("\u{FFFD}"))
    }

    func testControlModesConsumeFullStreamEvenAfterVisiblePrefixIsReleased() {
        var terminal = TerminalState()
        let id = WorkspaceTerminalEngine.beginRun(command: "interactive", terminal: &terminal)

        WorkspaceTerminalEngine.appendOutput(
            id: id,
            stdout: "\u{1B}[?1002;1006;1;2004h",
            terminal: &terminal
        )
        WorkspaceTerminalEngine.appendOutput(
            id: id,
            stdout: String(repeating: "x", count: ShellOutputCapper.defaultMaxBytes * 2),
            terminal: &terminal
        )

        XCTAssertFalse(terminal.entries[0].stdout.contains("\u{1B}[?1002"))
        XCTAssertEqual(
            terminal.mouseReporting,
            TerminalMouseReporting(trackingMode: .buttonMotion, encoding: .sgr)
        )
        XCTAssertEqual(
            terminal.keyboardMode,
            TerminalKeyboardMode(applicationCursorKeys: true, bracketedPaste: true)
        )
    }

    func testFinishedOutputIsDefensivelyBounded() {
        var terminal = TerminalState()
        let id = WorkspaceTerminalEngine.beginRun(command: "oversized-result", terminal: &terminal)
        let tail = "FINAL-RESULT-TAIL"

        WorkspaceTerminalEngine.finishEntry(
            id: id,
            stdout: String(repeating: "z", count: WorkspaceTerminalRetentionPolicy.maximumOutputBytes * 2) + tail,
            stderr: String(repeating: "e", count: WorkspaceTerminalRetentionPolicy.maximumOutputBytes * 2),
            exitCode: 1,
            ok: false,
            status: .failed,
            terminal: &terminal
        )

        XCTAssertTrue(terminal.entries[0].stdout.contains("output truncated"))
        XCTAssertTrue(terminal.entries[0].stdout.hasSuffix(tail))
        XCTAssertTrue(terminal.entries[0].stderr.contains("output truncated"))
        XCTAssertLessThan(
            terminal.entries[0].stdout.utf8.count,
            WorkspaceTerminalRetentionPolicy.maximumOutputBytes + 200
        )
    }

    func testHistoryKeepsLatestCommandsAndSurfacesReleasedCount() {
        let entries = (0..<WorkspaceTerminalRetentionPolicy.maximumEntryCount).map { index in
            TerminalCommandState(
                command: "command-\(index)",
                stdout: "output-\(index)",
                stderr: "",
                exitCode: 0,
                ok: true
            )
        }
        var terminal = TerminalState(isVisible: true, entries: entries)
        let newestID = WorkspaceTerminalEngine.beginRun(
            command: "command-newest",
            terminal: &terminal
        )

        XCTAssertEqual(terminal.entries.count, WorkspaceTerminalRetentionPolicy.maximumEntryCount)
        XCTAssertEqual(terminal.entries.first?.command, "command-1")
        XCTAssertEqual(terminal.entries.last?.command, "command-newest")
        XCTAssertEqual(terminal.discardedEntryCount, 1)

        let surface = TerminalSurface(terminal: terminal, cwd: nil)
        XCTAssertEqual(
            surface.retentionNotice,
            "1 older command released to keep terminal memory bounded."
        )
        let html = WorkspaceHTMLTerminalRenderer.render(surface)
        XCTAssertTrue(html.contains(#"data-testid="terminal-retention-notice""#))
        XCTAssertTrue(html.contains("1 older command released"))

        WorkspaceTerminalEngine.finishEntry(
            id: newestID,
            stdout: "done",
            stderr: "",
            exitCode: 0,
            ok: true,
            status: .done,
            terminal: &terminal
        )
        terminal.isRunning = false
        XCTAssertTrue(WorkspaceTerminalEngine.clearHistory(terminal: &terminal))
        XCTAssertEqual(terminal.discardedEntryCount, 0)
        XCTAssertNil(TerminalSurface(terminal: terminal, cwd: nil).retentionNotice)
    }

    func testInitialStateAndStoppedLiveOutputRemainBounded() {
        let oversizedEntries = (0..<(WorkspaceTerminalRetentionPolicy.maximumEntryCount + 3)).map { index in
            TerminalCommandState(
                command: "command-\(index)",
                stdout: String(repeating: "x", count: WorkspaceTerminalRetentionPolicy.maximumOutputBytes * 2),
                stderr: "",
                exitCode: 0,
                ok: true
            )
        }
        var terminal = TerminalState(entries: oversizedEntries)

        XCTAssertEqual(terminal.entries.count, WorkspaceTerminalRetentionPolicy.maximumEntryCount)
        XCTAssertEqual(terminal.discardedEntryCount, 3)
        XCTAssertTrue(terminal.entries.allSatisfy { $0.stdout.contains("output truncated") })

        let id = WorkspaceTerminalEngine.beginRun(command: "running", terminal: &terminal)
        WorkspaceTerminalEngine.appendOutput(
            id: id,
            stdout: "live-before-stop",
            stderr: "warning-before-stop",
            terminal: &terminal
        )
        WorkspaceTerminalEngine.stopRunningEntries(terminal: &terminal)

        XCTAssertEqual(terminal.entries.last?.status, .stopped)
        XCTAssertEqual(terminal.entries.last?.stdout, "live-before-stop")
        XCTAssertEqual(terminal.entries.last?.stderr, "warning-before-stop")
    }
}
