import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeAgent

enum QueuedToolPosition {
    case first
    case last
}

let expectedDiskUsageCommand = "df -h / /Quill 2>/dev/null || df -h /"
let expectedOpenClawDiscoveryCommand = "command -v openclaw || which openclaw || echo 'not found'"

func expectedDownloadCommand(url: String, outputPath: String) -> String {
    [
        "mkdir -p 'downloads'",
        "curl -L --fail --silent --show-error --output '\(outputPath)' '\(url)'",
        "ls -lh '\(outputPath)'"
    ].joined(separator: " && ")
}

func preflightFailingAgentRunner() -> AgentRunner {
    AgentRunner(llm: FailingLLMClient(), enablesImmediateActionPreflight: true)
}

func fixedSayAgentRunner(_ message: String) -> AgentRunner {
    AgentRunner(llm: FixedSayLLMClient(message: message), enablesImmediateActionPreflight: true)
}

@discardableResult
func assertSingleSuccessfulToolResult(
    in result: AgentRunResult,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> ToolResult {
    XCTAssertEqual(result.toolResults.count, 1, file: file, line: line)
    let first = result.toolResults.first
    let toolResult = try XCTUnwrap(first, file: file, line: line)
    XCTAssertTrue(toolResult.ok, toolResult.error ?? "", file: file, line: line)
    return toolResult
}

func XCTAssertNoAssistantMessageContains(
    _ needle: String,
    in result: AgentRunResult,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertFalse(
        result.thread.messages.contains { $0.content.contains(needle) },
        "Unexpected assistant message containing \(needle)",
        file: file,
        line: line
    )
}

func queuedToolCall(
    in result: AgentRunResult,
    position: QueuedToolPosition = .first
) throws -> ToolCall {
    let queued: ThreadEvent?
    switch position {
    case .first:
        queued = result.thread.events.first { $0.kind == .toolQueued }
    case .last:
        queued = result.thread.events.last { $0.kind == .toolQueued }
    }

    let event = try XCTUnwrap(queued)
    let payloadJSON = try XCTUnwrap(event.payloadJSON)
    return try JSONDecoder().decode(ToolCall.self, from: Data(payloadJSON.utf8))
}

func queuedShellCommand(in result: AgentRunResult) throws -> String {
    let call = try queuedToolCall(in: result)
    let arguments = try ToolArguments(call.argumentsJSON)
    XCTAssertEqual(call.name, ToolDefinition.shellRun.name)
    return try arguments.requiredString("cmd")
}

func queuedFileWrite(in result: AgentRunResult) throws -> (path: String, content: String) {
    let call = try queuedToolCall(in: result)
    let arguments = try ToolArguments(call.argumentsJSON)
    XCTAssertEqual(call.name, ToolDefinition.fileWrite.name)
    return (
        try arguments.requiredString("path"),
        try arguments.requiredString("content")
    )
}

func queuedFileRead(in result: AgentRunResult) throws -> String {
    let call = try queuedToolCall(in: result, position: .last)
    let arguments = try ToolArguments(call.argumentsJSON)
    XCTAssertEqual(call.name, ToolDefinition.fileRead.name)
    return try arguments.requiredString("path")
}

func queuedFileList(in result: AgentRunResult) throws -> (path: String, includeHidden: Bool) {
    let call = try queuedToolCall(in: result, position: .last)
    let arguments = try ToolArguments(call.argumentsJSON)
    XCTAssertEqual(call.name, ToolDefinition.fileList.name)
    return (
        arguments.string("path") ?? ".",
        arguments.bool("includeHidden") ?? false
    )
}

func queuedFileSearch(in result: AgentRunResult) throws -> (query: String, path: String?) {
    let call = try queuedToolCall(in: result, position: .last)
    let arguments = try ToolArguments(call.argumentsJSON)
    XCTAssertEqual(call.name, ToolDefinition.fileSearch.name)
    return (
        try arguments.requiredString("query"),
        arguments.string("path")
    )
}

enum FailingLLMClientError: Error {
    case shouldNotBeCalled
}

struct FailingLLMClient: LLMClient {
    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        throw FailingLLMClientError.shouldNotBeCalled
    }
}

struct FixedSayLLMClient: LLMClient {
    var message: String

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        .say(message)
    }
}
