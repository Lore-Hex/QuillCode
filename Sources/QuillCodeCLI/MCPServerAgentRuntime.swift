import Foundation
import QuillCodeAgent
import QuillCodeCore

extension MCPServerSession {
    func execute(
        _ invocation: MCPServerToolInvocation,
        requestID: MCPServerRequestID
    ) async throws -> String {
        switch invocation {
        case .start(let threadID, let input):
            let effective = try MCPServerConfigOverlay.resolve(
                input: input,
                base: appConfig,
                serverModel: request.model
            )
            let cwd = try resolvedCWD(input.cwd)
            let mode = mode(
                sandbox: effective.sandbox,
                approvalPolicy: effective.approvalPolicy,
                reviewer: effective.approvalsReviewer
            )
            var thread = ChatThread(
                id: threadID,
                mode: mode,
                model: effective.model
            )
            appendInstructions(input, to: &thread)
            let settings = AppServerThreadSettings(
                cwd: cwd,
                approvalPolicy: .string(effective.approvalPolicy),
                approvalsReviewer: effective.approvalsReviewer,
                sandbox: effective.sandbox,
                runtimeAppConfig: effective.appConfig,
                compactPrompt: input.compactPrompt
            )
            let record = AppServerThreadRecord(thread: thread, settings: settings)
            try await repository.create(record)
            await sendSessionConfigured(
                requestID: requestID,
                record: record
            )
            return try await executePrompt(
                input.prompt,
                record: record,
                requestID: requestID
            )

        case .reply(let threadID, let prompt):
            let record: AppServerThreadRecord
            do {
                record = try await repository.load(threadID)
            } catch {
                throw MCPServerToolInputError.invalid(
                    "Thread \(threadID.uuidString.lowercased()) was not found."
                )
            }
            return try await executePrompt(prompt, record: record, requestID: requestID)
        }
    }

    private func executePrompt(
        _ prompt: String,
        record: AppServerThreadRecord,
        requestID: MCPServerRequestID
    ) async throws -> String {
        progressProjectors[requestID] = MCPServerProgressProjector(
            threadID: record.thread.id,
            cwd: record.settings.cwd,
            baseline: record.thread
        )
        let configuredRunner = try await configuredRunner(
            for: record,
            requestID: requestID
        )
        let result = try await configuredRunner.send(
            prompt,
            in: record.thread,
            workspaceRoot: record.settings.cwd,
            onProgress: { [weak self] snapshot in
                await self?.receiveProgress(
                    snapshot,
                    settings: record.settings,
                    requestID: requestID
                )
            }
        )
        try Task.checkCancellation()
        if let failure = progressFailures[requestID] {
            throw MCPServerRuntimeError.persistence(failure)
        }
        try await repository.save(AppServerThreadRecord(
            thread: result.thread,
            settings: record.settings
        ))
        let content = result.thread.messages.last(where: { $0.role == .assistant })?.content ?? ""
        await sendEvent(
            requestID: requestID,
            threadID: record.thread.id,
            message: .object([
                "type": .string("turn_complete"),
                "last_agent_message": .string(content)
            ])
        )
        return content
    }

