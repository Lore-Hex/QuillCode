import Foundation
import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class WorkspaceTerminalIntegrationTests: XCTestCase {
    func testTerminalCommandRunsInWorkspaceRootAndRecordsOutput() async throws {
        let root = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Terminal Project")
        model.selectProject(projectID)

        model.toggleTerminal()
        await model.runTerminalCommand("printf terminal-ok", workspaceRoot: root)

        XCTAssertTrue(model.terminal.isVisible)
        XCTAssertFalse(model.terminal.isRunning)
        XCTAssertEqual(model.terminal.entries.count, 1)
        XCTAssertEqual(model.terminal.entries[0].command, "printf terminal-ok")
        XCTAssertEqual(model.terminal.entries[0].stdout, "terminal-ok")
        XCTAssertEqual(model.terminal.entries[0].exitCode, 0)
        XCTAssertTrue(model.terminal.entries[0].ok)

        let surface = model.surface().terminal
        XCTAssertTrue(surface.isVisible)
        XCTAssertEqual(surface.cwdLabel, root.path)
        XCTAssertEqual(surface.entries.first?.statusLabel, "Done")
        XCTAssertEqual(surface.entries.first?.exitCodeLabel, "exit 0")
    }

    func testTerminalCommandRunsThroughSSHRemoteProject() async throws {
        let root = try makeTempDirectory()
        let argumentsFile = root.appendingPathComponent("ssh-args.txt")
        let fakeSSH = try makeFakeSSH(in: root, argumentsFile: argumentsFile)
        let connection = ProjectConnection.ssh(
            path: "/srv/quill repo",
            host: "feather.local",
            user: "quill",
            port: 2222
        )
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )

        await model.runTerminalCommand("printf remote-terminal", workspaceRoot: root)

        XCTAssertEqual(model.terminal.entries.count, 1)
        XCTAssertEqual(model.terminal.entries[0].status, .done)
        XCTAssertEqual(model.terminal.entries[0].stdout, "remote-terminal\n")
        XCTAssertEqual(model.terminal.currentDirectoryPath, "ssh://quill@feather.local:2222/srv/quill repo")
        let surface = model.surface()
        XCTAssertEqual(surface.terminal.cwdLabel, "ssh://quill@feather.local:2222/srv/quill repo")
        XCTAssertEqual(surface.terminal.entries.first?.executionContext?.kind, .sshRemote)
        XCTAssertEqual(surface.terminal.entries.first?.executionContext?.label, "SSH Remote")
        XCTAssertEqual(surface.terminal.entries.first?.executionContext?.detail, "feather.local")
        let arguments = try String(contentsOf: argumentsFile, encoding: .utf8)
        XCTAssertTrue(arguments.contains("-T\n-o\nBatchMode=yes\n-o\nConnectTimeout=4\n-p\n2222\nquill@feather.local\n"))
        XCTAssertTrue(arguments.contains("cd '/srv/quill repo' &&"))
        XCTAssertTrue(arguments.contains("printf remote-terminal"))
        XCTAssertTrue(arguments.contains("__QUILLCODE_TERMINAL_"))
    }

    func testTerminalCommandPersistsSSHRemoteCWDAndEnvironment() async throws {
        let root = try makeTempDirectory()
        let remoteRoot = root.appendingPathComponent("remote repo")
        try FileManager.default.createDirectory(at: remoteRoot, withIntermediateDirectories: true)
        let argumentsFile = root.appendingPathComponent("ssh-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: root, argumentsFile: argumentsFile)
        let connection = ProjectConnection.ssh(
            path: remoteRoot.path,
            host: "feather.local",
            user: "quill"
        )
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )

        await model.runTerminalCommand(
            "mkdir -p nested && cd nested && export QUILL_REMOTE_TERMINAL=works && printf remote-one",
            workspaceRoot: root
        )

        let nestedPath = remoteRoot.appendingPathComponent("nested").path
        XCTAssertEqual(model.terminal.entries[0].status, .done)
        XCTAssertEqual(model.terminal.entries[0].stdout, "remote-one")
        XCTAssertEqual(model.terminal.currentDirectoryPath, "ssh://quill@feather.local\(nestedPath)")
        XCTAssertEqual(model.terminal.environmentOverrides["QUILL_REMOTE_TERMINAL"], "works")

        await model.runTerminalCommand(
            #"pwd && printf ':' && printf "$QUILL_REMOTE_TERMINAL""#,
            workspaceRoot: root
        )

        XCTAssertEqual(model.terminal.entries[1].status, .done)
        XCTAssertEqual(model.terminal.entries[1].stdout, "\(nestedPath)\n:works")
        let arguments = try String(contentsOf: argumentsFile, encoding: .utf8)
        XCTAssertTrue(arguments.contains("cd '\(nestedPath.replacingOccurrences(of: "'", with: "'\\''"))' &&"))
    }

    func testTerminalCommandAppearsAsRunningBeforeCompletion() async throws {
        let root = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel()

        let task = Task {
            await model.runTerminalCommand("sleep 0.2 && printf terminal-done", workspaceRoot: root)
        }
        try await waitUntil(timeoutSeconds: 1) {
            model.terminal.isRunning && model.terminal.entries.first?.status == .running
        }

        XCTAssertEqual(model.terminal.entries.count, 1)
        XCTAssertEqual(model.terminal.entries[0].command, "sleep 0.2 && printf terminal-done")
        XCTAssertEqual(model.surface().terminal.entries.first?.statusLabel, "Running")
        XCTAssertEqual(model.surface().terminal.entries.first?.exitCodeLabel, "running")

        await task.value

        XCTAssertFalse(model.terminal.isRunning)
        XCTAssertEqual(model.terminal.entries.count, 1)
        XCTAssertEqual(model.terminal.entries[0].status, .done)
        XCTAssertEqual(model.terminal.entries[0].stdout, "terminal-done")
    }

    func testTerminalCommandStreamsOutputBeforeCompletion() async throws {
        let root = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel()

        let task = Task {
            await model.runTerminalCommand("echo terminal-start; sleep 0.2; echo terminal-end", workspaceRoot: root)
        }
        try await waitUntil(timeoutSeconds: 1) {
            model.terminal.entries.first?.status == .running
                && model.terminal.entries.first?.stdout.contains("terminal-start") == true
        }

        XCTAssertEqual(model.surface().terminal.entries.first?.statusLabel, "Running")
        XCTAssertTrue(model.surface().terminal.entries.first?.stdout.contains("terminal-start") == true)

        await task.value

        XCTAssertFalse(model.terminal.isRunning)
        XCTAssertEqual(model.terminal.entries.first?.status, .done)
        XCTAssertTrue(model.terminal.entries.first?.stdout.contains("terminal-end") == true)
    }

    func testTerminalCommandPersistsCurrentDirectoryAcrossCommands() async throws {
        let root = try makeQuillCodeTestDirectory()
        let nested = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Terminal Project")

        await model.runTerminalCommand("cd nested", workspaceRoot: root)

        let resolvedNestedPath = nested.resolvingSymlinksInPath().standardizedFileURL.path
        XCTAssertEqual(model.terminal.currentDirectoryPath, resolvedNestedPath)
        XCTAssertEqual(model.surface().terminal.cwdLabel, resolvedNestedPath)

        await model.runTerminalCommand("pwd", workspaceRoot: root)

        let printedPath = try XCTUnwrap(model.terminal.entries.last?.stdout)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(
            URL(fileURLWithPath: printedPath).resolvingSymlinksInPath().path,
            URL(fileURLWithPath: try XCTUnwrap(model.terminal.currentDirectoryPath)).resolvingSymlinksInPath().path
        )
    }

    func testTerminalCommandPersistsEnvironmentAcrossCommands() async throws {
        let root = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Terminal Project")

        await model.runTerminalCommand("export QUILL_TERMINAL_TEST=from-session", workspaceRoot: root)
        await model.runTerminalCommand("printf '%s' \"$QUILL_TERMINAL_TEST\"", workspaceRoot: root)

        XCTAssertEqual(model.terminal.entries.last?.stdout, "from-session")
        XCTAssertEqual(model.terminal.environmentOverrides["QUILL_TERMINAL_TEST"], "from-session")
        XCTAssertNil(model.terminal.environmentOverrides["SHLVL"])
        XCTAssertNil(model.terminal.environmentOverrides["PWD"])

        await model.runTerminalCommand("unset QUILL_TERMINAL_TEST", workspaceRoot: root)
        await model.runTerminalCommand("printf '%s' \"${QUILL_TERMINAL_TEST:-missing}\"", workspaceRoot: root)

        XCTAssertEqual(model.terminal.entries.last?.stdout, "missing")
    }

    func testTerminalClearHistoryKeepsSessionContextAndDraft() async throws {
        let root = try makeQuillCodeTestDirectory()
        let nested = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Terminal Project")

        await model.runTerminalCommand(
            "cd nested && export QUILL_TERMINAL_TEST=from-clear",
            workspaceRoot: root
        )
        model.setTerminalDraft("pwd")

        XCTAssertTrue(model.surface().terminal.canClear)
        XCTAssertTrue(model.clearTerminalHistory())

        XCTAssertTrue(model.terminal.isVisible)
        XCTAssertTrue(model.terminal.entries.isEmpty)
        XCTAssertEqual(model.terminal.draft, "pwd")
        XCTAssertEqual(model.terminal.currentDirectoryPath, nested.standardizedFileURL.path)
        XCTAssertEqual(model.terminal.environmentOverrides["QUILL_TERMINAL_TEST"], "from-clear")
        XCTAssertFalse(model.surface().terminal.canClear)
        XCTAssertEqual(model.surface().terminal.cwdLabel, nested.standardizedFileURL.path)
    }

    func testTerminalClearHistoryDoesNotHideRunningCommand() async throws {
        let root = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel()

        let task = Task {
            await model.runTerminalCommand("sleep 5", workspaceRoot: root)
        }
        try await waitUntil(timeoutSeconds: 1) {
            model.terminal.entries.first?.status == .running
        }

        XCTAssertFalse(model.clearTerminalHistory())
        XCTAssertEqual(model.terminal.entries.count, 1)
        XCTAssertEqual(model.terminal.entries.first?.status, .running)
        XCTAssertFalse(model.surface().terminal.canClear)

        task.cancel()
        model.cancelActiveWork()
        await task.value
    }

    func testTerminalCurrentDirectoryResetsWhenProjectChanges() async throws {
        let firstRoot = try makeQuillCodeTestDirectory()
        let firstNested = firstRoot.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: firstNested, withIntermediateDirectories: true)
        let secondRoot = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: firstRoot, name: "First")

        await model.runTerminalCommand("cd nested", workspaceRoot: firstRoot)
        XCTAssertEqual(model.surface().terminal.cwdLabel, firstNested.standardizedFileURL.path)

        _ = model.addProject(path: secondRoot, name: "Second")

        XCTAssertEqual(model.surface().terminal.cwdLabel, secondRoot.standardizedFileURL.path)
        XCTAssertEqual(model.terminal.currentDirectoryPath, secondRoot.standardizedFileURL.path)
    }

    func testTerminalEnvironmentResetsWhenProjectChanges() async throws {
        let firstRoot = try makeQuillCodeTestDirectory()
        let secondRoot = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: firstRoot, name: "First")

        await model.runTerminalCommand("export QUILL_TERMINAL_TEST=from-first-project", workspaceRoot: firstRoot)
        XCTAssertEqual(model.terminal.environmentOverrides["QUILL_TERMINAL_TEST"], "from-first-project")

        _ = model.addProject(path: secondRoot, name: "Second")
        await model.runTerminalCommand("printf '%s' \"${QUILL_TERMINAL_TEST:-missing}\"", workspaceRoot: secondRoot)

        XCTAssertEqual(model.terminal.environmentOverrides["QUILL_TERMINAL_TEST"], nil)
        XCTAssertEqual(model.terminal.entries.last?.stdout, "missing")
    }

    func testTerminalCancellationMarksRunningEntryStopped() async throws {
        let root = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel()

        let task = Task {
            await model.runTerminalCommand("sleep 5", workspaceRoot: root)
        }
        try await waitUntil(timeoutSeconds: 1) {
            model.terminal.entries.first?.status == .running
        }

        task.cancel()
        model.cancelActiveWork()
        await task.value

        XCTAssertFalse(model.terminal.isRunning)
        XCTAssertEqual(model.terminal.entries.count, 1)
        XCTAssertEqual(model.terminal.entries[0].status, .stopped)
        XCTAssertEqual(model.surface().terminal.entries.first?.statusLabel, "Stopped")
        XCTAssertEqual(model.surface().terminal.entries.first?.exitCodeLabel, "stopped")
        XCTAssertTrue(model.terminal.entries[0].stderr.contains("Command stopped."))
    }

    func testTerminalStopAllKeepsEntryStoppedAfterProcessExits() async throws {
        let root = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel()

        let task = Task {
            await model.runTerminalCommand("sleep 0.2 && printf late-result", workspaceRoot: root)
        }
        try await waitUntil(timeoutSeconds: 1) {
            model.terminal.entries.first?.status == .running
        }

        model.cancelActiveWork()
        await task.value

        XCTAssertFalse(model.terminal.isRunning)
        XCTAssertEqual(model.terminal.entries.count, 1)
        XCTAssertEqual(model.terminal.entries[0].status, .stopped)
        XCTAssertEqual(model.terminal.entries[0].stdout, "")
        XCTAssertEqual(model.terminal.entries[0].stderr, "Command stopped.")
        XCTAssertNil(model.terminal.entries[0].exitCode)
    }

    private func waitUntil(
        timeoutSeconds: TimeInterval,
        condition: @MainActor @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for condition")
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}
