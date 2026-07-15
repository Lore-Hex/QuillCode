import Foundation
import QuillCodeAgent
import QuillCodeCore

actor CLIProgressReporter {
    private struct ActiveTool {
        var call: ToolCall
        var itemType: String
    }

    private let emitsJSONLines: Bool
    private let output: any CLIOutputWriting
    private var seenEventIDs: Set<UUID> = []
    private var assistantMessages: [UUID: String] = [:]
    private var completedAssistantMessages: Set<UUID> = []
    private var activeTools: [ActiveTool] = []
    private var usage = ModelTokenUsage()
    private var didBegin = false

    init(emitsJSONLines: Bool, output: any CLIOutputWriting) {
        self.emitsJSONLines = emitsJSONLines
        self.output = output
    }

    func begin(thread: ChatThread) async {
        guard !didBegin else { return }
        didBegin = true
        seenEventIDs = Set(thread.events.map(\.id))
        assistantMessages = Dictionary(uniqueKeysWithValues: thread.messages.compactMap { message in
            message.role == .assistant ? (message.id, message.content) : nil
        })
        completedAssistantMessages = Set(assistantMessages.keys)
        if emitsJSONLines {
            await emit([
                "type": .string("thread.started"),
                "thread_id": .string(thread.id.uuidString.lowercased())
            ])
            await emit(["type": .string("turn.started")])
        } else {
            await output.writeStandardErrorLine("Thread \(thread.id.uuidString.lowercased())")
        }
    }

    func report(_ thread: ChatThread) async {
        guard didBegin else { return }
        for event in thread.events where seenEventIDs.insert(event.id).inserted {
            await report(event)
        }
        for message in thread.messages where message.role == .assistant {
            let previous = assistantMessages[message.id]
            assistantMessages[message.id] = message.content
            guard emitsJSONLines, !completedAssistantMessages.contains(message.id) else { continue }
            if previous == nil {
                await emitItem(
                    lifecycle: "item.started",
                    id: message.id.uuidString.lowercased(),
                    type: "agent_message",
                    fields: ["text": .string(message.content)]
                )
            } else if previous != message.content {
                await emitItem(
                    lifecycle: "item.updated",
                    id: message.id.uuidString.lowercased(),
                    type: "agent_message",
                    fields: ["text": .string(message.content)]
                )
            }
        }
    }

    func finish(_ result: AgentRunResult) async {
        await report(result.thread)
        for message in result.thread.messages where message.role == .assistant {
            guard completedAssistantMessages.insert(message.id).inserted else { continue }
            if emitsJSONLines {
                await emitItem(
                    lifecycle: "item.completed",
                    id: message.id.uuidString.lowercased(),
                    type: "agent_message",
                    fields: ["text": .string(message.content)]
                )
            }
        }
        if emitsJSONLines {
            await emit([
                "type": .string("turn.completed"),
                "usage": .object([
                    "input_tokens": .number(Double(usage.promptTokens)),
                    "cached_input_tokens": .number(0),
                    "output_tokens": .number(Double(usage.completionTokens)),
                    "reasoning_output_tokens": .number(0)
                ]),
                "stop_reason": .string(stopReason(result.stopReason))
            ])
        } else if result.stopReason != .finished {
            await output.writeStandardErrorLine("Run stopped: \(stopReason(result.stopReason))")
        }
    }

    func fail(_ error: Error) async {
        let message = error.localizedDescription
        if emitsJSONLines {
            await emit([
                "type": .string("error"),
                "message": .string(message)
            ])
            await emit([
                "type": .string("turn.failed"),
                "error": .object(["message": .string(message)])
            ])
        } else {
            await output.writeStandardErrorLine("quill-code: \(message)")
        }
    }

    /// Codex JSONL exits nonzero without inventing a failed-turn event when an interrupted turn is
    /// acknowledged. Human output still makes the stop explicit on stderr.
    func interrupted() async {
        guard !emitsJSONLines else { return }
        await output.writeStandardErrorLine("Run interrupted.")
    }

    private func report(_ event: ThreadEvent) async {
        if let eventUsage = ModelTokenUsageEvent.usage(from: event) {
            usage.promptTokens += eventUsage.promptTokens
            usage.completionTokens += eventUsage.completionTokens
            usage.totalTokens += eventUsage.totalTokens
            return
        }
        switch event.kind {
        case .toolQueued:
            let call = decode(ToolCall.self, event.payloadJSON)
                ?? ToolCall(id: event.id.uuidString, name: toolName(from: event.summary), argumentsJSON: "{}")
            let type = itemType(for: call.name)
            activeTools.append(ActiveTool(call: call, itemType: type))
            if emitsJSONLines {
                var fields: [String: CLIJSONValue] = [
                    "name": .string(call.name),
                    "status": .string("in_progress"),
                    "arguments": decodedJSON(call.argumentsJSON)
                ]
                if type == "command_execution", let command = command(from: call) {
                    fields["command"] = .string(command)
                }
                await emitItem(lifecycle: "item.started", id: call.id, type: type, fields: fields)
            } else {
                await output.writeStandardErrorLine("→ \(call.name)")
            }
        case .toolRunning:
            guard let active = activeTools.first else { return }
            if emitsJSONLines {
                await emitItem(
                    lifecycle: "item.updated",
                    id: active.call.id,
                    type: active.itemType,
                    fields: ["name": .string(active.call.name), "status": .string("in_progress")]
                )
            }
        case .toolCompleted, .toolFailed:
            let active = activeTools.isEmpty
                ? ActiveTool(
                    call: ToolCall(id: event.id.uuidString, name: toolName(from: event.summary), argumentsJSON: "{}"),
                    itemType: "tool_call"
                )
                : activeTools.removeFirst()
            let result = decode(ToolResult.self, event.payloadJSON)
            if emitsJSONLines {
                var fields: [String: CLIJSONValue] = [
                    "name": .string(active.call.name),
                    "status": .string(event.kind == .toolCompleted ? "completed" : "failed")
                ]
                if let result { fields["output"] = codableJSON(result) }
                await emitItem(
                    lifecycle: "item.completed",
                    id: active.call.id,
                    type: active.itemType,
                    fields: fields
                )
            } else {
                let mark = event.kind == .toolCompleted ? "✓" : "✗"
                await output.writeStandardErrorLine("\(mark) \(active.call.name)")
                if event.kind == .toolFailed, let detail = result?.displayedFailureDetail {
                    await output.writeStandardErrorLine("  \(detail)")
                }
            }
        case .approvalRequested:
            await emitEventItem(event, type: "approval_request", status: "pending")
        case .approvalDecided:
            await emitEventItem(event, type: "approval_decision", status: "completed")
        case .reviewComment:
            await emitEventItem(event, type: "review_comment", status: "completed")
        case .notice:
            if event.summary == AgentRunner.streamingNotice { return }
            let type = event.summary.hasPrefix("Thinking:") ? "reasoning" : "notice"
            await emitEventItem(event, type: type, status: "completed")
        case .message, .messageFeedback:
            break
        }
    }

    private func emitEventItem(_ event: ThreadEvent, type: String, status: String) async {
        if emitsJSONLines {
            var fields: [String: CLIJSONValue] = [
                "text": .string(event.summary),
                "status": .string(status)
            ]
            if let payload = event.payloadJSON { fields["payload"] = decodedJSON(payload) }
            await emitItem(
                lifecycle: "item.completed",
                id: event.id.uuidString.lowercased(),
                type: type,
                fields: fields
            )
        } else if type == "reasoning" || type == "notice" || type == "approval_request" {
            await output.writeStandardErrorLine("• \(event.summary)")
        }
    }

    private func emitItem(
        lifecycle: String,
        id: String,
        type: String,
        fields: [String: CLIJSONValue]
    ) async {
        var item = fields
        item["id"] = .string(id)
        item["type"] = .string(type)
        await emit(["type": .string(lifecycle), "item": .object(item)])
    }

    private func emit(_ object: [String: CLIJSONValue]) async {
        guard let line = try? CLIJSONCodec.line(object) else { return }
        await output.writeStandardOutput(line)
    }

    private func decodedJSON(_ text: String) -> CLIJSONValue {
        (try? CLIJSONCodec.decode(text)) ?? .string(text)
    }

    private func codableJSON<T: Encodable>(_ value: T) -> CLIJSONValue {
        guard let data = try? JSONEncoder().encode(value),
              let json = try? CLIJSONCodec.decode(data)
        else { return .null }
        return json
    }

    private func decode<T: Decodable>(_ type: T.Type, _ payload: String?) -> T? {
        guard let payload else { return nil }
        return try? JSONDecoder().decode(type, from: Data(payload.utf8))
    }

    private func command(from call: ToolCall) -> String? {
        guard case .object(let arguments) = decodedJSON(call.argumentsJSON) else { return nil }
        return arguments["cmd"]?.stringValue ?? arguments["command"]?.stringValue
    }

    private func toolName(from summary: String) -> String {
        summary.split(separator: " ").first.map(String.init) ?? "unknown"
    }

    private func itemType(for toolName: String) -> String {
        switch toolName {
        case ToolDefinition.shellRun.name:
            "command_execution"
        case ToolDefinition.fileWrite.name, ToolDefinition.applyPatch.name:
            "file_change"
        case ToolDefinition.webSearch.name:
            "web_search"
        default:
            toolName.hasPrefix("host.mcp.") ? "mcp_tool_call" : "tool_call"
        }
    }

    private func stopReason(_ reason: AgentRunStopReason) -> String {
        switch reason {
        case .finished:
            "finished"
        case .toolStepCeilingExhausted:
            "tool_step_ceiling_exhausted"
        case .flailDetected:
            "flail_detected"
        case .spendFuseApprovalRequired:
            "spend_approval_required"
        case .approvalRequired:
            "approval_required"
        }
    }
}

private extension ToolResult {
    var displayedFailureDetail: String? {
        for candidate in [error].compactMap({ $0 }) + [stderr, stdout] {
            let detail = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !detail.isEmpty { return detail }
        }
        return nil
    }
}
