import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

struct WorkspaceMCPRuntimeResult: Sendable, Hashable {
    var ok: Bool
    var errorMessage: String?
    var notice: String?
    var agentStatus: String?
}

struct WorkspaceMCPFinishResult: Sendable, Hashable {
    var changed: Bool
    var agentStatus: String?
}

final class WorkspaceMCPRuntime: @unchecked Sendable {
    private var processes: [String: WorkspaceMCPProcessHandle]
    private let launcher: any WorkspaceMCPServerLaunching

    init(launcher: any WorkspaceMCPServerLaunching = DefaultWorkspaceMCPServerLauncher()) {
        self.processes = [:]
        self.launcher = launcher
    }

    deinit {
        terminateAllRunningProcesses()
    }

    var hasRunningServers: Bool {
        processes.values.contains { $0.process.isRunning }
    }

    var runningServerIDs: [String] {
        processes.compactMap { id, handle in
            handle.process.isRunning ? id : nil
        }
    }

    func terminateAllRunningProcesses() {
        for handle in processes.values where handle.process.isRunning {
            handle.process.clearReadabilityHandlers()
            handle.process.terminate()
        }
        processes.removeAll()
    }

    func startServer(
        manifest: ProjectExtensionManifest,
        workspaceRoot: URL,
        extensions: inout ExtensionsState,
        onTermination: @escaping @MainActor @Sendable (_ id: String, _ terminationStatus: Int32) -> Void
    ) -> WorkspaceMCPRuntimeResult {
        let launchRequest: WorkspaceMCPLaunchRequest
        do {
            launchRequest = try WorkspaceMCPLaunchRequest.make(
                manifest: manifest,
                workspaceRoot: workspaceRoot
            )
        } catch let error as WorkspaceMCPLaunchRequestError {
            extensions.mcpServerStatuses[manifest.id] = .failed
            return WorkspaceMCPRuntimeResult(
                ok: false,
                errorMessage: error.localizedDescription,
                agentStatus: nil
            )
        } catch {
            extensions.mcpServerStatuses[manifest.id] = .failed
            return WorkspaceMCPRuntimeResult(
                ok: false,
                errorMessage: "Could not validate \(manifest.name): \(error.localizedDescription)",
                notice: "MCP server \(manifest.name) failed to start",
                agentStatus: TopBarAgentStatusLabel.failed
            )
        }
        if let handle = processes[manifest.id], handle.process.isRunning {
            if extensions.mcpServerStatuses[manifest.id]?.isActive != true {
                extensions.mcpServerStatuses[manifest.id] = .running
            }
            return WorkspaceMCPRuntimeResult(ok: true, agentStatus: TopBarAgentStatusLabel.idle)
        }

        let launchedServer: WorkspaceMCPLaunchedServer

        do {
            launchedServer = try launcher.launch(
                request: launchRequest,
                onTermination: onTermination
            )
        } catch {
            extensions.mcpServerStatuses[manifest.id] = .failed
            return WorkspaceMCPRuntimeResult(
                ok: false,
                errorMessage: "Could not start \(manifest.name): \(error.localizedDescription)",
                notice: "MCP server \(manifest.name) failed to start",
                agentStatus: TopBarAgentStatusLabel.failed
            )
        }

        processes[manifest.id] = WorkspaceMCPProcessHandle(
            process: launchedServer.process,
            session: launchedServer.session
        )
        extensions.mcpServerStatuses[manifest.id] = .probing
        extensions.mcpServerProbeSummaries[manifest.id] = nil

        do {
            let result = try launchedServer.session.probe(timeout: 2.0)
            extensions.mcpServerStatuses[manifest.id] = .ready
            extensions.mcpServerProbeSummaries[manifest.id] = MCPServerProbeSummary(result: result)
            launchedServer.process.startDrainingStandardError()
            return WorkspaceMCPRuntimeResult(
                ok: true,
                notice: "MCP server \(manifest.name) ready\(Self.probeNoticeSuffix(for: result))",
                agentStatus: TopBarAgentStatusLabel.idle
            )
        } catch {
            launchedServer.process.clearReadabilityHandlers()
            if launchedServer.process.isRunning {
                launchedServer.process.terminate()
            }
            processes[manifest.id] = nil
            let message = error.localizedDescription
            extensions.mcpServerStatuses[manifest.id] = .failed
            extensions.mcpServerProbeSummaries[manifest.id] = MCPServerProbeSummary(errorMessage: message)
            return WorkspaceMCPRuntimeResult(
                ok: false,
                errorMessage: "Could not verify \(manifest.name): \(message)",
                notice: "MCP server \(manifest.name) probe failed: \(message)",
                agentStatus: TopBarAgentStatusLabel.failed
            )
        }
    }

