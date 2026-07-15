import Foundation
import QuillCodeAgent
import QuillCodeCore

enum AppServerApprovalKind: Sendable {
    case command
    case fileChange
}

struct AppServerPendingApproval {
    var kind: AppServerApprovalKind
    var continuation: CheckedContinuation<AgentPermissionRequestDecision, Never>
}

private struct AppServerApprovalRequest {
    var kind: AppServerApprovalKind
    var method: String
    var params: CLIJSONValue
}

extension AppServerSession {
    func requestApproval(
        for call: ToolCall,
        reason: String,
        thread: ChatThread,
        workspaceRoot: URL
    ) async -> AgentPermissionRequestHookOutcome {
        guard !inputFinished else {
            return AgentPermissionRequestHookOutcome(decision: .deny(
                reason: "The app-server client disconnected before answering the approval request."
            ))
        }
        guard let active = activeTurns[thread.id] else {
            return AgentPermissionRequestHookOutcome()
        }
        let request = approvalRequest(
            for: call,
            reason: reason,
            threadID: thread.id,
            turnID: active.id,
            workspaceRoot: workspaceRoot
        )

        let id = AppServerRequestID.string("quillcode-approval-\(nextServerRequestSequence)")
        nextServerRequestSequence += 1
        let decision = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: AgentPermissionRequestDecision.deny(
                        reason: "The approval request was cancelled."
                    ))
                    return
                }
                pendingApprovals[id] = AppServerPendingApproval(
                    kind: request.kind,
                    continuation: continuation
                )
                Task { [weak self] in
                    await self?.dispatchApprovalRequest(id: id, request: request)
                }
            }
        } onCancel: {
            Task { [weak self] in
                await self?.cancelPendingApproval(id)
            }
        }
        return AgentPermissionRequestHookOutcome(decision: decision)
    }

    func resolveApprovalResponse(
        id: AppServerRequestID,
        result: CLIJSONValue?,
        error: AppServerRPCError?
    ) {
        guard let pending = pendingApprovals.removeValue(forKey: id) else { return }
        pending.continuation.resume(returning: approvalDecision(
            kind: pending.kind,
            result: result,
            error: error
        ))
    }

    func resolveAllPendingApprovals(with decision: AgentPermissionRequestDecision) {
        let pending = Array(pendingApprovals.values)
        pendingApprovals.removeAll()
        for request in pending {
            request.continuation.resume(returning: decision)
        }
    }

    private func dispatchApprovalRequest(
        id: AppServerRequestID,
        request: AppServerApprovalRequest
    ) async {
        guard pendingApprovals[id] != nil else { return }
        await send(.request(id: id, method: request.method, params: request.params))
    }

    private func cancelPendingApproval(_ id: AppServerRequestID) {
        guard let pending = pendingApprovals.removeValue(forKey: id) else { return }
        pending.continuation.resume(returning: .deny(reason: "The approval request was cancelled."))
    }

    private func approvalRequest(
        for call: ToolCall,
        reason: String,
        threadID: UUID,
        turnID: String,
        workspaceRoot: URL
    ) -> AppServerApprovalRequest {
        let common: [String: CLIJSONValue] = [
            "threadId": .string(AppServerThreadProjection.identifier(threadID)),
            "turnId": .string(turnID),
            "itemId": .string(call.id),
            "startedAtMs": .number((Date().timeIntervalSince1970 * 1_000).rounded()),
            "reason": reason.isEmpty ? .null : .string(reason)
        ]
        if !isFileChange(call) {
            var params = common
            params["approvalId"] = .null
            params["environmentId"] = .null
            params["networkApprovalContext"] = .null
            params["command"] = .string(displayCommand(for: call))
            params["cwd"] = .string(workspaceRoot.path)
            params["commandActions"] = .null
            params["proposedExecpolicyAmendment"] = .null
            params["proposedNetworkPolicyAmendments"] = .null
            return AppServerApprovalRequest(
                kind: .command,
                method: "item/commandExecution/requestApproval",
                params: .object(params)
            )
        }
        var params = common
        params["grantRoot"] = .null
        return AppServerApprovalRequest(
            kind: .fileChange,
            method: "item/fileChange/requestApproval",
            params: .object(params)
        )
    }

    private func approvalDecision(
        kind: AppServerApprovalKind,
        result: CLIJSONValue?,
        error: AppServerRPCError?
    ) -> AgentPermissionRequestDecision {
        if let error {
            return .deny(reason: "Approval request failed: \(error.message)")
        }
        guard let decision = result?.objectValue?["decision"] else {
            return .deny(reason: "The app-server client returned an invalid approval response.")
        }
        if let value = decision.stringValue {
            switch value {
            case "accept", "acceptForSession": return .allow
            case "decline": return .deny(reason: "The user declined this action.")
            case "cancel": return .deny(reason: "The user cancelled this action.")
            default: return .deny(reason: "The app-server client returned an unknown approval decision.")
            }
        }
        if kind == .command,
           let value = decision.objectValue,
           value["acceptWithExecpolicyAmendment"] != nil || value["applyNetworkPolicyAmendment"] != nil {
            return .allow
        }
        return .deny(reason: "The app-server client returned an invalid approval decision.")
    }

    private func shellCommand(from call: ToolCall) -> String? {
        guard let arguments = try? CLIJSONCodec.decode(call.argumentsJSON).objectValue else { return nil }
        return arguments["cmd"]?.stringValue ?? arguments["command"]?.stringValue
    }

    private func displayCommand(for call: ToolCall) -> String {
        if let command = shellCommand(from: call) { return command }
        let redacted = call.redactedForTranscript()
        return String("\(redacted.name) \(redacted.argumentsJSON)".prefix(4_000))
    }

    private func isFileChange(_ call: ToolCall) -> Bool {
        if ["host.file.write", "host.apply_patch"].contains(call.name) { return true }
        return [
            "host.git.branch.switch",
            "host.git.stage",
            "host.git.restore",
            "host.git.stage_hunk",
            "host.git.unstage_hunk",
            "host.git.restore_hunk",
            "host.git.worktree.handoff",
            "host.git.worktree.create_branch",
            "host.git.worktree.remove",
            "host.git.worktree.prune"
        ].contains(call.name)
    }
}
