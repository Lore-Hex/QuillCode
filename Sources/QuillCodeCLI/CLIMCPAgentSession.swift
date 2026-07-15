import Foundation
import QuillCodeAgent
import QuillCodeTools

struct CLIMCPAgentSessionPreparer: Sendable {
    private let launcher: any MCPClientLaunching
    private let httpClient: any MCPHTTPClient

    init(
        launcher: any MCPClientLaunching = DefaultMCPClientLauncher(),
        httpClient: any MCPHTTPClient = URLSessionMCPHTTPClient()
    ) {
        self.launcher = launcher
        self.httpClient = httpClient
    }

    func prepare(
        configuration: CLIRuntimeConfiguration,
        threadID: UUID
    ) async throws -> CLIMCPAgentSession {
        guard !configuration.request.ignoresUserConfig else {
            return CLIMCPAgentSession()
        }

        let configurations = try AppServerMCPConfigurationLoader.load(
            globalConfig: configuration.paths.configFile,
            projectRoot: configuration.request.cwd,
            fallbackCWD: configuration.request.cwd,
            environment: configuration.environment
        )
        guard !configurations.isEmpty else {
            return CLIMCPAgentSession()
        }

        let registry = AppServerMCPRegistry(
            launcher: launcher,
            secretStore: AppServerMCPSecretStore(
                directory: configuration.paths.secretsDirectory
            ),
            httpClient: httpClient
        )
        let scope = "exec:\(threadID.uuidString.lowercased())"
        do {
            let adapter = try await MCPAgentRunnerAdapter.prepare(
                registry: registry,
                scope: scope,
                configurations: configurations
            )
            return CLIMCPAgentSession(adapter: adapter, registry: registry)
        } catch {
            await registry.terminateAll()
            throw error
        }
    }
}

struct CLIMCPAgentSession: Sendable {
    private let adapter: MCPAgentRunnerAdapter?
    private let registry: AppServerMCPRegistry?

    init(
        adapter: MCPAgentRunnerAdapter? = nil,
        registry: AppServerMCPRegistry? = nil
    ) {
        self.adapter = adapter
        self.registry = registry
    }

    func configure(_ runner: AgentRunner) -> AgentRunner {
        adapter?.configure(runner) ?? runner
    }

    func shutdown() async {
        await registry?.terminateAll()
    }
}