    func stopServer(
        manifest: ProjectExtensionManifest,
        extensions: inout ExtensionsState
    ) -> WorkspaceMCPRuntimeResult {
        stopProcess(id: manifest.id)
        extensions.mcpServerStatuses[manifest.id] = .stopped
        extensions.mcpServerProbeSummaries[manifest.id] = nil
        return WorkspaceMCPRuntimeResult(
            ok: true,
            notice: "MCP server \(manifest.name) stopped",
            agentStatus: TopBarAgentStatusLabel.idle
        )
    }

    func finishServer(
        id: String,
        terminationStatus: Int32,
        extensions: inout ExtensionsState
    ) -> WorkspaceMCPFinishResult {
        processes[id] = nil
        if extensions.mcpServerStatuses[id] == .stopped {
            return WorkspaceMCPFinishResult(changed: false, agentStatus: nil)
        }
        extensions.mcpServerStatuses[id] = terminationStatus == 0 ? .stopped : .failed
        if terminationStatus != 0 {
            extensions.mcpServerProbeSummaries[id] = MCPServerProbeSummary(
                errorMessage: "Process exited with status \(terminationStatus)."
            )
        } else {
            extensions.mcpServerProbeSummaries[id] = nil
        }
        let status = terminationStatus == 0
            ? TopBarAgentStatusLabel.idle
            : TopBarAgentStatusLabel.failed
        return WorkspaceMCPFinishResult(
            changed: true,
            agentStatus: status
        )
    }

    func cancelAll(extensions: inout ExtensionsState) -> Bool {
        let runningIDs = runningServerIDs
        for id in runningIDs {
            stopProcess(id: id)
            extensions.mcpServerStatuses[id] = .stopped
            extensions.mcpServerProbeSummaries[id] = nil
        }
        return !runningIDs.isEmpty
    }

    func toolDefinitions(
        manifests: [ProjectExtensionManifest],
        extensions: ExtensionsState
    ) -> [ToolDefinition] {
        Self.toolDefinitions(
            manifests: manifests,
            extensions: extensions,
            runningServerIDs: Set(runningServerIDs)
        )
    }

    static func toolDefinitions(
        manifests: [ProjectExtensionManifest],
        extensions: ExtensionsState,
        runningServerIDs: Set<String>
    ) -> [ToolDefinition] {
        WorkspaceMCPToolCatalog(
            manifests: manifests,
            extensions: extensions,
            runningServerIDs: runningServerIDs
        ).toolDefinitions()
    }

    func executionOverride(extensions: ExtensionsState) -> AgentToolExecutionOverride? {
        let sessions = processes.compactMapValues { handle in
            handle.process.isRunning ? handle.session : nil
        }
        return Self.executionOverride(sessions: sessions, summaries: extensions.mcpServerProbeSummaries)
    }

    func streamingExecutionOverride(
        extensions: ExtensionsState
    ) -> AgentStreamingToolExecutionOverride? {
        let sessions = processes.compactMapValues { handle in
            handle.process.isRunning ? handle.session : nil
        }
        return Self.streamingExecutionOverride(
            sessions: sessions,
            summaries: extensions.mcpServerProbeSummaries
        )
    }

    func execute(call: ToolCall, extensions: ExtensionsState) -> ToolResult? {
        let sessions = processes.compactMapValues { handle in
            handle.process.isRunning ? handle.session : nil
        }
        return Self.execute(
            call: call,
            sessions: sessions,
            summaries: extensions.mcpServerProbeSummaries
        )
    }

    private func stopProcess(id: String) {
        if let handle = processes[id], handle.process.isRunning {
            handle.process.clearReadabilityHandlers()
            handle.process.terminate()
        }
        processes[id] = nil
    }
}
