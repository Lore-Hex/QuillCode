import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

final class WorkspaceToolEventRecorderTests: XCTestCase {
    func testEventsRecordQueuedRunningAndCompletedStates() throws {
        let call = ToolCall(name: ToolDefinition.shellRun.name, argumentsJSON: #"{"cmd":"whoami"}"#)
        let result = ToolResult(ok: true, stdout: "quill\n", exitCode: 0)

        let events = WorkspaceToolEventRecorder.events(call: call, result: result)
        let eventKinds: [ThreadEventKind] = events.map(\.kind)
        let eventSummaries: [String] = events.map(\.summary)

        XCTAssertEqual(eventKinds, [.toolQueued, .toolRunning, .toolCompleted])
        XCTAssertEqual(eventSummaries, [
            "\(ToolDefinition.shellRun.name) queued",
            "\(ToolDefinition.shellRun.name) running",
            "\(ToolDefinition.shellRun.name) completed"
        ])
        let queuedPayload = try XCTUnwrap(events[0].payloadJSON)
        let queuedCall = try JSONHelpers.decode(ToolCall.self, from: queuedPayload)
        XCTAssertEqual(queuedCall.name, ToolDefinition.shellRun.name)
        XCTAssertEqual(try ToolArguments(queuedCall.argumentsJSON).requiredString("cmd"), "whoami")

        let completedPayload = try XCTUnwrap(events[2].payloadJSON)
        let completedResult = try JSONHelpers.decode(ToolResult.self, from: completedPayload)
        XCTAssertTrue(completedResult.ok)
        XCTAssertEqual(completedResult.stdout, "quill\n")
        XCTAssertEqual(completedResult.exitCode, 0)
    }

    func testEventsRecordFailures() throws {
        let call = ToolCall(name: ToolDefinition.fileRead.name, argumentsJSON: #"{"path":"missing.txt"}"#)
        let result = ToolResult(ok: false, error: "File not found")

        let events = WorkspaceToolEventRecorder.events(call: call, result: result)
        let eventKinds: [ThreadEventKind] = events.map(\.kind)

        XCTAssertEqual(eventKinds, [.toolQueued, .toolRunning, .toolFailed])
        XCTAssertEqual(events[2].summary, "\(ToolDefinition.fileRead.name) failed")
        let failedPayload = try XCTUnwrap(events[2].payloadJSON)
        let failedResult = try JSONHelpers.decode(ToolResult.self, from: failedPayload)
        XCTAssertFalse(failedResult.ok)
        XCTAssertEqual(failedResult.error, "File not found")
    }

    func testQueuedPayloadRedactsEnvironmentValues() throws {
        let call = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: #"{"cmd":"env","env":{"API_KEY":"secret-value"}}"#
        )
        let result = ToolResult(ok: true)

        let events = WorkspaceToolEventRecorder.events(call: call, result: result)

        let queuedPayload = try XCTUnwrap(events[0].payloadJSON)
        XCTAssertFalse(queuedPayload.contains("secret-value"))
        XCTAssertTrue(queuedPayload.contains("<redacted>"))
    }

    func testQueuedPayloadRedactsMemoryRememberContent() throws {
        let call = ToolCall(
            name: ToolDefinition.memoryRemember.name,
            argumentsJSON: #"{"content":"api_key=SYNTHETIC_TEST_SECRET_DO_NOT_USE"}"#
        )
        let result = ToolResult(ok: false, error: "Memory was not saved because it contains a credential.")

        let events = WorkspaceToolEventRecorder.events(call: call, result: result)

        let queuedPayload = try XCTUnwrap(events[0].payloadJSON)
        XCTAssertTrue(queuedPayload.contains(ToolCall.redactedMemoryContentValue))
        XCTAssertFalse(queuedPayload.contains("SYNTHETIC_TEST_SECRET_DO_NOT_USE"))
    }

    func testAppendAddsEventsToThreadInOrder() {
        var thread = ChatThread(events: [
            ThreadEvent(kind: .message, summary: "Existing message")
        ])
        let call = ToolCall(name: ToolDefinition.gitStatus.name, argumentsJSON: "{}")
        let result = ToolResult(ok: true, stdout: "clean")

        WorkspaceToolEventRecorder.append(call: call, result: result, to: &thread)
        let eventKinds: [ThreadEventKind] = thread.events.map(\.kind)

        XCTAssertEqual(eventKinds, [
            .message,
            .toolQueued,
            .toolRunning,
            .toolCompleted
        ])
        XCTAssertEqual(thread.events.last?.summary, "\(ToolDefinition.gitStatus.name) completed")
    }

    func testAppendExecutionRecordsPrimaryAndFollowUpsInOrder() {
        var thread = ChatThread()
        let execution = WorkspaceToolCallExecution(
            primary: WorkspaceRecordedToolResult(
                call: ToolCall(name: ToolDefinition.applyPatch.name, argumentsJSON: "{}"),
                result: ToolResult(ok: true)
            ),
            followUps: [
                WorkspaceRecordedToolResult(
                    call: ToolCall(name: ToolDefinition.gitDiff.name, argumentsJSON: "{}"),
                    result: ToolResult(ok: true, stdout: "diff")
                )
            ]
        )

        WorkspaceToolEventRecorder.append(execution: execution, to: &thread)

        XCTAssertEqual(thread.events.map(\.summary), [
            "\(ToolDefinition.applyPatch.name) queued",
            "\(ToolDefinition.applyPatch.name) running",
            "\(ToolDefinition.applyPatch.name) completed",
            "\(ToolDefinition.gitDiff.name) queued",
            "\(ToolDefinition.gitDiff.name) running",
            "\(ToolDefinition.gitDiff.name) completed"
        ])
    }
}
