import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

struct MCPServerProjectedEvent: Sendable {
    var id: String
    var message: CLIJSONValue
}

struct MCPServerProgressProjector: Sendable {
    private let cwd: URL
    private var seenMessageIDs: Set<UUID>
    private var seenEventIDs: Set<UUID>
    private var assistantTextByID: [UUID: String]
    private var pendingTool: ToolCall?

    init(cwd: URL, baseline: ChatThread) {
        self.cwd = cwd
        self.seenMessageIDs = Set(baseline.messages.map(\.id))
        self.seenEventIDs = Set(baseline.events.map(\.id))
        self.assistantTextByID = Dictionary(uniqueKeysWithValues: baseline.messages.compactMap { message in
            message.role == .assistant ? (message.id, message.content) : nil
        })
    }

    mutating func project(_ snapshot: ChatThread) -> [MCPServerProjectedEvent] {
        var projected: [MCPServerProjectedEvent] = []
        for message in snapshot.messages {
            projected.append(contentsOf: project(message))
        }
        for event in snapshot.events where seenEventIDs.insert(event.id).inserted {
            projected.append(contentsOf: project(event))
        }
        return projected
    }

    private mutating func project(_ message: ChatMessage) -> [MCPServerProjectedEvent] {
        switch message.role {
        case .user:
            guard seenMessageIDs.insert(message.id).inserted else { return [] }
            return [MCPServerProjectedEvent(
                id: message.id.uuidString.lowercased(),
                message: .object([
                    "type": .string("user_message"),
                    "message": .string(Self.bounded(message.content))
                ])
            )]
        case .assistant:
            let previous = assistantTextByID[message.id] ?? ""
            assistantTextByID[message.id] = message.content
            seenMessageIDs.insert(message.id)
            guard previous != message.content else { return [] }
            let delta = message.content.hasPrefix(previous)
                ? String(message.content.dropFirst(previous.count))
                : message.content
            guard !delta.isEmpty else { return [] }
            return [MCPServerProjectedEvent(
                id: message.id.uuidString.lowercased(),
                message: .object([
                    "type": .string("agent_message_content_delta"),
                    "delta": .string(Self.bounded(delta))
                ])
            )]
        case .system, .tool:
            seenMessageIDs.insert(message.id)
            return []
        }
    }

    private mutating func project(_ event: ThreadEvent) -> [MCPServerProjectedEvent] {
        let id = event.id.uuidString.lowercased()
        switch event.kind {
        case .toolQueued:
            let call = decode(ToolCall.self, event.payloadJSON)
                ?? ToolCall(id: id, name: event.summary, argumentsJSON: "{}")
            let redacted = call.redactedForTranscript()
            // AgentRunner executes one tool step at a time. Mirroring that invariant avoids an
            // unnecessary FIFO and keeps malformed histories from pairing a stale call to a result.
            pendingTool = redacted
            if redacted.name == ToolDefinition.shellRun.name {
                return [MCPServerProjectedEvent(id: id, message: .object([
                    "type": .string("exec_command_begin"),
                    "call_id": .string(redacted.id),
                    "command": .array([.string(Self.bounded(
                        shellCommand(redacted) ?? redacted.name
                    ))]),
                    "cwd": .string(cwd.path)
                ]))]
            }
            return [MCPServerProjectedEvent(id: id, message: .object([
                "type": .string("item_started"),
                "call_id": .string(redacted.id),
                "tool": .string(redacted.name),
                "arguments": decodedJSON(redacted.argumentsJSON)
            ]))]

        case .toolCompleted, .toolFailed:
            let call = pendingTool
                ?? ToolCall(id: id, name: event.summary, argumentsJSON: "{}")
            pendingTool = nil
            let result = decode(ToolResult.self, event.payloadJSON)
            let output = Self.bounded(combinedOutput(result))
            if call.name == ToolDefinition.shellRun.name {
                return [MCPServerProjectedEvent(id: id, message: .object([
                    "type": .string("exec_command_end"),
                    "call_id": .string(call.id),
                    "stdout": .string(output),
                    "stderr": .string(Self.bounded(result?.stderr ?? "")),
                    "exit_code": result?.exitCode.map { .number(Double($0)) } ?? .null
                ]))]
            }
            return [MCPServerProjectedEvent(id: id, message: .object([
                "type": .string("item_completed"),
                "call_id": .string(call.id),
                "tool": .string(call.name),
                "success": .bool(result?.ok ?? (event.kind == .toolCompleted)),
                "output": .string(output)
            ]))]

        case .notice:
            guard event.summary != AgentRunner.streamingNotice else { return [] }
            let type = event.summary.hasPrefix("Thinking:") ? "agent_reasoning" : "warning"
            return [MCPServerProjectedEvent(id: id, message: .object([
                "type": .string(type),
                "message": .string(Self.bounded(event.summary))
            ]))]

        case .approvalRequested:
            return [MCPServerProjectedEvent(id: id, message: .object([
                "type": .string("approval_requested"),
                "message": .string(Self.bounded(event.summary))
            ]))]
        case .approvalDecided:
            return [MCPServerProjectedEvent(id: id, message: .object([
                "type": .string("approval_decided"),
                "message": .string(Self.bounded(event.summary))
            ]))]
        case .toolRunning, .toolProgress, .reviewComment, .message, .messageFeedback:
            return []
        }
    }

    private func shellCommand(_ call: ToolCall) -> String? {
        let arguments = decodedJSON(call.argumentsJSON).objectValue
        return arguments?["cmd"]?.stringValue ?? arguments?["command"]?.stringValue
    }

    private func combinedOutput(_ result: ToolResult?) -> String {
        guard let result else { return "" }
        return [result.stdout, result.stderr, result.error ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func decodedJSON(_ text: String) -> CLIJSONValue {
        (try? CLIJSONCodec.decode(text)) ?? .string(Self.bounded(text))
    }

    private func decode<T: Decodable>(_ type: T.Type, _ text: String?) -> T? {
        guard let text else { return nil }
        return try? JSONDecoder().decode(type, from: Data(text.utf8))
    }

    private static func bounded(_ text: String, limit: Int = 32 * 1_024) -> String {
        guard text.utf8.count > limit else { return text }
        var prefix = ""
        prefix.reserveCapacity(limit)
        var byteCount = 0
        for character in text {
            let width = String(character).utf8.count
            guard byteCount + width <= limit else { break }
            prefix.append(character)
            byteCount += width
        }
        return prefix + "\n[output truncated]"
    }
}
