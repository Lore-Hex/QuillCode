import XCTest
import QuillCodeCore
@testable import QuillCodeApp
@testable import quill_code_desktop

@MainActor
final class QuillCodeDesktopLocalEnvironmentActionTests: XCTestCase {
    func testCommandStartsOffMainActorAndUsesPerChatSendSlot() async throws {
        let root = try makeProject()
        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Desktop Environment")
        model.selectProject(projectID)
        let threadID = model.newChat()
        let action = try XCTUnwrap(model.selectedProject?.localActions.first)
        let gate = DesktopLocalEnvironmentToolResultGate()
        model.cancellableToolRunner = { call, workspaceRoot in
            await gate.run(call: call, workspaceRoot: workspaceRoot)
        }
        let coordinator = QuillCodeDesktopWorkspaceActionCoordinator()
        let tasks = QuillCodeDesktopTaskCoordinator()
        var refreshCount = 0

        XCTAssertTrue(coordinator.runWorkspaceCommand(
            action.id,
            model: model,
            fallbackWorkspaceRoot: root,
            tasks: tasks,
            refresh: { refreshCount += 1 }
        ))
        XCTAssertTrue(tasks.isSendRunning(threadID: threadID))

        try await waitUntil {
            model.currentToolCards.last?.status == .running
        }
        XCTAssertGreaterThanOrEqual(refreshCount, 2)
        XCTAssertFalse(coordinator.runWorkspaceCommand(
            action.id,
            model: model,
            fallbackWorkspaceRoot: root,
            tasks: tasks
        ))
        XCTAssertEqual(model.currentToolCards.count, 1)
        XCTAssertEqual(model.surface().commands.first(where: { $0.id == action.id })?.isEnabled, false)

        let capture = await gate.capture
        XCTAssertEqual(capture?.call.name, "host.shell.run")
        XCTAssertEqual(capture?.workspaceRoot, root.standardizedFileURL)
        await gate.finish(ToolResult(ok: true, stdout: "desktop-ok", exitCode: 0))
        try await waitUntil {
            !tasks.isSendRunning(threadID: threadID)
        }

        XCTAssertEqual(model.currentToolCards.last?.status, .done)
        XCTAssertEqual(model.surface().commands.first(where: { $0.id == action.id })?.isEnabled, true)
        XCTAssertGreaterThanOrEqual(refreshCount, 3)
    }

    func testStopAllCancelsRunningLocalEnvironmentAction() async throws {
        let root = try makeProject()
        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Cancellable Desktop Environment")
        model.selectProject(projectID)
        let threadID = model.newChat()
        let action = try XCTUnwrap(model.selectedProject?.localActions.first)
        model.cancellableToolRunner = { _, _ in
            do {
                try await Task.sleep(for: .seconds(30))
                return ToolResult(ok: true)
            } catch {
                return ToolResult(ok: false, error: "Command cancelled.")
            }
        }
        let tasks = QuillCodeDesktopTaskCoordinator()
        let coordinator = QuillCodeDesktopWorkspaceActionCoordinator()
        XCTAssertTrue(coordinator.runWorkspaceCommand(
            action.id,
            model: model,
            fallbackWorkspaceRoot: root,
            tasks: tasks
        ))
        try await waitUntil {
            model.currentToolCards.last?.status == .running
        }

        var draft = "unsent"
        QuillCodeDesktopActiveWorkCoordinator().stopAll(
            draft: &draft,
            model: model,
            tasks: tasks,
            refresh: {}
        )
        try await waitUntil {
            !model.isCancellableToolRunActive(for: threadID)
        }

        XCTAssertEqual(draft, "")
        XCTAssertFalse(tasks.isSendRunning(threadID: threadID))
        XCTAssertEqual(model.currentToolCards.last?.status, .failed)
        let outputJSON = try XCTUnwrap(model.currentToolCards.last?.outputJSON)
        XCTAssertEqual(
            try JSONHelpers.decode(ToolResult.self, from: outputJSON).error,
            "Command cancelled."
        )
        XCTAssertEqual(model.root.topBar.agentStatus, "Stopped")
    }

