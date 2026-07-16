import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

struct AppServerProjectedNotification: Sendable {
    var method: String
    var params: CLIJSONValue
}

struct AppServerProgressProjector: Sendable {
    private let threadID: String
    private let turnID: String
    private let cwd: URL
    private var seenEventIDs: Set<UUID>
    private var assistantTextByID: [UUID: String]
    private var completedAssistantIDs: Set<UUID>
    private var activeTools: [ToolCall] = []
    private var mcpRoutes: [String: MCPAgentToolRoute] = [:]
    private(set) var items: [CLIJSONValue]

    init(
        threadID: UUID,
        turnID: String,
        cwd: URL,
        baseline: ChatThread,
        userItem: CLIJSONValue
    ) {
        self.threadID = AppServerThreadProjection.identifier(threadID)
        self.turnID = turnID
        self.cwd = cwd
        self.seenEventIDs = Set(baseline.events.map(\.id))
        self.assistantTextByID = Dictionary(uniqueKeysWithValues: baseline.messages.compactMap { message in
            message.role == .assistant ? (message.id, message.content) : nil
        })
        self.completedAssistantIDs = Set(baseline.messages.lazy.filter { $0.role == .assistant }.map(\.id))
        self.items = [userItem]
    }

    mutating func registerMCPRoutes(_ routes: [String: MCPAgentToolRoute]) {
        mcpRoutes.merge(routes) { _, replacement in replacement }
    }

    mutating func project(_ snapshot: ChatThread) -> [AppServerProjectedNotification] {
        var notifications: [AppServerProjectedNotification] = []
        for event in snapshot.events where seenEventIDs.insert(event.id).inserted {
            notifications.append(contentsOf: project(event))
        }
        for message in snapshot.messages where message.role == .assistant {
            notifications.append(contentsOf: project(message))
        }
        return notifications
    }

    mutating func addUserMessage(_ message: ChatMessage, clientID: String?) {
        let item = AppServerThreadProjection.userMessageItem(message, clientID: clientID)
        upsert(item, id: AppServerThreadProjection.identifier(message.id))
    }

    mutating func finish(_ snapshot: ChatThread, completedAt: Date) -> [AppServerProjectedNotification] {
        var notifications = project(snapshot)
        for message in snapshot.messages where message.role == .assistant {
            guard assistantTextByID[message.id] != nil,
                  completedAssistantIDs.insert(message.id).inserted else { continue }
            let item = AppServerThreadProjection.assistantMessageItem(message)
            upsert(item, id: AppServerThreadProjection.identifier(message.id))
            notifications.append(completed(item, at: completedAt))
        }
        while let call = activeTools.first {
            activeTools.removeFirst()
            let item = toolItem(call: call, result: nil, status: "failed")
            upsert(item, id: call.id)
            notifications.append(completed(item, at: completedAt))
        }
        return notifications
    }

    private mutating func project(_ message: ChatMessage) -> [AppServerProjectedNotification] {
        guard !completedAssistantIDs.contains(message.id) else { return [] }
        let id = AppServerThreadProjection.identifier(message.id)
        let previous = assistantTextByID[message.id]
        assistantTextByID[message.id] = message.content
        let current = AppServerThreadProjection.assistantMessageItem(message)
        upsert(current, id: id)

        if previous == nil {
            let empty = AppServerThreadProjection.assistantMessageItem(
                ChatMessage(id: message.id, role: .assistant, content: "", createdAt: message.createdAt)
            )
            var result = [started(empty, at: message.createdAt)]
            if !message.content.isEmpty {
                result.append(delta(method: "item/agentMessage/delta", itemID: id, text: message.content))
            }
            return result
        }
        guard previous != message.content else { return [] }
        let appended = message.content.hasPrefix(previous ?? "")
            ? String(message.content.dropFirst(previous?.count ?? 0))
            : message.content
        return appended.isEmpty ? [] : [
            delta(method: "item/agentMessage/delta", itemID: id, text: appended)
        ]
    }

    private mutating func project(_ event: ThreadEvent) -> [AppServerProjectedNotification] {
        switch event.kind {
        case .toolQueued:
            let call = decode(ToolCall.self, event.payloadJSON)
                ?? ToolCall(id: AppServerThreadProjection.identifier(event.id), name: toolName(event), argumentsJSON: "{}")
            activeTools.append(call)
            let item = toolItem(call: call, result: nil, status: "inProgress")
            upsert(item, id: call.id)
            return [started(item, at: event.createdAt)]
        case .toolCompleted, .toolFailed:
            let call = activeTools.isEmpty
                ? ToolCall(id: AppServerThreadProjection.identifier(event.id), name: toolName(event), argumentsJSON: "{}")
                : activeTools.removeFirst()
            let result = decode(ToolResult.self, event.payloadJSON)
            let status = event.kind == .toolCompleted ? "completed" : "failed"
            let item = toolItem(call: call, result: result, status: status)
            upsert(item, id: call.id)
            var notifications: [AppServerProjectedNotification] = []
            if isShell(call), let output = combinedOutput(result), !output.isEmpty {
                notifications.append(delta(
                    method: "item/commandExecution/outputDelta",
                    itemID: call.id,
                    text: output
                ))
            }
            notifications.append(completed(item, at: event.createdAt))
            return notifications
        case .notice:
            guard event.summary != AgentRunner.streamingNotice,
                  ModelTokenUsageEvent.usage(from: event) == nil,
                  event.summary.hasPrefix("Thinking:") else { return [] }
            let text = event.summary.dropFirst("Thinking:".count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return [] }
            let id = AppServerThreadProjection.identifier(event.id)
            let item: CLIJSONValue = .object([
                "type": .string("reasoning"),
                "id": .string(id),
                "summary": .array([.string(text)]),
                "content": .array([])
            ])
            upsert(item, id: id)
            return [started(item, at: event.createdAt), completed(item, at: event.createdAt)]
        case .toolRunning, .approvalRequested, .approvalDecided, .reviewComment, .message, .messageFeedback:
            return []
        }
    }

