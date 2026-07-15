import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools

typealias AppServerMessageSink = @Sendable (String) async -> Void

struct AppServerConfiguredRunner: Sendable {
    var runner: AgentRunner
    var mcpRoutes: [String: MCPAgentToolRoute]
}

actor AppServerSession {
    static let maximumMessageBytes = 1_048_576

    enum HandshakeState: Sendable, Equatable {
        case awaitingInitialize
        case awaitingInitialized
        case ready
    }

    struct ActiveTurn: Sendable {
        var id: String
        var startedAt: Date
        var settings: AppServerThreadSettings
        var latestThread: ChatThread
        var currentInput: AppServerTurnInput
        var currentUserMessage: ChatMessage
        var queuedSteering: [AppServerTurnInput]
        var persistenceFailure: String?
        var task: Task<Void, Never>?
        var projector: AppServerProgressProjector
    }

    let request: CLIAppServerRequest
    let environment: [String: String]
    let currentDirectory: URL
    let paths: QuillCodePaths
    var appConfig: AppConfig
    let repository: AppServerThreadRepository
    let attachmentStore: ImageAttachmentStore
    let mcpRegistry: AppServerMCPRegistry
    let runnerFactory: CLIAgentRunnerFactory
    let sink: AppServerMessageSink

    var handshake = HandshakeState.awaitingInitialize
    var optedOutNotifications: Set<String> = []
    var activeTurns: [UUID: ActiveTurn] = [:]
    var nextServerRequestSequence: Int64 = 1
    var pendingApprovals: [AppServerRequestID: AppServerPendingApproval] = [:]
    var cachedModelCatalog: TrustedRouterModelCatalog?
    var cachedSkillSnapshots: [String: SkillCatalogSnapshot] = [:]
    var skillExtraRoots: [URL] = []
    var skillWatchCWDs: [URL] = []
    var skillWatchRoots: [SkillRoot] = []
    var skillWatchTask: Task<Void, Never>?
    var skillWatchGeneration: UInt64 = 0
    var fileWatches: [String: AppServerFileWatchRegistration] = [:]
    var inputFinished = false

    init(
        request: CLIAppServerRequest,
        environment: [String: String],
        currentDirectory: URL,
        runnerFactory: @escaping CLIAgentRunnerFactory,
        mcpLauncher: any MCPClientLaunching = DefaultMCPClientLauncher(),
        sink: @escaping AppServerMessageSink
    ) throws {
        let paths = request.home.map { QuillCodePaths(home: $0) } ?? QuillCodePaths()
        try paths.ensure()
        self.request = request
        self.environment = environment
        self.currentDirectory = currentDirectory.standardizedFileURL
        self.paths = paths
        self.appConfig = try ConfigStore(fileURL: paths.configFile).load()
        self.repository = AppServerThreadRepository(paths: paths, fallbackCWD: currentDirectory)
        self.attachmentStore = ImageAttachmentStore(directory: paths.attachmentsDirectory)
        self.mcpRegistry = AppServerMCPRegistry(launcher: mcpLauncher)
        self.runnerFactory = runnerFactory
        self.sink = sink
    }

    func receive(_ line: Data) async {
        let message: AppServerInboundMessage
        do {
            message = try AppServerInboundMessage(data: line)
        } catch AppServerWireError.invalidEnvelope {
            await send(.error(id: nil, error: .invalidRequest))
            return
        } catch {
            await send(.error(id: nil, error: .parseError))
            return
        }

        switch message {
        case .request(let id, let method, let params):
            await handleRequest(id: id, method: method, params: params)
        case .notification(let method, let params):
            await handleNotification(method: method, params: params)
        case .response(let id, let result, let error):
            resolveApprovalResponse(id: id, result: result, error: error)
        }
    }

    func waitForActiveTurns() async {
        let tasks = activeTurns.values.compactMap(\.task)
        for task in tasks { await task.value }
    }

    func finishInput() async {
        inputFinished = true
        cancelSkillWatcher()
        cancelAllFileWatches()
        await mcpRegistry.terminateAll()
        resolveAllPendingApprovals(
            with: .deny(reason: "The app-server client disconnected before answering the approval request.")
        )
    }

    private func handleRequest(
        id: AppServerRequestID,
        method: String,
        params: CLIJSONValue
    ) async {
        if method == "initialize" {
            await initialize(id: id, params: params)
            return
        }
        guard handshake == .ready else {
            await send(.error(id: id, error: .notInitialized))
            return
        }

        do {
            let result: CLIJSONValue
            var turnToLaunch: UUID?
            switch method {
            case "model/list": result = try await listModels(params)
            case "modelProvider/capabilities/read": result = try modelProviderCapabilities(params)
            case "account/read": result = try readAccount(params)
            case "account/usage/read": result = try await readAccountUsage(params)
            case "account/rateLimits/read": result = try await readAccountRateLimits(params)
            case "config/read": result = try readConfig(params)
            case "config/value/write": result = try await writeConfigValue(params)
            case "config/batchWrite": result = try await writeConfigBatch(params)
            case "plugin/list": result = try listPlugins(params)
            case "plugin/installed": result = try listInstalledPlugins(params)
            case "plugin/read": result = try readPlugin(params)
            case "plugin/skill/read": result = try readRemotePluginSkill(params)
            case "skills/list": result = try listSkills(params)
            case "skills/extraRoots/set": result = try await setSkillExtraRoots(params)
            case "skills/config/write": result = try await writeSkillConfig(params)
            case "mcpServerStatus/list": result = try await listMCPServerStatus(params)
            case "config/mcpServer/reload": result = try await reloadMCPServers(params)
            case "mcpServer/tool/call": result = try await callMCPServerTool(params)
            case "mcpServer/resource/read": result = try await readMCPResource(params)
            case "mcpServer/oauth/login": result = try loginMCPServerOAuth(params)
            case "fs/readFile": result = try readFile(params)
            case "fs/writeFile": result = try writeFile(params)
            case "fs/createDirectory": result = try createDirectory(params)
            case "fs/getMetadata": result = try fileMetadata(params)
            case "fs/readDirectory": result = try readDirectory(params)
            case "fs/remove": result = try removeFileSystemItem(params)
            case "fs/copy": result = try copyFileSystemItem(params)
            case "fs/watch": result = try startFileWatch(params)
            case "fs/unwatch": result = try await stopFileWatch(params)
            case "thread/start": result = try await startThread(params)
            case "thread/resume": result = try await resumeThread(params)
            case "thread/fork": result = try await forkThread(params)
            case "thread/list": result = try await listThreads(params)
            case "thread/read": result = try await readThread(params)
            case "thread/archive": result = try await setThreadArchived(params, archived: true)
            case "thread/unarchive": result = try await setThreadArchived(params, archived: false)
            case "thread/delete": result = try await deleteThread(params)
            case "thread/name/set": result = try await setThreadName(params)
            case "thread/goal/set": result = try await setThreadGoal(params)
            case "thread/goal/get": result = try await getThreadGoal(params)
            case "thread/goal/clear": result = try await clearThreadGoal(params)
            case "turn/start":
                result = try await startTurn(params)
                turnToLaunch = try threadID(from: AppServerParams(params))
            case "turn/steer": result = try await steerTurn(params)
            case "turn/interrupt": result = try await interruptTurn(params)
            default:
                throw AppServerRPCError.methodNotFound(method)
            }
            await send(.response(id: id, result: result))
            if let turnToLaunch { launchTurn(turnToLaunch) }
        } catch let error as AppServerRPCError {
            await send(.error(id: id, error: error))
        } catch {
            await send(.error(id: id, error: .internalError(error.localizedDescription)))
        }
    }

    private func handleNotification(method: String, params: CLIJSONValue) async {
        guard method == "initialized" else { return }
        guard handshake == .awaitingInitialized else { return }
        _ = params
        handshake = .ready
    }

    private func initialize(id: AppServerRequestID, params: CLIJSONValue) async {
        guard handshake == .awaitingInitialize else {
            await send(.error(id: id, error: .alreadyInitialized))
            return
        }
        do {
            let params = try AppServerParams(params)
            guard let client = try params.optionalObject("clientInfo") else {
                throw AppServerRPCError.invalidParams("clientInfo is required")
            }
            let clientParams = try AppServerParams(.object(client))
            let name = try clientParams.requiredString("name")
            let version = try clientParams.requiredString("version")
            if let capabilities = try params.optionalObject("capabilities") {
                let values = try AppServerParams(.object(capabilities)).optionalArray("optOutNotificationMethods") ?? []
                optedOutNotifications = Set(try values.map { value in
                    guard let method = value.stringValue else {
                        throw AppServerRPCError.invalidParams(
                            "capabilities.optOutNotificationMethods must contain strings"
                        )
                    }
                    return method
                })
            }
            handshake = .awaitingInitialized
            await send(.response(id: id, result: .object([
                "userAgent": .string("QuillCode/\(QuillCodeCommandRunner.version) (\(name); \(version))"),
                "codexHome": .string(paths.home.path),
                "platformFamily": .string("unix"),
                "platformOs": .string(AppServerPlatform.currentOS)
            ])))
        } catch let error as AppServerRPCError {
            await send(.error(id: id, error: error))
        } catch {
            await send(.error(id: id, error: .invalidParams(error.localizedDescription)))
        }
    }

    func sendNotification(_ method: String, params: CLIJSONValue) async {
        guard !optedOutNotifications.contains(method) else { return }
        await send(.notification(method: method, params: params))
    }

    func send(_ message: AppServerOutboundMessage) async {
        guard let line = try? AppServerWireCodec.line(message) else { return }
        await sink(line)
    }

    func threadID(from params: AppServerParams) throws -> UUID {
        let value = try params.requiredString("threadId")
        guard let id = UUID(uuidString: value) else {
            throw AppServerRPCError.invalidParams("threadId must be a UUID")
        }
        return id
    }

    func threadFile(for id: UUID, ephemeral: Bool) -> URL? {
        guard !ephemeral else { return nil }
        return paths.threadsDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    func runner(for record: AppServerThreadRecord) async throws -> AppServerConfiguredRunner {
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
        var runner = try runnerFactory(CLIRuntimeConfiguration(
            request: runRequest,
            appConfig: appConfig,
            paths: paths,
            imageAttachmentStore: attachmentStore,
            environment: environment
        ))
        let mcpContext = try mcpContext(for: record)
        let mcpCatalog = try await mcpRegistry.agentToolCatalog(
            scope: mcpContext.scope,
            configurations: mcpContext.configurations
        )
        runner.additionalToolDefinitions.append(contentsOf: mcpCatalog.definitions)
        let inheritedToolExecution = runner.toolExecutionOverride
        let registry = mcpRegistry
        let scope = mcpContext.scope
        let configurations = mcpContext.configurations
        runner.toolExecutionOverride = { call, workspaceRoot in
            if let route = mcpCatalog.route(forModelName: call.name),
               let configuration = configurations[route.serverName] {
                return await registry.executeAgentTool(
                    scope: scope,
                    configuration: configuration,
                    route: route,
                    argumentsJSON: call.argumentsJSON
                )
            }
            return await inheritedToolExecution?(call, workspaceRoot)
        }
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
            guard let self else {
                return AgentPermissionRequestHookOutcome(notices: notices)
            }
            let appServer = await self.requestApproval(
                for: call,
                reason: reason,
                thread: thread,
                workspaceRoot: workspaceRoot
            )
            notices.append(contentsOf: appServer.notices)
            return AgentPermissionRequestHookOutcome(
                decision: appServer.decision,
                notices: notices
            )
        }
        return AppServerConfiguredRunner(
            runner: runner,
            mcpRoutes: mcpCatalog.routesByModelName
        )
    }
}

private enum AppServerPlatform {
    static var currentOS: String {
        let text = ProcessInfo.processInfo.operatingSystemVersionString.lowercased()
        if text.contains("mac") { return "macos" }
        if text.contains("linux") { return "linux" }
        if text.contains("windows") { return "windows" }
        return "unknown"
    }
}
