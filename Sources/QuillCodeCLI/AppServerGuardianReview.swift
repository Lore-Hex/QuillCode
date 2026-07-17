import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

enum AppServerGuardianAssessmentStatus: String, Sendable {
    case inProgress
    case approved
    case denied
    case timedOut
    case aborted

    init(wireValue: String) throws {
        switch wireValue {
        case "in_progress", "inProgress": self = .inProgress
        case "approved": self = .approved
        case "denied": self = .denied
        case "timed_out", "timedOut": self = .timedOut
        case "aborted": self = .aborted
        default:
            throw AppServerRPCError.invalidParams("event.status is not a Guardian assessment status")
        }
    }
}

struct AppServerGuardianAssessmentEvent: Sendable {
    var id: String
    var targetItemID: String?
    var turnID: String
    var status: AppServerGuardianAssessmentStatus
    var action: AppServerGuardianReviewAction

    init(_ value: CLIJSONValue) throws {
        let params = try AppServerParams(value)
        id = try params.requiredString("id")
        targetItemID = try Self.optionalString(in: params, snake: "target_item_id", camel: "targetItemId")
        turnID = try Self.requiredString(in: params, snake: "turn_id", camel: "turnId")
        status = try AppServerGuardianAssessmentStatus(wireValue: params.requiredString("status"))
        guard let action = try params.optionalObject("action") else {
            throw AppServerRPCError.invalidParams("event.action is required")
        }
        self.action = try AppServerGuardianReviewAction(.object(action))
    }

    private static func optionalString(
        in params: AppServerParams,
        snake: String,
        camel: String
    ) throws -> String? {
        if params.object[snake] != nil { return try params.optionalString(snake) }
        return try params.optionalString(camel)
    }

    private static func requiredString(
        in params: AppServerParams,
        snake: String,
        camel: String
    ) throws -> String {
        if params.object[snake] != nil { return try params.requiredString(snake) }
        return try params.requiredString(camel)
    }
}

enum AppServerGuardianReviewAction: Sendable, Equatable {
    case command(source: String, command: String, cwd: String)
    case applyPatch(cwd: String, files: [String])
    case mcpToolCall(server: String, toolName: String)
    case unsupported(type: String)

    init(_ value: CLIJSONValue) throws {
        let params = try AppServerParams(value)
        let type = try params.requiredString("type")
        switch type {
        case "command":
            self = .command(
                source: try params.requiredString("source"),
                command: try params.requiredString("command", allowingEmpty: true),
                cwd: try params.requiredString("cwd")
            )
        case "apply_patch", "applyPatch":
            let files = try params.optionalArray("files") ?? []
            self = .applyPatch(
                cwd: try params.requiredString("cwd"),
                files: try files.map { value in
                    guard let path = value.stringValue, !path.isEmpty else {
                        throw AppServerRPCError.invalidParams("event.action.files must contain paths")
                    }
                    return path
                }
            )
        case "mcp_tool_call", "mcpToolCall":
            let toolName = if params.object["tool_name"] != nil {
                try params.requiredString("tool_name")
            } else {
                try params.requiredString("toolName")
            }
            self = .mcpToolCall(
                server: try params.requiredString("server"),
                toolName: toolName
            )
        case "execve", "network_access", "networkAccess", "request_permissions", "requestPermissions":
            self = .unsupported(type: type)
        default:
            throw AppServerRPCError.invalidParams("event.action.type is not a Guardian action type")
        }
    }

    init?(
        call: ToolCall,
        cwd: URL,
        mcpRoutes: [String: MCPAgentToolRoute] = [:]
    ) {
        let arguments = try? ToolArguments(call.argumentsJSON)
        switch call.name {
        case ToolDefinition.shellRun.name:
            guard let command = arguments?.string("cmd") ?? arguments?.string("command") else { return nil }
            let workingDirectory = Self.workingDirectory(
                arguments?.string("cwd"),
                workspaceRoot: cwd
            )
            self = .command(source: "shell", command: command, cwd: workingDirectory.path)
        case ToolDefinition.applyPatch.name:
            guard let patch = arguments?.string("patch") else { return nil }
            let files = PatchToolExecutor.targetPaths(in: patch).map {
                cwd.appendingPathComponent($0).standardizedFileURL.path
            }
            self = .applyPatch(cwd: cwd.standardizedFileURL.path, files: files)
        default:
            guard let route = mcpRoutes[call.name] else { return nil }
            self = .mcpToolCall(server: route.serverName, toolName: route.toolName)
        }
    }