    func testManualAutomationRunUsesCancellableDesktopLane() async throws {
        let root = try makeProject()
        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Automated Desktop Environment")
        model.selectProject(projectID)
        let originatingThreadID = model.newChat()
        let action = try XCTUnwrap(model.selectedProject?.localActions.first)
        let automation = try XCTUnwrap(model.createLocalEnvironmentActionAutomation(
            actionID: action.id,
            scheduleDescription: "Manual",
            nextRunAt: nil
        ))
        let gate = DesktopLocalEnvironmentToolResultGate()
        model.cancellableToolRunner = { call, workspaceRoot in
            await gate.run(call: call, workspaceRoot: workspaceRoot)
        }
        let tasks = QuillCodeDesktopTaskCoordinator()
        let coordinator = QuillCodeDesktopWorkspaceActionCoordinator()

        XCTAssertTrue(coordinator.runWorkspaceCommand(
            "automation-run:\(automation.id.uuidString)",
            model: model,
            fallbackWorkspaceRoot: root,
            tasks: tasks
        ))
        XCTAssertTrue(tasks.isSendRunning(threadID: originatingThreadID))
        try await waitUntil {
            model.currentToolCards.last?.status == .running
        }

        let automationThreadID = try XCTUnwrap(model.root.selectedThreadID)
        XCTAssertNotEqual(automationThreadID, originatingThreadID)
        XCTAssertTrue(model.isCancellableToolRunActive(for: automationThreadID))
        await gate.finish(ToolResult(ok: true, stdout: "automation-ok", exitCode: 0))
        try await waitUntil {
            !tasks.isSendRunning(threadID: originatingThreadID)
        }

        XCTAssertEqual(model.currentToolCards.last?.status, .done)
        XCTAssertTrue(model.selectedThread?.events.contains {
            $0.summary == "Scheduled local environment action completed: Desktop Check"
        } == true)
    }

    func testStopAllCancelsDueAutomationRunWithoutStoppingTicker() async throws {
        let root = try makeProject()
        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Due Desktop Environment")
        model.selectProject(projectID)
        let action = try XCTUnwrap(model.selectedProject?.localActions.first)
        _ = try XCTUnwrap(model.createLocalEnvironmentActionAutomation(
            actionID: action.id,
            scheduleDescription: "Now",
            nextRunAt: Date(timeIntervalSince1970: 1)
        ))
        model.cancellableToolRunner = { _, _ in
            do {
                try await Task.sleep(for: .seconds(30))
                return ToolResult(ok: true)
            } catch {
                return ToolResult(ok: false, error: "Command cancelled.")
            }
        }
        let tasks = QuillCodeDesktopTaskCoordinator()
        defer { tasks.cancelAll() }
        QuillCodeDesktopAutomationCoordinator(
            tickIntervalNanoseconds: 60_000_000_000
        ).startTicker(
            model: model,
            tasks: tasks,
            notifier: SilentDesktopAutomationNotifier(),
            refresh: {}
        )
        try await waitUntil {
            model.activeCancellableToolRunCount == 1
        }
        let automationThreadID = try XCTUnwrap(model.root.selectedThreadID)

        var draft = ""
        QuillCodeDesktopActiveWorkCoordinator().stopAll(
            draft: &draft,
            model: model,
            tasks: tasks,
            refresh: {}
        )
        try await waitUntil {
            !model.isCancellableToolRunActive(for: automationThreadID)
        }

        XCTAssertTrue(tasks.isRunning(.automationTicker))
        XCTAssertFalse(tasks.isRunning(.automationRun))
        XCTAssertEqual(model.currentToolCards.last?.status, .failed)
        XCTAssertEqual(model.root.topBar.agentStatus, "Stopped")
    }

    private func makeProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quill-cowork-desktop-local-action-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let actions = root.appendingPathComponent(".quillcode/actions", isDirectory: true)
        try FileManager.default.createDirectory(at: actions, withIntermediateDirectories: true)
        try "printf desktop-ok".write(
            to: actions.appendingPathComponent("desktop-check.sh"),
            atomically: true,
            encoding: .utf8
        )
        return root
    }

    private func waitUntil(
        timeoutSeconds: TimeInterval = 1,
        condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timed out waiting for desktop local action state.")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private actor DesktopLocalEnvironmentToolResultGate {
    struct Capture: Sendable {
        var call: ToolCall
        var workspaceRoot: URL
    }

    private var continuation: CheckedContinuation<ToolResult, Never>?
    private(set) var capture: Capture?

    func run(call: ToolCall, workspaceRoot: URL) async -> ToolResult {
        capture = Capture(call: call, workspaceRoot: workspaceRoot)
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finish(_ result: ToolResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

private struct SilentDesktopAutomationNotifier: QuillCodeAutomationNotifying {
    func deliver(_ report: AutomationRunReport) {}
}