    private func toolItem(call: ToolCall, result: ToolResult?, status: String) -> CLIJSONValue {
        if let route = mcpRoutes[call.name] {
            return mcpToolItem(call: call, route: route, result: result, status: status)
        }
        if isShell(call) {
            return .object([
                "type": .string("commandExecution"),
                "id": .string(call.id),
                "command": .string(command(call) ?? call.name),
                "cwd": .string(cwd.path),
                "processId": .null,
                "source": .string("agent"),
                "status": .string(status),
                "commandActions": .array([]),
                "aggregatedOutput": combinedOutput(result).map(CLIJSONValue.string) ?? .null,
                "exitCode": result?.exitCode.map { .number(Double($0)) } ?? .null,
                "durationMs": .null
            ])
        }

        let output = combinedOutput(result)
        return .object([
            "type": .string("dynamicToolCall"),
            "id": .string(call.id),
            "namespace": .string("quillcode"),
            "tool": .string(call.name),
            "arguments": decodedJSON(call.argumentsJSON),
            "status": .string(status),
            "contentItems": output.map { .array([.object([
                "type": .string("inputText"),
                "text": .string($0)
            ])]) } ?? .null,
            "success": result.map { .bool($0.ok) } ?? .null,
            "durationMs": .null
        ])
    }

    private func mcpToolItem(
        call: ToolCall,
        route: MCPAgentToolRoute,
        result: ToolResult?,
        status: String
    ) -> CLIJSONValue {
        let output = combinedOutput(result)
        let projectedResult: CLIJSONValue
        let projectedError: CLIJSONValue
        if let result, result.ok {
            let content: [CLIJSONValue] = output.map { text in
                [.object(["type": .string("text"), "text": .string(text)])]
            } ?? []
            projectedResult = .object([
                "content": .array(content),
                "structuredContent": .null,
                "_meta": .null
            ])
            projectedError = .null
        } else if let result {
            projectedResult = .null
            projectedError = .object([
                "message": .string(output ?? result.error ?? "MCP tool failed.")
            ])
        } else {
            projectedResult = .null
            projectedError = .null
        }
        return .object([
            "type": .string("mcpToolCall"),
            "id": .string(call.id),
            "server": .string(route.serverName),
            "tool": .string(route.toolName),
            "status": .string(status),
            "arguments": decodedJSON(call.argumentsJSON),
            "appContext": .null,
            "pluginId": .null,
            "result": projectedResult,
            "error": projectedError
        ])
    }

    private func started(_ item: CLIJSONValue, at date: Date) -> AppServerProjectedNotification {
        lifecycle("item/started", item: item, timestampKey: "startedAtMs", date: date)
    }

    private func completed(_ item: CLIJSONValue, at date: Date) -> AppServerProjectedNotification {
        lifecycle("item/completed", item: item, timestampKey: "completedAtMs", date: date)
    }

    private func lifecycle(
        _ method: String,
        item: CLIJSONValue,
        timestampKey: String,
        date: Date
    ) -> AppServerProjectedNotification {
        AppServerProjectedNotification(method: method, params: .object([
            "threadId": .string(threadID),
            "turnId": .string(turnID),
            "item": item,
            timestampKey: .number((date.timeIntervalSince1970 * 1_000).rounded())
        ]))
    }

    private func delta(method: String, itemID: String, text: String) -> AppServerProjectedNotification {
        AppServerProjectedNotification(method: method, params: .object([
            "threadId": .string(threadID),
            "turnId": .string(turnID),
            "itemId": .string(itemID),
            "delta": .string(text)
        ]))
    }

    private mutating func upsert(_ item: CLIJSONValue, id: String) {
        if let index = items.firstIndex(where: { $0.objectValue?["id"]?.stringValue == id }) {
            items[index] = item
        } else {
            items.append(item)
        }
    }

    private func decodedJSON(_ text: String) -> CLIJSONValue {
        (try? CLIJSONCodec.decode(text)) ?? .string(text)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ text: String?) -> T? {
        guard let text else { return nil }
        return try? JSONDecoder().decode(type, from: Data(text.utf8))
    }

    private func isShell(_ call: ToolCall) -> Bool {
        call.name == ToolDefinition.shellRun.name
    }

    private func command(_ call: ToolCall) -> String? {
        guard let arguments = decodedJSON(call.argumentsJSON).objectValue else { return nil }
        return arguments["cmd"]?.stringValue ?? arguments["command"]?.stringValue
    }

    private func combinedOutput(_ result: ToolResult?) -> String? {
        guard let result else { return nil }
        let chunks = [result.stdout, result.stderr, result.error ?? ""].filter { !$0.isEmpty }
        return chunks.isEmpty ? nil : chunks.joined(separator: "\n")
    }

    private func toolName(_ event: ThreadEvent) -> String {
        event.summary.split(separator: " ").first.map(String.init) ?? "unknown"
    }
}
