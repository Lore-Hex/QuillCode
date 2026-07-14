import Foundation
import XCTest
import QuillCodeCore
@testable import QuillComputerUseKit

final class WorkflowRecordingTests: XCTestCase {
    func testCaptureBoundsEventsSnapshotsAndBuildsSkillDraftingPrompt() throws {
        let now = Date()
        let events = (0..<(WorkflowRecordingLimits.eventCount + 3)).map { index in
            WorkflowRecordingEvent(
                kind: .click,
                elapsedMilliseconds: index * 100,
                summary: "Clicked item \(index)."
            )
        }
        let snapshots = (0..<(WorkflowRecordingLimits.snapshotCount + 2)).map { index in
            WorkflowRecordingSnapshot(
                path: "/tmp/workflow-\(index).png",
                width: 800,
                height: 600,
                elapsedMilliseconds: index * 1_000
            )
        }

        let capture = WorkflowRecordingCapture(
            goal: "Publish the release",
            startedAt: now,
            stoppedAt: now.addingTimeInterval(12),
            events: events,
            snapshots: snapshots
        )

        XCTAssertEqual(capture.events.count, WorkflowRecordingLimits.eventCount)
        XCTAssertEqual(capture.snapshots.count, WorkflowRecordingLimits.snapshotCount)
        XCTAssertEqual(capture.omittedEventCount, 3)
        XCTAssertEqual(capture.omittedSnapshotCount, 2)
        XCTAssertEqual(capture.durationSeconds, 12)
        XCTAssertTrue(capture.skillDraftingPrompt.contains("Goal: Publish the release"))
        XCTAssertTrue(capture.skillDraftingPrompt.contains("`.quillcode/skills/<safe-slug>/SKILL.md`"))
        XCTAssertTrue(capture.skillDraftingPrompt.contains("Never include credentials"))
    }

    func testRepresentativeSnapshotsSpanTheWholeWorkflow() {
        let snapshots = (0..<12).map { index in
            WorkflowRecordingSnapshot(
                path: "/tmp/workflow-\(index).png",
                width: 800,
                height: 600,
                elapsedMilliseconds: index * 1_000
            )
        }
        let capture = WorkflowRecordingCapture(
            goal: "Publish the release",
            startedAt: Date(timeIntervalSince1970: 0),
            stoppedAt: Date(timeIntervalSince1970: 12),
            events: [],
            snapshots: snapshots
        )

        XCTAssertEqual(
            capture.representativeSnapshots(maximumCount: 4).map(\.path),
            [
                "/tmp/workflow-0.png",
                "/tmp/workflow-4.png",
                "/tmp/workflow-7.png",
                "/tmp/workflow-11.png"
            ]
        )
        XCTAssertEqual(
            capture.representativeSnapshots(maximumCount: 1).map(\.path),
            ["/tmp/workflow-11.png"]
        )
        XCTAssertTrue(capture.representativeSnapshots(maximumCount: 0).isEmpty)
    }