    private func configuredRunner(
        for record: AppServerThreadRecord,
        requestID: MCPServerRequestID
    ) async throws -> AgentRunner {
        let runtimeConfig = record.settings.runtimeAppConfig ?? appConfig
        let runRequest = CLIRunRequest(
            style: .exec,
            prompt: "",
            live: request.live,
            apiKey: request.apiKey,
            model: record.thread.model,
            baseURL: request.baseURL,
            cwd: record.settings.cwd,
            home: request.home,
            sandbox: record.settings.sandbox,
            explicitMode: record.thread.mode,
            skipsGitRepositoryCheck: true
        )
        let runtime = CLIRuntimeConfiguration(
            request: runRequest,
            appConfig: runtimeConfig,
            paths: paths,
            imageAttachmentStore: attachmentStore,
            environment: environment
        )
        var runner = runtime.applyingInvocationPolicy(to: try runnerFactory(runtime))
        let configurations = try AppServerMCPConfigurationLoader.load(
            globalConfig: paths.configFile,
            projectRoot: record.settings.cwd,
            fallbackCWD: record.settings.cwd,
            environment: environment
        )
        let adapter = try await MCPAgentRunnerAdapter.prepare(
            registry: mcpRegistry,
            scope: "thread:\(record.thread.id.uuidString.lowercased())",
            configurations: configurations
        )
        runner = adapter.configure(runner)
        let inheritedHook = runner.permissionRequestHook
        runner.permissionRequestHook = { [weak self] call, reason, thread, workspaceRoot in
            var notices: [String] = []
            if let inheritedHook {
                let inherited = try await inheritedHook(call, reason, thread, workspaceRoot)
                notices.append(contentsOf: inherited.notices)
                switch inherited.decision {
                case .allow, .deny:
                    return AgentPermissionRequestHookOutcome(
                        decision: inherited.decision,
                        notices: notices
                    )
                case .noDecision:
                    break
                }
            }
            guard let self else { return AgentPermissionRequestHookOutcome(notices: notices) }
            let decision = await self.requestApproval(
                for: call,
                reason: reason,
                thread: thread,
                workspaceRoot: workspaceRoot,
                originatingRequestID: requestID
            )
            notices.append(contentsOf: decision.notices)
            return AgentPermissionRequestHookOutcome(
                decision: decision.decision,
                notices: notices
            )
        }
        return runner
    }

    private func receiveProgress(
        _ snapshot: ChatThread,
        settings: AppServerThreadSettings,
        requestID: MCPServerRequestID
    ) async {
        guard var projector = progressProjectors[requestID] else { return }
        let events = projector.project(snapshot)
        progressProjectors[requestID] = projector
        do {
            try await repository.save(AppServerThreadRecord(thread: snapshot, settings: settings))
        } catch {
            progressFailures[requestID] = error.localizedDescription
            activeCalls[requestID]?.task.cancel()
        }
        for event in events {
            await sendEvent(
                requestID: requestID,
                threadID: snapshot.id,
                message: event.message,
                eventID: event.id
            )
        }
    }

    private func sendSessionConfigured(
        requestID: MCPServerRequestID,
        record: AppServerThreadRecord
    ) async {
        await sendEvent(
            requestID: requestID,
            threadID: record.thread.id,
            message: .object([
                "type": .string("session_configured"),
                "session_id": .string(record.thread.id.uuidString.lowercased()),
                "thread_id": .string(record.thread.id.uuidString.lowercased()),
                "model": .string(record.thread.model),
                "model_provider_id": .string("trustedrouter"),
                "approval_policy": record.settings.approvalPolicy,
                "approvals_reviewer": .string(record.settings.approvalsReviewer),
                "sandbox": .string(record.settings.sandbox.rawValue),
                "cwd": .string(record.settings.cwd.path)
            ])
        )
    }

    private func resolvedCWD(_ value: String?) throws -> URL {
        let candidate: URL
        if let value, !value.isEmpty {
            candidate = NSString(string: value).isAbsolutePath
                ? URL(fileURLWithPath: value)
                : currentDirectory.appendingPathComponent(value)
        } else {
            candidate = currentDirectory
        }
        let normalized = candidate.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalized.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw MCPServerToolInputError.invalid("cwd must name an existing directory")
        }
        return normalized
    }

    private func mode(
        sandbox: CLISandboxMode,
        approvalPolicy: String,
        reviewer: String
    ) -> AgentMode {
        if sandbox == .readOnly { return .readOnly }
        if approvalPolicy == "never" || reviewer != "user" { return .auto }
        return .review
    }

    private func appendInstructions(_ input: MCPServerRunInput, to thread: inout ChatThread) {
        for (label, value) in [
            ("Base instructions", input.baseInstructions),
            ("Developer instructions", input.developerInstructions)
        ] {
            guard let value,
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            thread.messages.append(ChatMessage(role: .system, content: "\(label):\n\(value)"))
        }
    }
}

private enum MCPServerRuntimeError: LocalizedError {
    case persistence(String)

    var errorDescription: String? {
        switch self {
        case .persistence(let reason): "Thread persistence failed: \(reason)"
        }
    }
}