    var notificationValue: CLIJSONValue {
        switch self {
        case .command(let source, let command, let cwd):
            .object([
                "type": .string("command"),
                "source": .string(source == "unified_exec" ? "unifiedExec" : source),
                "command": .string(command),
                "cwd": .string(cwd)
            ])
        case .applyPatch(let cwd, let files):
            .object([
                "type": .string("applyPatch"),
                "cwd": .string(cwd),
                "files": .array(files.map(CLIJSONValue.string))
            ])
        case .mcpToolCall(let server, let toolName):
            .object([
                "type": .string("mcpToolCall"),
                "server": .string(server),
                "toolName": .string(toolName),
                "connectorId": .null,
                "connectorName": .null,
                "toolTitle": .null
            ])
        case .unsupported(let type):
            .object(["type": .string(type)])
        }
    }

    func matches(call: ToolCall, cwd: URL, mcpRoutes: [String: MCPAgentToolRoute] = [:]) -> Bool {
        guard let expected = Self(call: call, cwd: cwd, mcpRoutes: mcpRoutes) else { return false }
        return normalized == expected.normalized
    }

    private var normalized: AppServerGuardianReviewAction {
        switch self {
        case .command(let source, let command, let cwd):
            .command(
                source: source == "unifiedExec" ? "unified_exec" : source,
                command: command,
                cwd: URL(fileURLWithPath: cwd).standardizedFileURL.path
            )
        case .applyPatch(let cwd, let files):
            .applyPatch(
                cwd: URL(fileURLWithPath: cwd).standardizedFileURL.path,
                files: files.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            )
        case .mcpToolCall, .unsupported:
            self
        }
    }

    private static func workingDirectory(_ value: String?, workspaceRoot: URL) -> URL {
        guard let value, !value.isEmpty else { return workspaceRoot.standardizedFileURL }
        if value.hasPrefix("/") { return URL(fileURLWithPath: value).standardizedFileURL }
        return workspaceRoot.appendingPathComponent(value).standardizedFileURL
    }
}

struct AppServerGuardianReviewProjection: Sendable {
    var request: ApprovalRequest
    var action: AppServerGuardianReviewAction
    var startedAt: Date
}

extension AppServerSession {
    func prepareGuardianDenialApproval(_ raw: CLIJSONValue) async throws -> UUID? {
        let params = try AppServerParams(raw)
        let threadID = try threadID(from: params)
        guard !hasActiveOperation(for: threadID) else {
            throw AppServerRPCError.invalidParams("thread already has an active turn")
        }
        guard let eventValue = params.object["event"] else {
            throw AppServerRPCError.invalidParams("event is required")
        }
        let event = try AppServerGuardianAssessmentEvent(eventValue)
        let record = try await loadRecord(threadID)
        guard event.status == .denied else {
            return nil
        }

        let records = AutoReviewDenialHistory.records(
            in: record.thread,
            workspaceRoot: record.settings.cwd
        )
        guard let denial = records.first(where: { $0.id == event.id }) else {
            let unscoped = AutoReviewDenialHistory.records(in: record.thread)
                .first(where: { $0.id == event.id })
            if let unscoped {
                throw retryRPCError(for: unscoped.retryState)
            }
            throw AppServerRPCError.invalidRequest("Guardian denial is no longer available")
        }
        guard denial.retryState == .available else {
            throw retryRPCError(for: denial.retryState)
        }
        guard let identity = denial.request.actionIdentity, identity.isReplayable else {
            throw AppServerRPCError.invalidRequest(
                AgentAutoReviewRetryError.replayUnavailable.localizedDescription
            )
        }
        guard event.turnID == identity.turnID else {
            throw AppServerRPCError.invalidRequest("Guardian denial turn does not match the durable review")
        }
        guard event.targetItemID == denial.request.toolCall.id else {
            throw AppServerRPCError.invalidRequest("Guardian denial target does not match the durable review")
        }

        var configuredRunner: AppServerConfiguredRunner?
        let call = denial.request.toolCall
        if call.name == ToolDefinition.shellRun.name || call.name == ToolDefinition.applyPatch.name {
            guard event.action.matches(call: call, cwd: record.settings.cwd) else {
                throw AppServerRPCError.invalidRequest(
                    "Guardian denial action does not match the durable review"
                )
            }
        } else {
            let configured = try await runner(for: record)
            guard event.action.matches(
                call: call,
                cwd: record.settings.cwd,
                mcpRoutes: configured.mcpRoutes
            ) else {
                throw AppServerRPCError.invalidRequest(
                    "Guardian denial action does not match the durable review"
                )
            }
            configuredRunner = configured
        }

        guard let userMessage = record.thread.messages.last(where: {
            guard $0.role == .user else { return false }
            return ($0.turnID ?? $0.id.uuidString.lowercased()) == identity.turnID
        }) else {
            throw AppServerRPCError.invalidRequest(
                "Guardian denial no longer has its original user context"
            )
        }

        activeGuardianRetries[threadID] = ActiveGuardianRetry(
            denialRequestID: denial.id,
            turnID: identity.turnID,
            settings: record.settings,
            latestThread: record.thread,
            userMessage: userMessage.content,
            persistenceFailure: nil,
            task: nil,
            projector: AppServerProgressProjector(
                threadID: threadID,
                turnID: identity.turnID,
                cwd: record.settings.cwd,
                baseline: record.thread
            ),
            configuredRunner: configuredRunner
        )
        markThreadLoaded(threadID, subscription: .ifNew)
        return threadID
    }