    func testCaptureDecodesLegacyPayloadWithoutDurationLimitField() throws {
        let json = """
        {
          "goal": "Publish the release",
          "startedAt": 0,
          "stoppedAt": 12,
          "events": [],
          "snapshots": [],
          "omittedEventCount": 0,
          "omittedSnapshotCount": 0
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let capture = try decoder.decode(
            WorkflowRecordingCapture.self,
            from: Data(json.utf8)
        )

        XCTAssertFalse(capture.reachedDurationLimit)
    }

    func testDurationLimitIsDisclosedInStatusAndSkillPrompt() async throws {
#if canImport(AppKit) && canImport(ApplicationServices) && canImport(CoreGraphics)
        let directory = temporaryDirectory()
        let recorder = MacWorkflowRecorder(
            statusStore: MacWorkflowRecordingStatusStore(),
            durationSeconds: 0.02
        )
        _ = try await recorder.start(WorkflowRecordingRequest(
            goal: "Publish the release",
            artifactDirectory: directory.path
        ))

        try await Task.sleep(nanoseconds: 60_000_000)
        let status = await recorder.status()
        XCTAssertTrue(status.isRecording, "limit-reached sessions must keep Stop available")
        XCTAssertTrue(status.hasReachedDurationLimit)

        let capture = try await recorder.stop()
        XCTAssertTrue(capture.reachedDurationLimit)
        XCTAssertTrue(capture.skillDraftingPrompt.contains("later actions were not captured"))
#endif
    }

    func testConcurrentStartAndCancelAlwaysLeavesRecorderIdle() async {
#if canImport(AppKit) && canImport(ApplicationServices) && canImport(CoreGraphics)
        let directory = temporaryDirectory()
        let recorder = MacWorkflowRecorder(statusStore: MacWorkflowRecordingStatusStore())
        let start = Task {
            try? await recorder.start(WorkflowRecordingRequest(
                goal: "Publish the release",
                artifactDirectory: directory.path
            ))
        }

        await Task.yield()
        await recorder.cancel()
        _ = await start.value
        await recorder.cancel()

        let status = await recorder.status()
        XCTAssertEqual(status.phase, .idle)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
#endif
    }

    func testConcurrentStartAndStopNeverLeavesRecorderActive() async {
#if canImport(AppKit) && canImport(ApplicationServices) && canImport(CoreGraphics)
        let directory = temporaryDirectory()
        let startupGate = WorkflowRecorderStartupGate()
        let recorder = MacWorkflowRecorder(
            statusStore: MacWorkflowRecordingStatusStore(),
            beforeMonitorInstallation: { await startupGate.pause() }
        )
        let start = Task {
            do {
                _ = try await recorder.start(WorkflowRecordingRequest(
                    goal: "Publish the release",
                    artifactDirectory: directory.path
                ))
                return true
            } catch {
                return false
            }
        }

        await startupGate.waitUntilPaused()
        do {
            _ = try await recorder.stop()
            XCTFail("stopping during startup must cancel the pending recording")
        } catch {}
        await startupGate.resume()

        let didStart = await start.value
        XCTAssertFalse(didStart)

        let status = await recorder.status()
        XCTAssertEqual(status.phase, .idle)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
#endif
    }

    func testExecutorStartsAndStopsRecordingWithOwnerContext() async throws {
        let backend = RecordingComputerUseBackend()
        let artifactDirectory = temporaryDirectory()
        let executor = ComputerUseToolExecutor(
            backend: backend,
            artifactDirectory: artifactDirectory,
            originThreadID: "thread-1",
            projectID: "project-1",
            workspaceRoot: "/workspace"
        )

        let startResult = await executor.execute(ToolCall(
            name: ToolDefinition.workflowRecordStart.name,
            argumentsJSON: #"{"goal":"Publish a release"}"#
        ))
        let start = try XCTUnwrap(startResult)
        XCTAssertTrue(start.ok)
        let status = try JSONHelpers.decode(WorkflowRecordingStatus.self, from: start.stdout)
        XCTAssertTrue(status.isRecording)

        let latestRequest = await backend.latestRequest()
        let request = try XCTUnwrap(latestRequest)
        XCTAssertEqual(request.goal, "Publish a release")
        XCTAssertEqual(request.originThreadID, "thread-1")
        XCTAssertEqual(request.projectID, "project-1")
        XCTAssertEqual(request.workspaceRoot, "/workspace")
        XCTAssertTrue(request.artifactDirectory.hasPrefix(artifactDirectory.path))

        let stopResult = await executor.execute(ToolCall(
            name: ToolDefinition.workflowRecordStop.name,
            argumentsJSON: "{}"
        ))
        let stop = try XCTUnwrap(stopResult)
        XCTAssertTrue(stop.ok)
        XCTAssertEqual(stop.artifacts, ["/tmp/workflow-final.png"])
        let capture = try JSONHelpers.decode(WorkflowRecordingCapture.self, from: stop.stdout)
        XCTAssertEqual(capture.goal, "Publish a release")
    }

    func testExecutorRejectsEmptyGoalBeforeStartingBackend() async throws {
        let backend = RecordingComputerUseBackend()
        let executor = ComputerUseToolExecutor(backend: backend)

        let toolResult = await executor.execute(ToolCall(
            name: ToolDefinition.workflowRecordStart.name,
            argumentsJSON: #"{"goal":"   "}"#
        ))
        let result = try XCTUnwrap(toolResult)

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "Missing required string argument: goal")
        let latestRequest = await backend.latestRequest()
        XCTAssertNil(latestRequest)
    }

    func testStartRequiresBothComputerUsePermissions() async throws {
        let backend = RecordingComputerUseBackend(status: .permissionStatus(
            screenRecordingGranted: true,
            accessibilityGranted: false
        ))
        let executor = ComputerUseToolExecutor(backend: backend)

        let toolResult = await executor.execute(ToolCall(
            name: ToolDefinition.workflowRecordStart.name,
            argumentsJSON: #"{"goal":"Record a skill"}"#
        ))
        let result = try XCTUnwrap(toolResult)

        XCTAssertFalse(result.ok)
        XCTAssertEqual(
            result.error,
            "Computer Use workflow recording needs Accessibility. Open Computer Use setup from Settings, grant Accessibility, then refresh status."
        )
    }

    func testStopRemainsAvailableAfterPermissionsAreRevoked() async throws {
        let backend = RecordingComputerUseBackend(status: .permissionStatus(
            screenRecordingGranted: false,
            accessibilityGranted: false
        ))
        let executor = ComputerUseToolExecutor(backend: backend)

        let toolResult = await executor.execute(ToolCall(
            name: ToolDefinition.workflowRecordStop.name,
            argumentsJSON: "{}"
        ))
        let result = try XCTUnwrap(toolResult)

        XCTAssertTrue(result.ok)
    }

    func testGenericBackendReportsRecordingUnavailable() async throws {
        let executor = ComputerUseToolExecutor(backend: StubComputerUseBackend())

        let toolResult = await executor.execute(ToolCall(
            name: ToolDefinition.workflowRecordStart.name,
            argumentsJSON: #"{"goal":"Record a skill"}"#
        ))
        let result = try XCTUnwrap(toolResult)

        XCTAssertFalse(result.ok)
        XCTAssertEqual(
            result.error,
            "Workflow recording is unavailable on this Computer Use backend."
        )
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkflowRecordingTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}

private actor WorkflowRecorderStartupGate {
    private var isPaused = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func pause() async {
        isPaused = true
        entryWaiters.forEach { $0.resume() }
        entryWaiters.removeAll()
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilPaused() async {
        guard !isPaused else { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func resume() {
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

private actor RecordingComputerUseBackend: ComputerUseBackend, WorkflowRecordingBackend {
    nonisolated let status: ComputerUseStatus
    nonisolated let workflowRecordingStatusSnapshot: WorkflowRecordingStatus = .idle
    private var request: WorkflowRecordingRequest?

    init(status: ComputerUseStatus = .permissionStatus(
        screenRecordingGranted: true,
        accessibilityGranted: true
    )) {
        self.status = status
    }

    func latestRequest() -> WorkflowRecordingRequest? {
        request
    }

    func workflowRecordingStatus() async -> WorkflowRecordingStatus {
        request == nil ? .idle : WorkflowRecordingStatus(phase: .recording, goal: request?.goal)
    }

    func startWorkflowRecording(_ request: WorkflowRecordingRequest) async throws -> WorkflowRecordingStatus {
        self.request = request
        return WorkflowRecordingStatus(phase: .recording, goal: request.goal, startedAt: Date())
    }

    func stopWorkflowRecording() async throws -> WorkflowRecordingCapture {
        let goal = request?.goal ?? "Recorded workflow"
        request = nil
        return WorkflowRecordingCapture(
            goal: goal,
            startedAt: Date(timeIntervalSince1970: 10),
            stoppedAt: Date(timeIntervalSince1970: 12),
            events: [],
            snapshots: [WorkflowRecordingSnapshot(
                path: "/tmp/workflow-final.png",
                width: 800,
                height: 600,
                elapsedMilliseconds: 2_000
            )]
        )
    }

    func cancelWorkflowRecording() async {
        request = nil
    }

    func screenshot() async throws -> ComputerScreenshot {
        ComputerScreenshot(width: 1, height: 1, pngBase64: "iVBORw0KGgo=")
    }

    func leftClick(x: Int, y: Int) async throws {}
    func type(_ text: String) async throws {}
    func scroll(dx: Int, dy: Int) async throws {}
    func moveCursor(x: Int, y: Int) async throws {}
    func pressKey(_ key: String) async throws {}
}
