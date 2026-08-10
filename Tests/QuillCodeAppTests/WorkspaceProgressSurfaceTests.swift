import Foundation
import XCTest
import QuillCodeCore
@testable import QuillCodeApp

@MainActor
final class WorkspaceProgressSurfaceTests: XCTestCase {
    func testAgentProgressMatchesAuthoritativeSurfaceForFiftyThousandEventHistory() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let eventCount = 50_000
        var events: [ThreadEvent] = []
        var messages: [ChatMessage] = []
        events.reserveCapacity(eventCount)
        messages.reserveCapacity(eventCount / 10)

        for index in 0..<eventCount {
            events.append(ThreadEvent(
                kind: .notice,
                createdAt: timestamp,
                summary: "Progress record \(index)"
            ))
            if index.isMultiple(of: 10) {
                messages.append(ChatMessage(
                    role: index.isMultiple(of: 20) ? .user : .assistant,
                    content: "Daily-driving turn \(index)",
                    createdAt: timestamp
                ))
            }
        }

        let thread = ChatThread(
            title: "Long-running task",
            messages: messages,
            events: events
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))
        let previous = model.surface()

        model.root.threads[0].messages.append(ChatMessage(
            role: .assistant,
            content: "Fresh streamed answer",
            createdAt: timestamp
        ))
        model.root.threads[0].events.append(ThreadEvent(
            kind: .notice,
            createdAt: timestamp,
            summary: "Fresh streamed progress"
        ))

        let progress = model.progressSurface(reusing: previous, scope: .agent)
        let authoritative = model.surface()

        XCTAssertEqual(progress, authoritative)
        XCTAssertEqual(progress.transcript.messages.last?.text, "Fresh streamed answer")
        XCTAssertEqual(progress.settings, previous.settings)
        XCTAssertEqual(progress.automations, previous.automations)
        XCTAssertEqual(progress.worktreeEnvironments, previous.worktreeEnvironments)
        XCTAssertEqual(progress.terminal, previous.terminal)
    }

    func testTerminalProgressUpdatesTerminalAndStatusWithoutRebuildingAgentHistory() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let thread = ChatThread(
            title: "Terminal task",
            messages: (0..<10_000).map { index in
                ChatMessage(
                    role: index.isMultiple(of: 2) ? .user : .assistant,
                    content: "Turn \(index)",
                    createdAt: timestamp
                )
            }
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))
        let previous = model.surface()
        model.terminal = TerminalState(
            isVisible: true,
            isRunning: true,
            entries: [TerminalCommandState(
                command: "swift test",
                stdout: "Building...",
                stderr: "",
                exitCode: nil,
                ok: true,
                status: .running,
                createdAt: timestamp
            )]
        )
        model.root.topBar.agentStatus = TopBarAgentStatusLabel.running

        let progress = model.progressSurface(reusing: previous, scope: .terminal)
        let authoritative = model.surface()

        XCTAssertEqual(progress.terminal, authoritative.terminal)
        XCTAssertEqual(progress.commands, authoritative.commands)
        XCTAssertEqual(progress.topBar.agentStatus, authoritative.topBar.agentStatus)
        XCTAssertEqual(progress.topBar.runtimeIssueLabel, authoritative.topBar.runtimeIssueLabel)
        XCTAssertEqual(progress.topBar.runtimeIssueSeverity, authoritative.topBar.runtimeIssueSeverity)
        XCTAssertEqual(progress.topBar.branchStatusLabel, authoritative.topBar.branchStatusLabel)
        XCTAssertEqual(progress.runtimeIssue, authoritative.runtimeIssue)
        XCTAssertEqual(progress.lastError, authoritative.lastError)
        XCTAssertEqual(progress.terminal.entries.last?.stdout, "Building...")
        XCTAssertEqual(progress.transcript, previous.transcript)
        XCTAssertEqual(progress.settings, previous.settings)
        XCTAssertEqual(progress.automations, previous.automations)
        XCTAssertEqual(progress.worktreeEnvironments, previous.worktreeEnvironments)
    }

    func testAgentProgressReusesFilesystemBackedWorktreeEnvironmentProjection() throws {
        let root = try makeQuillCodeTestDirectory()
        let configurationDirectory = root.appendingPathComponent(".quillcode")
        let configurationURL = configurationDirectory.appendingPathComponent("config.toml")
        try FileManager.default.createDirectory(
            at: configurationDirectory,
            withIntermediateDirectories: true
        )
        try writeEnvironment(named: "development", title: "Development", to: configurationURL)

        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Scoped refresh")
        model.selectProject(projectID)
        let previous = model.surface()
        XCTAssertEqual(previous.worktreeEnvironments.options.map(\.title), ["Development"])

        try writeEnvironment(named: "release", title: "Release", to: configurationURL)
        let progress = model.progressSurface(reusing: previous, scope: .agent)

        XCTAssertEqual(progress.worktreeEnvironments, previous.worktreeEnvironments)
        previous.worktreeEnvironments.options.withUnsafeBufferPointer { previousBuffer in
            progress.worktreeEnvironments.options.withUnsafeBufferPointer { progressBuffer in
                XCTAssertEqual(previousBuffer.baseAddress, progressBuffer.baseAddress)
            }
        }
        XCTAssertEqual(model.surface().worktreeEnvironments.options.map(\.title), ["Release"])
    }

    func testEmptyProgressScopeReturnsSurfaceUnchanged() {
        let model = QuillCodeWorkspaceModel()
        let previous = model.surface()

        XCTAssertEqual(model.progressSurface(reusing: previous, scope: []), previous)
    }

    private func writeEnvironment(named name: String, title: String, to url: URL) throws {
        try """
        [worktree_setup]
        default_environment = "\(name)"

        [local_environments.\(name)]
        title = "\(title)"
        """.write(to: url, atomically: true, encoding: .utf8)
    }
}
