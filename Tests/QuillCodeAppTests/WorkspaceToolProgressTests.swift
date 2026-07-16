import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

final class WorkspaceToolProgressTests: XCTestCase {
    func testProgressUpdatesExactActiveCardAndTerminalResultClearsIt() throws {
        let call = ToolCall(
            id: "tool-1",
            name: ToolDefinition.mcpCall.name,
            argumentsJSON: #"{"serverID":"docs","toolName":"index","arguments":{}}"#
        )
        var reducer = WorkspaceToolCardEventReducer<[ToolCardState]>.toolCardList()
        reducer.apply(try queuedEvent(call))
        reducer.apply(progressEvent(toolCallID: "other", completed: 25, total: 100, message: "Wrong"))
        XCTAssertNil(reducer.state.first?.progress)

        reducer.apply(progressEvent(toolCallID: call.id, completed: 25, total: 100, message: "Indexing"))
        XCTAssertEqual(reducer.state.count, 1)
        XCTAssertEqual(reducer.state.first?.status, .running)
        XCTAssertEqual(reducer.state.first?.subtitle, "Indexing")
        XCTAssertEqual(reducer.state.first?.progress?.fractionCompleted, 0.25)
        XCTAssertEqual(reducer.state.first?.progress?.percentLabel, "25%")

        reducer.apply(ThreadEvent(
            kind: .toolCompleted,
            summary: "host.mcp.call completed",
            payloadJSON: try JSONHelpers.encodePretty(ToolResult(ok: true, stdout: "done"))
        ))
        XCTAssertEqual(reducer.state.first?.status, .done)
        XCTAssertNil(reducer.state.first?.progress)
    }

    func testHTMLRendererExposesDeterminateAndIndeterminateProgressAccessibly() {
        let determinate = ToolCardState(
            id: "determinate",
            title: ToolDefinition.mcpCall.name,
            subtitle: "Indexing",
            status: .running,
            progress: ToolProgressSurface(progress: .init(completed: 42, total: 100, message: "Indexing"))
        )
        let determinateHTML = WorkspaceHTMLToolCardRenderer.render(determinate)
        XCTAssertTrue(determinateHTML.contains(#"data-testid="tool-card-progress""#))
        XCTAssertTrue(determinateHTML.contains(#"role="progressbar""#))
        XCTAssertTrue(determinateHTML.contains(#"aria-label="Indexing""#))
        XCTAssertTrue(determinateHTML.contains(#"aria-valuenow="42""#))
        XCTAssertTrue(determinateHTML.contains(#"style="width: 42%""#))

        let indeterminate = ToolCardState(
            id: "indeterminate",
            title: ToolDefinition.mcpCall.name,
            subtitle: "Connecting",
            status: .running,
            progress: ToolProgressSurface(progress: .init(completed: 1, message: "Connecting"))
        )
        let indeterminateHTML = WorkspaceHTMLToolCardRenderer.render(indeterminate)
        XCTAssertTrue(indeterminateHTML.contains(#"class="tool-progress indeterminate""#))
        XCTAssertFalse(indeterminateHTML.contains("aria-valuenow"))
    }

    func testWorkspaceMCPStreamingOverridePreservesProgressAndFinalResult() async throws {
        let session = StreamingWorkspaceMCPSession(events: [
            .progress(.init(completed: 3, total: 10, message: "Reading")),
            .result(.init(content: [.object(["type": .string("text"), "text": .string("complete")])]))
        ])
        let executionOverride = try XCTUnwrap(WorkspaceMCPRuntime.streamingExecutionOverride(
            sessions: ["docs": session],
            summaries: ["docs": MCPServerProbeSummary(toolNames: ["index"])]
        ))
        let call = ToolCall(
            id: "mcp-call",
            name: ToolDefinition.mcpCall.name,
            argumentsJSON: #"{"serverID":"docs","toolName":"index","arguments":{"path":"README.md"}}"#
        )
        let stream = try XCTUnwrap(executionOverride(call, URL(fileURLWithPath: "/tmp")))
        var events: [AgentStreamingToolExecutionEvent] = []
        for try await event in stream { events.append(event) }

        XCTAssertEqual(events, [
            .progress(.init(completed: 3, total: 10, message: "Reading")),
            .result(ToolResult(ok: true, stdout: "complete"))
        ])
    }

    func testProgressIsRunningForStatusActivityAndCancellation() throws {
        let event = progressEvent(toolCallID: "tool-1", completed: 5, total: 10, message: "Writing")
        XCTAssertEqual(WorkspaceAgentStatusBuilder.status(for: event), TopBarAgentStatusLabel.running)

        let thread = ChatThread(events: [event])
        let activity = try XCTUnwrap(WorkspaceActivityEventSurfaceBuilder.recentSteps(for: thread).last)
        XCTAssertEqual(activity.title, "Tool progress")
        XCTAssertEqual(activity.statusLabel, ActivityStatusLabel.running)

        var cancelled = thread
        WorkspaceComposerCancellationPlanner.applyCancelledSend(userPrompt: "stop", to: &cancelled)
        XCTAssertEqual(cancelled.events.suffix(2).map(\.kind), [.toolFailed, .notice])
    }

    private func queuedEvent(_ call: ToolCall) throws -> ThreadEvent {
        ThreadEvent(
            kind: .toolQueued,
            summary: "\(call.name) queued",
            payloadJSON: try JSONHelpers.encodePretty(call)
        )
    }

    private func progressEvent(
        toolCallID: String,
        completed: Double,
        total: Double?,
        message: String
    ) -> ThreadEvent {
        ThreadEvent(
            kind: .toolProgress,
            summary: message,
            payloadJSON: try? JSONHelpers.encodePretty(ToolProgressEventPayload(
                toolCallID: toolCallID,
                progress: ToolExecutionProgress(completed: completed, total: total, message: message)
            ))
        )
    }
}

private struct StreamingWorkspaceMCPSession: WorkspaceMCPSession {
    var events: [MCPClientToolEvent]

    func callToolEvents(
        toolName: String,
        arguments: MCPJSONValue?,
        metadata: MCPJSONValue?,
        timeout: TimeInterval
    ) -> AsyncThrowingStream<MCPClientToolEvent, Error> {
        AsyncThrowingStream { continuation in
            events.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }

    func probe(timeout: TimeInterval) throws -> MCPServerProbeResult {
        throw MCPProbeError.responseError("Unused test method")
    }

    func callTool(toolName: String, argumentsJSON: String, timeout: TimeInterval) throws -> ToolResult {
        throw MCPProbeError.responseError("Unused test method")
    }

    func readResource(uri: String, timeout: TimeInterval) throws -> ToolResult {
        throw MCPProbeError.responseError("Unused test method")
    }

    func getPrompt(name: String, argumentsJSON: String, timeout: TimeInterval) throws -> ToolResult {
        throw MCPProbeError.responseError("Unused test method")
    }
}
