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

    func testTrackedAssistantTailProgressSkipsLongHistoryTranscriptProjection() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        var events = [ThreadEvent(
            kind: .toolQueued,
            createdAt: timestamp,
            summary: "queued"
        )]
        events.reserveCapacity(50_000)
        for index in 1..<50_000 {
            events.append(ThreadEvent(
                kind: .notice,
                createdAt: timestamp,
                summary: "Progress record \(index)"
            ))
        }
        let assistant = ChatMessage(
            role: .assistant,
            content: "Initial streamed answer",
            createdAt: timestamp
        )
        let thread = ChatThread(
            title: "Long streaming task",
            messages: [ChatMessage(role: .user, content: "Proceed", createdAt: timestamp), assistant],
            events: events
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))
        model.beginAgentRun(
            threadID: thread.id,
            lifecycle: WorkspaceComposerSendLifecycle.started(from: model.composer)
        )
        let previous = model.surface()
        XCTAssertEqual(previous.transcript.toolCards.count, 1)

        var snapshot = try XCTUnwrap(model.selectedThread)
        snapshot.messages[snapshot.messages.index(before: snapshot.messages.endIndex)].content = "Fresh streamed answer"
        snapshot.events[snapshot.events.index(before: snapshot.events.endIndex)].summary = "Thinking: validating"
        model.applyAgentProgress(snapshot, expectedThreadID: thread.id)

        let progress = model.progressSurface(reusing: previous, scope: .agent)
        XCTAssertEqual(progress.transcript.messages.last?.text, "Fresh streamed answer")
        XCTAssertEqual(
            storageAddress(of: progress.transcript.toolCards),
            storageAddress(of: previous.transcript.toolCards),
            "assistant streaming should retain the already-reduced tool-card buffer"
        )
        XCTAssertEqual(progress, model.surface())
    }

    func testBackgroundAgentProgressReusesSelectedLongTranscript() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let selected = ChatThread(
            title: "Foreground history",
            messages: (0..<10_000).map { index in
                ChatMessage(
                    role: index.isMultiple(of: 2) ? .user : .assistant,
                    content: "Turn \(index)",
                    createdAt: timestamp
                )
            },
            events: [ThreadEvent(kind: .toolQueued, createdAt: timestamp, summary: "queued")]
        )
        let background = ChatThread(
            title: "Background run",
            messages: [ChatMessage(role: .user, content: "Keep working", createdAt: timestamp)]
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [selected, background],
            selectedThreadID: selected.id
        ))
        model.beginAgentRun(
            threadID: background.id,
            lifecycle: WorkspaceComposerSendLifecycle.started(from: model.composer)
        )
        let previous = model.surface()

        var snapshot = try XCTUnwrap(model.root.threads.first { $0.id == background.id })
        snapshot.messages.append(ChatMessage(
            role: .assistant,
            content: "Background result",
            createdAt: timestamp
        ))
        model.applyAgentProgress(snapshot, expectedThreadID: background.id)

        let progress = model.progressSurface(reusing: previous, scope: .agent)
        XCTAssertEqual(
            storageAddress(of: progress.transcript.messages),
            storageAddress(of: previous.transcript.messages)
        )
        XCTAssertEqual(
            storageAddress(of: progress.transcript.toolCards),
            storageAddress(of: previous.transcript.toolCards)
        )
        XCTAssertEqual(
            storageAddress(of: progress.transcript.timelineItems),
            storageAddress(of: previous.transcript.timelineItems)
        )
        XCTAssertEqual(progress, model.surface())
    }

    func testToolLifecycleProgressFallsBackToAuthoritativeTranscriptProjection() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let thread = ChatThread(
            messages: [ChatMessage(role: .user, content: "Run it", createdAt: timestamp)],
            events: [ThreadEvent(kind: .toolQueued, createdAt: timestamp, summary: "queued")]
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))
        model.beginAgentRun(
            threadID: thread.id,
            lifecycle: WorkspaceComposerSendLifecycle.started(from: model.composer)
        )
        let previous = model.surface()

        var snapshot = try XCTUnwrap(model.selectedThread)
        snapshot.events.append(ThreadEvent(kind: .toolRunning, createdAt: timestamp, summary: "running"))
        model.applyAgentProgress(snapshot, expectedThreadID: thread.id)

        let progress = model.progressSurface(reusing: previous, scope: .agent)
        XCTAssertEqual(progress.transcript.toolCards.last?.status, .running)
        XCTAssertNotEqual(
            storageAddress(of: progress.transcript.toolCards),
            storageAddress(of: previous.transcript.toolCards)
        )
        XCTAssertEqual(progress, model.surface())
    }

    func testCoalescedAssistantAppendAndTailUpdateMatchesAuthoritativeSurface() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let thread = ChatThread(
            messages: [ChatMessage(role: .user, content: "Stream", createdAt: timestamp)]
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))
        model.beginAgentRun(
            threadID: thread.id,
            lifecycle: WorkspaceComposerSendLifecycle.started(from: model.composer)
        )
        let previous = model.surface()

        var snapshot = try XCTUnwrap(model.selectedThread)
        snapshot.messages.append(ChatMessage(role: .assistant, content: "First", createdAt: timestamp))
        model.applyAgentProgress(snapshot, expectedThreadID: thread.id)
        snapshot.messages[snapshot.messages.index(before: snapshot.messages.endIndex)].content = "First complete chunk"
        model.applyAgentProgress(snapshot, expectedThreadID: thread.id)

        let progress = model.progressSurface(reusing: previous, scope: .agent)
        XCTAssertEqual(progress.transcript.messages.map(\.text), ["Stream", "First complete chunk"])
        XCTAssertEqual(progress, model.surface())
    }

    func testAgentProgressReusesCachedWorktreeEnvironmentProjection() throws {
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
        XCTAssertEqual(model.surface().worktreeEnvironments.options.map(\.title), ["Development"])
        XCTAssertTrue(model.refreshProjectContext(projectID))
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

    private func storageAddress<Element>(of values: [Element]) -> UInt {
        values.withUnsafeBufferPointer { buffer in
            UInt(bitPattern: buffer.baseAddress)
        }
    }
}