    func launchGuardianRetry(_ threadID: UUID) {
        guard var active = activeGuardianRetries[threadID], active.task == nil else { return }
        active.task = Task { [weak self] in
            await self?.executeGuardianRetry(threadID)
        }
        activeGuardianRetries[threadID] = active
    }

    func cancelAllGuardianRetries() {
        activeGuardianRetries.values.forEach { $0.task?.cancel() }
    }

    private func executeGuardianRetry(_ threadID: UUID) async {
        guard let initial = activeGuardianRetries[threadID] else { return }
        await sendThreadStatus(threadID, active: true)
        do {
            let record = AppServerThreadRecord(
                thread: initial.latestThread,
                settings: initial.settings
            )
            let configured: AppServerConfiguredRunner
            if let prepared = initial.configuredRunner {
                configured = prepared
            } else {
                configured = try await runner(for: record)
            }
            guard var active = activeGuardianRetries[threadID] else { return }
            active.projector.registerMCPRoutes(configured.mcpRoutes)
            activeGuardianRetries[threadID] = active
            let result = try await configured.runner.retryAutoReviewDenial(
                requestID: initial.denialRequestID,
                in: initial.latestThread,
                workspaceRoot: initial.settings.cwd,
                userMessage: initial.userMessage,
                onProgress: { [weak self] snapshot in
                    await self?.receiveGuardianRetryProgress(threadID: threadID, snapshot: snapshot)
                }
            )
            try Task.checkCancellation()
            guard let latest = activeGuardianRetries[threadID] else { return }
            if let failure = latest.persistenceFailure {
                throw AppServerGuardianRetryError.persistence(failure)
            }
            try await repository.save(AppServerThreadRecord(
                thread: result.thread,
                settings: latest.settings
            ))
            await finishGuardianRetry(threadID, snapshot: result.thread, error: nil)
        } catch is CancellationError {
            let snapshot = activeGuardianRetries[threadID]?.latestThread ?? initial.latestThread
            await finishGuardianRetry(threadID, snapshot: snapshot, error: nil)
        } catch {
            let snapshot = activeGuardianRetries[threadID]?.latestThread ?? initial.latestThread
            await finishGuardianRetry(
                threadID,
                snapshot: snapshot,
                error: error.localizedDescription
            )
        }
    }

    private func receiveGuardianRetryProgress(threadID: UUID, snapshot: ChatThread) async {
        guard var active = activeGuardianRetries[threadID] else { return }
        active.latestThread = snapshot
        let notifications = active.projector.project(snapshot)
        activeGuardianRetries[threadID] = active
        do {
            try await repository.save(AppServerThreadRecord(thread: snapshot, settings: active.settings))
        } catch {
            guard var failed = activeGuardianRetries[threadID] else { return }
            failed.persistenceFailure = error.localizedDescription
            failed.task?.cancel()
            activeGuardianRetries[threadID] = failed
        }
        await send(notifications)
    }

    private func finishGuardianRetry(
        _ threadID: UUID,
        snapshot: ChatThread,
        error: String?
    ) async {
        guard var active = activeGuardianRetries.removeValue(forKey: threadID) else { return }
        let notifications = active.projector.finish(snapshot, completedAt: Date())
        do {
            try await repository.save(AppServerThreadRecord(thread: snapshot, settings: active.settings))
        } catch {
            await sendTurnError(
                "Could not persist the Guardian retry: \(error.localizedDescription)",
                threadID: threadID,
                turnID: active.turnID
            )
        }
        await send(notifications)
        if let error {
            await sendTurnError(error, threadID: threadID, turnID: active.turnID)
        }
        await sendThreadStatus(threadID, active: false)
    }

    private func retryRPCError(for state: AutoReviewDenialRetryState) -> AppServerRPCError {
        let error: AgentAutoReviewRetryError = switch state {
        case .available, .contextChanged: .contextChanged
        case .consumed: .retryConsumed
        case .unavailable: .replayUnavailable
        }
        return .invalidRequest(error.localizedDescription)
    }
}

private enum AppServerGuardianRetryError: LocalizedError {
    case persistence(String)

    var errorDescription: String? {
        switch self {
        case .persistence(let reason): "Guardian retry persistence failed: \(reason)"
        }
    }
}

extension ApprovalRiskLevel {
    var guardianWireValue: CLIJSONValue {
        switch self {
        case .unknown: .null
        case .low, .medium, .high, .critical: .string(rawValue)
        }
    }
}

extension ApprovalUserAuthorization {
    var guardianWireValue: CLIJSONValue {
        switch self {
        case .explicit: .string("high")
        case .implicit: .string("medium")
        case .missing, .mismatched: .string("low")
        case .unknown: .string("unknown")
        }
    }
}
