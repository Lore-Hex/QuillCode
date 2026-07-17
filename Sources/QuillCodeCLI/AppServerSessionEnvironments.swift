import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

struct AppServerThreadEnvironmentSubscription: Sendable {
    var environmentID: String
    var token: UUID
}

struct AppServerExecutionEnvironment: Sendable {
    enum Access: Sendable {
        case local
        case disabled
        case remote(AppServerRemoteEnvironmentToolExecutor)
    }

    var access: Access
    var workspaceRoot: URL
    var modelContext: String?
}

extension AppServerSession {
    func synchronizeEnvironmentSubscription(
        for record: AppServerThreadRecord
    ) async throws {
        let environmentID: String? = if record.settings.environments?.isEmpty == true {
            nil
        } else {
            record.settings.environments?.first?.environmentID ?? "local"
        }
        if environmentSubscriptions[record.thread.id]?.environmentID == environmentID {
            return
        }
        await removeEnvironmentSubscription(for: record.thread.id)
        guard let environmentID else { return }

        let token = UUID()
        environmentSubscriptions[record.thread.id] = .init(
            environmentID: environmentID,
            token: token
        )
        do {
            try await environmentRegistry.subscribe(
                token: token,
                threadID: record.thread.id,
                environmentID: environmentID
            ) { [weak self] event in
                await self?.receiveEnvironmentConnectionEvent(event)
            }
        } catch {
            environmentSubscriptions[record.thread.id] = nil
            throw error
        }
    }

    func removeEnvironmentSubscription(for threadID: UUID) async {
        guard let subscription = environmentSubscriptions.removeValue(forKey: threadID) else {
            return
        }
        await environmentRegistry.unsubscribe(subscription.token)
    }

    func removeAllEnvironmentSubscriptions() async {
        let tokens = environmentSubscriptions.values.map(\.token)
        environmentSubscriptions.removeAll()
        for token in tokens {
            await environmentRegistry.unsubscribe(token)
        }
    }

    private func receiveEnvironmentConnectionEvent(
        _ event: AppServerEnvironmentRegistry.ConnectionEvent
    ) async {
        guard subscribedThreadIDs.contains(event.threadID),
              environmentSubscriptions[event.threadID]?.environmentID == event.environmentID else {
            return
        }
        await sendNotification(
            event.connected
                ? "thread/environment/connected"
                : "thread/environment/disconnected",
            params: .object([
                "environmentId": .string(event.environmentID),
                "threadId": .string(AppServerThreadProjection.identifier(event.threadID))
            ])
        )
    }

    func applyEnvironmentSelection(
        from params: AppServerParams,
        to settings: inout AppServerThreadSettings
    ) async throws {
        guard params.object["environments"] != nil else { return }
        let selections = try AppServerThreadEnvironmentSelection.parse(from: params)
        guard let selections else { return }
        try await environmentRegistry.validate(selections)
        settings.environments = selections
    }

    func executionEnvironment(
        for settings: AppServerThreadSettings
    ) async throws -> AppServerExecutionEnvironment {
        if settings.environments?.isEmpty == true {
            return AppServerExecutionEnvironment(
                access: .disabled,
                workspaceRoot: settings.cwd,
                modelContext: """
                <environment_context>
                  <environment_access>disabled</environment_access>
                </environment_context>
                """
            )
        }

        let explicitSelection = settings.environments?.first
        let environmentID = explicitSelection?.environmentID ?? "local"
        switch try await environmentRegistry.resolve(environmentID) {
        case .local(let info):
            let workspaceRoot: URL
            if let cwd = explicitSelection?.cwd,
               !cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                workspaceRoot = try resolvedCWD(cwd, fallback: settings.cwd)
            } else {
                workspaceRoot = settings.cwd
            }
            return AppServerExecutionEnvironment(
                access: .local,
                workspaceRoot: workspaceRoot,
                modelContext: """
                <environment_context>
                  <environment_id>\(AppServerModelContextXML.escaped(environmentID))</environment_id>
                  <cwd>\(AppServerModelContextXML.escaped(workspaceRoot.path))</cwd>
                  <shell>\(AppServerModelContextXML.escaped(info.shell.name))</shell>
                </environment_context>
                """
            )
        case .remote(let info, let client):
            let executor = try AppServerRemoteEnvironmentToolExecutor(
                environmentID: environmentID,
                cwd: explicitSelection?.cwd ?? "",
                environmentInfo: info,
                client: client
            )
            return AppServerExecutionEnvironment(
                access: .remote(executor),
                workspaceRoot: await executor.logicalWorkspaceURL,
                modelContext: await executor.modelEnvironmentContext
            )
        }
    }

    func configure(
        _ runner: AgentRunner,
        for environment: AppServerExecutionEnvironment
    ) -> AgentRunner {
        switch environment.access {
        case .local:
            return runner
        case .disabled:
            return configureEnvironmentRestrictedRunner(
                runner,
                baseTools: [.webSearch],
                remoteExecutor: nil
            )
        case .remote(let executor):
            return configureEnvironmentRestrictedRunner(
                runner,
                baseTools: AppServerRemoteEnvironmentToolExecutor.toolDefinitions,
                remoteExecutor: executor
            )
        }
    }

    private func configureEnvironmentRestrictedRunner(
        _ runner: AgentRunner,
        baseTools: [ToolDefinition],
        remoteExecutor: AppServerRemoteEnvironmentToolExecutor?
    ) -> AgentRunner {
        var configured = runner
        let inheritedOverride = configured.toolExecutionOverride
        let remoteToolNames = AppServerRemoteEnvironmentToolExecutor.remotelyExecutedToolNames
        configured.baseToolDefinitions = baseTools
        configured.streamingToolExecutionOverride = nil
        configured.lsp = nil
        configured.workspaceStateSignature = { _ in
            remoteExecutor == nil ? "environment-access-disabled" : "remote-environment"
        }
        configured.toolExecutionOverride = { call, workspaceRoot in
            if let remoteExecutor, remoteToolNames.contains(call.name) {
                return await remoteExecutor.execute(call)
            }
            if let inheritedOverride,
               let result = await inheritedOverride(call, workspaceRoot) {
                return result
            }
            return ToolResult(
                ok: false,
                error: remoteExecutor == nil
                    ? "Environment access is disabled for this thread."
                    : "Tool is unavailable in the selected remote environment: \(call.name)"
            )
        }
        return configured
    }
}
