import Foundation
import QuillCodeAgent
import QuillCodeCore

struct MCPServerPendingApproval {
    var originatingRequestID: MCPServerRequestID
    var continuation: CheckedContinuation<AgentPermissionRequestDecision, Never>
}

extension MCPServerSession {
    func requestApproval(
        for call: ToolCall,
        reason: String,
        thread: ChatThread,
        workspaceRoot: URL,
        originatingRequestID: MCPServerRequestID
    ) async -> AgentPermissionRequestHookOutcome {
        guard !inputFinished else {
            return AgentPermissionRequestHookOutcome(decision: .deny(
                reason: "The MCP client disconnected before answering the approval request."
            ))
        }
        guard activeCalls[originatingRequestID] != nil else {
            return AgentPermissionRequestHookOutcome(decision: .deny(
                reason: "The originating MCP request is no longer active."
            ))
        }

        let requestID = MCPServerRequestID.integer(nextServerRequestSequence)
        nextServerRequestSequence += 1
        let decision = await withTaskCancellationHandler {
            await withCheckedContinuation {
                (continuation: CheckedContinuation<AgentPermissionRequestDecision, Never>) in
                guard !Task.isCancelled else {
                    continuation.resume(returning: .deny(reason: "The approval request was cancelled."))
                    return
                }
                pendingApprovals[requestID] = MCPServerPendingApproval(
                    originatingRequestID: originatingRequestID,
                    continuation: continuation
                )
                Task { [weak self] in
                    await self?.dispatchApprovalRequest(
                        id: requestID,
                        call: call,
                        reason: reason,
                        thread: thread,
                        workspaceRoot: workspaceRoot,
                        originatingRequestID: originatingRequestID
                    )
                }
            }
        } onCancel: {
            Task { [weak self] in await self?.cancelPendingApproval(requestID) }
        }
        return AgentPermissionRequestHookOutcome(decision: decision)
    }

    func resolveApprovalResponse(
        id: MCPServerRequestID,
        result: CLIJSONValue?,
        error: MCPServerRPCError?
    ) {
        guard let pending = pendingApprovals.removeValue(forKey: id) else { return }
        pending.continuation.resume(returning: approvalDecision(result: result, error: error))
    }

    func resolveAllPendingApprovals(with decision: AgentPermissionRequestDecision) {
        let pending = Array(pendingApprovals.values)
        pendingApprovals.removeAll()
        pending.forEach { $0.continuation.resume(returning: decision) }
    }

    func resolvePendingApprovals(
        for requestID: MCPServerRequestID,
        decision: AgentPermissionRequestDecision
    ) {
        let ids = pendingApprovals.compactMap { id, pending in
            pending.originatingRequestID == requestID ? id : nil
        }
        for id in ids {
            pendingApprovals.removeValue(forKey: id)?.continuation.resume(returning: decision)
        }
    }

    private func dispatchApprovalRequest(
        id: MCPServerRequestID,
        call: ToolCall,
        reason: String,
        thread: ChatThread,
        workspaceRoot: URL,
        originatingRequestID: MCPServerRequestID
    ) async {
        guard pendingApprovals[id] != nil else { return }
        let redacted = call.redactedForTranscript()
        let isPatch = isFileChange(redacted)
        var params: [String: CLIJSONValue] = [
            "message": .string(approvalMessage(
                call: redacted,
                reason: reason,
                workspaceRoot: workspaceRoot,
                isPatch: isPatch
            )),
            "requestedSchema": .object([
                "type": .string("object"),
                "properties": .object([:])
            ]),
            "threadId": .string(thread.id.uuidString.lowercased()),
            "codex_elicitation": .string(isPatch ? "patch-approval" : "exec-approval"),
            "codex_mcp_tool_call_id": originatingRequestID.displayValue,
            "codex_event_id": .string(redacted.id),
            "codex_call_id": .string(redacted.id)
        ]
        if isPatch {
            params["codex_reason"] = reason.isEmpty ? .null : .string(reason)
            params["codex_changes"] = .object([
                "tool": .string(redacted.name),
                "arguments": decodedArguments(redacted.argumentsJSON)
            ])
        } else {
            let command = shellCommand(redacted) ?? "\(redacted.name) \(redacted.argumentsJSON)"
            params["codex_command"] = .array([.string(String(command.prefix(8_192)))])
            params["codex_cwd"] = .string(workspaceRoot.path)
            params["codex_parsed_cmd"] = .array([])
        }
        await send(.request(id: id, method: "elicitation/create", params: .object(params)))
    }

    private func cancelPendingApproval(_ id: MCPServerRequestID) {
        pendingApprovals.removeValue(forKey: id)?.continuation.resume(
            returning: .deny(reason: "The approval request was cancelled.")
        )
    }

    private func approvalDecision(
        result: CLIJSONValue?,
        error: MCPServerRPCError?
    ) -> AgentPermissionRequestDecision {
        if let error { return .deny(reason: "Approval request failed: \(error.message)") }
        let object = result?.objectValue
        let action = object?["decision"]?.stringValue
            ?? object?["action"]?.stringValue
            ?? object?["content"]?.objectValue?["decision"]?.stringValue
        switch action?.lowercased() {
        case "approved", "approved_for_session", "allow", "accept", "acceptforsession":
            return .allow
        case "denied", "deny", "decline", "cancel", "abort":
            return .deny(reason: "The user declined this action.")
        default:
            return .deny(reason: "The MCP client returned an invalid approval response.")
        }
    }

    private func approvalMessage(
        call: ToolCall,
        reason: String,
        workspaceRoot: URL,
        isPatch: Bool
    ) -> String {
        if isPatch {
            return [reason, "Allow QuillCode to apply the proposed code changes?"]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }
        let command = shellCommand(call) ?? call.name
        return "Allow QuillCode to run `\(command)` in `\(workspaceRoot.path)`?"
    }

    private func shellCommand(_ call: ToolCall) -> String? {
        let object = decodedArguments(call.argumentsJSON).objectValue
        return object?["cmd"]?.stringValue ?? object?["command"]?.stringValue
    }

    private func decodedArguments(_ text: String) -> CLIJSONValue {
        (try? CLIJSONCodec.decode(text)) ?? .string(String(text.prefix(8_192)))
    }

    private func isFileChange(_ call: ToolCall) -> Bool {
        if ["host.file.write", "host.apply_patch"].contains(call.name) { return true }
        return call.name.hasPrefix("host.git.") && ![
            "host.git.status", "host.git.diff", "host.git.log", "host.git.branch.list"
        ].contains(call.name)
    }
}

private extension MCPServerRequestID {
    var displayValue: CLIJSONValue {
        switch self {
        case .string(let value): .string(value)
        case .integer(let value): .string(String(value))
        }
    }
}
