import Foundation
@testable import QuillCodeCLI
import QuillCodeCore
import XCTest

final class MCPServerProgressProjectorTests: XCTestCase {
    func testProjectsToolRunningAndProgressEvents() throws {
        let call = ToolCall(
            id: "call-progress",
            name: ToolDefinition.shellRun.name,
            argumentsJSON: #"{"cmd":"long-task"}"#
        )
        let progress = ToolProgressEventPayload(
            toolCallID: call.id,
            progress: ToolExecutionProgress(completed: 3, total: 12, message: "downloading")
        )
        var snapshot = ChatThread(events: [
            ThreadEvent(
                kind: .toolQueued,
                summary: "queued",
                payloadJSON: try JSONHelpers.encodePretty(call)
            ),
            ThreadEvent(kind: .toolRunning, summary: "host.shell.run running"),
            ThreadEvent(
                kind: .toolProgress,
                summary: "progress",
                payloadJSON: try JSONHelpers.encodePretty(progress)
            )
        ])
        var projector = MCPServerProgressProjector(
            cwd: URL(fileURLWithPath: "/workspace"),
            baseline: ChatThread()
        )

        let events = projector.project(snapshot)
        XCTAssertEqual(events.map { $0.message.objectValue?["type"]?.stringValue }, [
            "exec_command_begin",
            "item_running",
            "item_progress"
        ])

        let running = try XCTUnwrap(events[1].message.objectValue)
        XCTAssertEqual(running["call_id"]?.stringValue, call.id)
        XCTAssertEqual(running["tool"]?.stringValue, ToolDefinition.shellRun.name)
        XCTAssertEqual(running["message"]?.stringValue, "host.shell.run running")

        let progressMessage = try XCTUnwrap(events[2].message.objectValue)
        XCTAssertEqual(progressMessage["call_id"]?.stringValue, call.id)
        XCTAssertEqual(progressMessage["tool"]?.stringValue, ToolDefinition.shellRun.name)
        XCTAssertEqual(progressMessage["completed"]?.numberValue, 3)
        XCTAssertEqual(progressMessage["total"]?.numberValue, 12)
        XCTAssertEqual(progressMessage["fraction"]?.numberValue, 0.25)
        XCTAssertEqual(progressMessage["message"]?.stringValue, "downloading")

        snapshot.events.append(ThreadEvent(kind: .toolCompleted, summary: "done"))
        let finalEvents = projector.project(snapshot)
        XCTAssertEqual(
            finalEvents.first?.message.objectValue?["type"]?.stringValue,
            "exec_command_end"
        )
    }

    func testProgressProjectionOmitsUnavailableFraction() throws {
        let payload = ToolProgressEventPayload(
            toolCallID: "call-zero-total",
            progress: ToolExecutionProgress(
                completed: 5,
                total: 0,
                message: nil
            )
        )
        let snapshot = ChatThread(events: [
            ThreadEvent(
                kind: .toolProgress,
                summary: "still working",
                payloadJSON: try JSONHelpers.encodePretty(payload)
            )
        ])
        var projector = MCPServerProgressProjector(
            cwd: URL(fileURLWithPath: "/workspace"),
            baseline: ChatThread()
        )

        let event = try XCTUnwrap(projector.project(snapshot).first)
        let message = try XCTUnwrap(event.message.objectValue)
        XCTAssertEqual(message["type"]?.stringValue, "item_progress")
        XCTAssertEqual(message["completed"]?.numberValue, 5)
        XCTAssertEqual(message["total"]?.numberValue, 0)
        XCTAssertEqual(message["fraction"], .null)
        XCTAssertEqual(message["message"]?.stringValue, "still working")
    }

    func testAssistantDeltaTruncationPreservesCompleteUnicodeCharacters() throws {
        let baseline = ChatThread()
        var snapshot = baseline
        snapshot.messages = [ChatMessage(
            role: .assistant,
            content: String(repeating: "a", count: 32 * 1_024 - 1) + "🙂tail"
        )]
        var projector = MCPServerProgressProjector(
            cwd: URL(fileURLWithPath: "/workspace"),
            baseline: baseline
        )

        let event = try XCTUnwrap(projector.project(snapshot).first)
        let delta = try XCTUnwrap(event.message.objectValue?["delta"]?.stringValue)

        XCTAssertFalse(delta.contains("\u{FFFD}"))
        XCTAssertFalse(delta.contains("🙂"))
        XCTAssertTrue(delta.hasSuffix("\n[output truncated]"))
    }
}
