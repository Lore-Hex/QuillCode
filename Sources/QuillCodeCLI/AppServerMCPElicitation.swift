import Foundation
import QuillCodeTools

struct AppServerPendingMCPElicitation {
    var threadID: String
    var turnID: String?
    var continuation: CheckedContinuation<MCPClientElicitationResponse, Never>
}

extension AppServerSession {
    func requestTurnMCPElicitation(
        serverName: String,
        request: MCPClientElicitationRequest,
        threadID: UUID
    ) async -> MCPClientElicitationResponse {
        await requestMCPElicitation(
            serverName: serverName,
            request: request,
            threadID: threadID,
            turnID: activeTurns[threadID]?.id
        )
    }

    func requestMCPElicitation(
        serverName: String,
        request: MCPClientElicitationRequest,
        threadID: UUID,
        turnID: String?
    ) async -> MCPClientElicitationResponse {
        guard !inputFinished else { return .cancel() }
        if case .openAIForm = request, !mcpServerOpenAIFormElicitationEnabled {
            return .cancel()
        }

        let id = AppServerRequestID.string("quillcode-mcp-elicitation-\(nextServerRequestSequence)")
        nextServerRequestSequence += 1
        let projectedThreadID = AppServerThreadProjection.identifier(threadID)
        let params = Self.mcpElicitationParams(
            request,
            threadID: projectedThreadID,
            turnID: turnID,
            serverName: serverName
        )

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: .cancel())
                    return
                }
                pendingMCPElicitations[id] = AppServerPendingMCPElicitation(
                    threadID: projectedThreadID,
                    turnID: turnID,
                    continuation: continuation
                )
                Task { [weak self] in
                    await self?.dispatchMCPElicitationRequest(id: id, params: params)
                }
            }
        } onCancel: {
            Task { [weak self] in
                await self?.cancelPendingMCPElicitation(id)
            }
        }
    }

    @discardableResult
    func resolveMCPElicitationResponse(
        id: AppServerRequestID,
        result: CLIJSONValue?,
        error: AppServerRPCError?
    ) async -> Bool {
        guard let pending = pendingMCPElicitations.removeValue(forKey: id) else { return false }
        let response = Self.mcpElicitationResponse(result: result, error: error)
        await notifyMCPElicitationResolved(id: id, threadID: pending.threadID)
        pending.continuation.resume(returning: response)
        return true
    }

    func cancelPendingMCPElicitations(threadID: UUID, turnID: String) async {
        let projected = AppServerThreadProjection.identifier(threadID)
        let ids = pendingMCPElicitations.compactMap { id, pending in
            pending.threadID == projected && pending.turnID == turnID ? id : nil
        }
        for id in ids { await cancelPendingMCPElicitation(id) }
    }

    func resolveAllPendingMCPElicitations() async {
        for id in Array(pendingMCPElicitations.keys) {
            await cancelPendingMCPElicitation(id)
        }
    }

    private func dispatchMCPElicitationRequest(
        id: AppServerRequestID,
        params: CLIJSONValue
    ) async {
        guard pendingMCPElicitations[id] != nil else { return }
        await send(.request(id: id, method: "mcpServer/elicitation/request", params: params))
    }

    private func cancelPendingMCPElicitation(_ id: AppServerRequestID) async {
        guard let pending = pendingMCPElicitations.removeValue(forKey: id) else { return }
        await notifyMCPElicitationResolved(id: id, threadID: pending.threadID)
        pending.continuation.resume(returning: .cancel())
    }

    private func notifyMCPElicitationResolved(id: AppServerRequestID, threadID: String) async {
        await sendNotification("serverRequest/resolved", params: .object([
            "threadId": .string(threadID),
            "requestId": id.cliJSONValue
        ]))
    }

    private static func mcpElicitationParams(
        _ request: MCPClientElicitationRequest,
        threadID: String,
        turnID: String?,
        serverName: String
    ) -> CLIJSONValue {
        var params: [String: CLIJSONValue] = [
            "threadId": .string(threadID),
            "turnId": turnID.map(CLIJSONValue.string) ?? .null,
            "serverName": .string(serverName)
        ]
        switch request {
        case .form(let message, let requestedSchema, let metadata):
            params["mode"] = .string("form")
            params["message"] = .string(message)
            params["requestedSchema"] = requestedSchema.cliJSONValue
            if let metadata { params["_meta"] = metadata.cliJSONValue }
        case .openAIForm(let message, let requestedSchema, let metadata):
            params["mode"] = .string("openai/form")
            params["message"] = .string(message)
            params["requestedSchema"] = requestedSchema.cliJSONValue
            if let metadata { params["_meta"] = metadata.cliJSONValue }
        case .url(let message, let url, let elicitationID, let metadata):
            params["mode"] = .string("url")
            params["message"] = .string(message)
            params["url"] = .string(url)
            params["elicitationId"] = .string(elicitationID)
            if let metadata { params["_meta"] = metadata.cliJSONValue }
        }
        return .object(params)
    }

    private static func mcpElicitationResponse(
        result: CLIJSONValue?,
        error: AppServerRPCError?
    ) -> MCPClientElicitationResponse {
        guard error == nil,
              let object = result?.objectValue,
              let rawAction = object["action"]?.stringValue,
              let action = MCPClientElicitationAction(rawValue: rawAction)
        else {
            return .decline()
        }
        do {
            let content = try object["content"].map { try $0.mcpJSONValue }
            let metadata = try object["_meta"].map { try $0.mcpJSONValue }
            return MCPClientElicitationResponse(
                action: action,
                content: content,
                metadata: metadata
            )
        } catch {
            return .decline()
        }
    }
}

private extension AppServerRequestID {
    var cliJSONValue: CLIJSONValue {
        switch self {
        case .string(let value): .string(value)
        case .integer(let value): .number(Double(value))
        }
    }
}
