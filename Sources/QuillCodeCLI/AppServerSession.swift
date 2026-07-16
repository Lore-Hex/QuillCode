import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeReview
import QuillCodeTools

typealias AppServerMessageSink = @Sendable (String) async -> Void

struct AppServerConfiguredRunner: Sendable {
    var runner: AgentRunner
    var mcpRoutes: [String: MCPAgentToolRoute]
}

actor AppServerSession {
    static let maximumMessageBytes =
        AppServerImageDataURL.maximumEncodedBytes * ChatAttachment.maximumCountPerTurn
        + 256 * 1_024

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
        var userShellMessages: [ChatMessage]
        var consumedUserShellMessageCount: Int
        var persistenceFailure: String?
        var task: Task<Void, Never>?
        var projector: AppServerProgressProjector
    }

    struct UserShellLaunch: Sendable {
        var threadID: UUID
        var turnID: String
        var itemID: String
        var command: String
        var cwd: URL
        var shellExecutableURL: URL
        var startsStandaloneTurn: Bool
    }

    struct ActiveUserShellTurn: Sendable {
        var id: String
        var startedAt: Date
        var settings: AppServerThreadSettings
        var latestThread: ChatThread
        var pendingItemIDs: Set<String>
        var lifecycleStarted: Bool
        var interrupted: Bool
        var persistenceFailure: String?
    }

    struct ActiveUserShellCommand: Sendable {
        var launch: UserShellLaunch
        var session: ShellStreamingSession?
        var task: Task<Void, Never>?
    }

    struct ActiveCompaction: Sendable {
        var id: String
        var itemID: String
        var startedAt: Date
        var settings: AppServerThreadSettings
        var latestThread: ChatThread
        var userShellMessages: [ChatMessage]
        var persistenceFailure: String?
        var runner: AgentRunner
        var task: Task<Void, Never>?
    }

    struct ActiveReview: Sendable {
        var id: String
        var startedAt: Date
        var request: WorkspaceCodeReviewRequest
        var delivery: CodeReviewDelivery
        var settings: AppServerThreadSettings
        var latestThread: ChatThread
        var userShellMessages: [ChatMessage]
        var userMessage: ChatMessage
        var baselineAssistantIDs: Set<UUID>
        var baselineEventIDs: Set<UUID>
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
    let mcpSecretStore: any MCPSecretStore
    let runnerFactory: CLIAgentRunnerFactory
    let accountLoginStarter: any AppServerAccountLoginStarting
    let mcpOAuthLoginStarter: any AppServerMCPOAuthLoginStarting
    let sink: AppServerMessageSink

    var handshake = HandshakeState.awaitingInitialize
    var optedOutNotifications: Set<String> = []
    var experimentalAPIEnabled = false
    var mcpServerOpenAIFormElicitationEnabled = false
    var activeTurns: [UUID: ActiveTurn] = [:]
    var activeCompactions: [UUID: ActiveCompaction] = [:]
    var activeReviews: [UUID: ActiveReview] = [:]
    var activeRollbacks: Set<UUID> = []
    var activeUserShellTurns: [UUID: ActiveUserShellTurn] = [:]
    var activeUserShellCommands: [String: ActiveUserShellCommand] = [:]
    var loadedThreadIDs: Set<UUID> = []
    var subscribedThreadIDs: Set<UUID> = []
    var outOfBandElicitationCounts: [UUID: UInt64] = [:]
    var processSessions: [String: AppServerProcessSession] = [:]
    var processEventTasks: [String: Task<Void, Never>] = [:]
    var commandExecSessions: [String: AppServerActiveCommandExec] = [:]
    var commandExecEventTasks: [String: Task<Void, Never>] = [:]
    var activeFuzzyFileSearches: [UUID: AppServerActiveFuzzyFileSearch] = [:]
    var fuzzyFileSearchTokens: [String: UUID] = [:]
    var fuzzyFileSearchSessions: [String: AppServerFuzzyFileSearchSession] = [:]
    var nextServerRequestSequence: Int64 = 1
    var pendingApprovals: [AppServerRequestID: AppServerPendingApproval] = [:]
    var pendingMCPElicitations: [AppServerRequestID: AppServerPendingMCPElicitation] = [:]
    var pendingAccountLogins: [String: AppServerPendingAccountLogin] = [:]
    var pendingMCPOAuthLogins: [UUID: AppServerPendingMCPOAuthLogin] = [:]
    var mcpStartupTasks: [UUID: Task<Void, Never>] = [:]
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
        mcpHTTPClient: any MCPHTTPClient = URLSessionMCPHTTPClient(),
        accountLoginStarter: any AppServerAccountLoginStarting = DefaultAppServerAccountLoginStarter(),
        mcpOAuthLoginStarter: (any AppServerMCPOAuthLoginStarting)? = nil,
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
        let mcpSecretStore = AppServerMCPSecretStore(directory: paths.secretsDirectory)
        self.mcpSecretStore = mcpSecretStore
        self.mcpRegistry = AppServerMCPRegistry(
            launcher: mcpLauncher,
            secretStore: mcpSecretStore,
            httpClient: mcpHTTPClient
        )
        self.runnerFactory = runnerFactory
        self.accountLoginStarter = accountLoginStarter
        self.mcpOAuthLoginStarter = mcpOAuthLoginStarter
            ?? DefaultAppServerMCPOAuthLoginStarter(httpClient: mcpHTTPClient)
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
            if await resolveMCPElicitationResponse(id: id, result: result, error: error) {
                return
            }
            resolveApprovalResponse(id: id, result: result, error: error)
        }
    }

    func waitForActiveTurns() async {
        let tasks = activeTurns.values.compactMap(\.task)
            + activeCompactions.values.compactMap(\.task)
            + activeReviews.values.compactMap(\.task)
            + activeUserShellCommands.values.compactMap(\.task)
        for task in tasks { await task.value }
        let fuzzyTasks = activeFuzzyFileSearches.values.map(\.task)
            + fuzzyFileSearchSessions.values.compactMap(\.queryTask)
        for task in fuzzyTasks { await task.value }
        let startupTasks = Array(mcpStartupTasks.values)
        for task in startupTasks { await task.value }
    }

    func hasActiveOperation(for threadID: UUID) -> Bool {
        activeTurns[threadID] != nil
            || activeCompactions[threadID] != nil
            || activeReviews[threadID] != nil
            || activeRollbacks.contains(threadID)
            || activeUserShellTurns[threadID] != nil
    }

    func finishInput() async {
        inputFinished = true
        cancelSkillWatcher()
        cancelAllFileWatches()
        cancelAllAccountLogins()
        cancelAllMCPServerOAuthLogins()
        cancelAllMCPServerStartups()
        await cancelAllFuzzyFileSearches()
        cancelAllUserShellCommands()
        await terminateAllCommandExecProcesses()
        await terminateAllProcesses()
        await resolveAllPendingMCPElicitations()
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

        if method == "fuzzyFileSearch" {
            do {
                try startFuzzyFileSearchRequest(id: id, params: params)
            } catch let error as AppServerRPCError {
                await send(.error(id: id, error: error))
            } catch {
                await send(.error(id: id, error: .internalError(error.localizedDescription)))
            }
            return
        }

        if method == "command/exec" {
            do {
                try startCommandExec(id: id, params: params)
            } catch let error as AppServerRPCError {
                await send(.error(id: id, error: error))
            } catch {
                await send(.error(id: id, error: .internalError(error.localizedDescription)))
            }
            return
        }

        do {
            let result: CLIJSONValue
            var turnToLaunch: UUID?
            var accountAfterResponse: AppServerAccountAfterResponse?
            var mcpOAuthLoginToLaunch: UUID?
            var processToLaunch: String?
            var compactionToLaunch: UUID?
            var reviewToLaunch: UUID?
            var userShellToLaunch: UserShellLaunch?
            var mcpStartupThreadToLaunch: UUID?
            var notificationsAfterResponse: [AppServerDeferredNotification] = []
            switch method {
            case "model/list": result = try await listModels(params)
            case "modelProvider/capabilities/read": result = try modelProviderCapabilities(params)
            case "account/read": result = try readAccount(params)
            case "account/login/start":
                let outcome = try startAccountLogin(params)
                result = outcome.result
                accountAfterResponse = outcome.afterResponse
            case "account/login/cancel":
                let outcome = try cancelAccountLogin(params)
                result = outcome.result
                accountAfterResponse = outcome.afterResponse
            case "account/logout":
                let outcome = try logoutAccount(params)
                result = outcome.result
                accountAfterResponse = outcome.afterResponse
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
            case "config/mcpServer/reload", "mcpServer/refresh":
                result = try await reloadMCPServers(params, method: method)
            case "mcpServer/tool/call": result = try await callMCPServerTool(params)
            case "mcpServer/resource/read": result = try await readMCPResource(params)
            case "mcpServer/oauth/login":
                let outcome = try await startMCPServerOAuthLogin(params)
                result = outcome.result
                mcpOAuthLoginToLaunch = outcome.loginID
            case "fs/readFile": result = try readFile(params)
            case "fs/writeFile": result = try writeFile(params)
            case "fs/createDirectory": result = try createDirectory(params)
            case "fs/getMetadata": result = try fileMetadata(params)
            case "fs/readDirectory": result = try readDirectory(params)
            case "fs/remove": result = try removeFileSystemItem(params)
            case "fs/copy": result = try copyFileSystemItem(params)
            case "fs/watch": result = try startFileWatch(params)
            case "fs/unwatch": result = try await stopFileWatch(params)
            case "process/spawn":
                processToLaunch = try spawnProcess(params)
                result = .object([:])
            case "process/writeStdin": result = try writeProcessStdin(params)
            case "process/resizePty": result = try resizeProcessPTY(params)
            case "process/kill": result = try killProcess(params)
            case "command/exec/write": result = try writeCommandExec(params)
            case "command/exec/resize": result = try resizeCommandExec(params)
            case "command/exec/terminate": result = try terminateCommandExec(params)
            case "fuzzyFileSearch/sessionStart": result = try startFuzzyFileSearchSession(params)
            case "fuzzyFileSearch/sessionUpdate": result = try updateFuzzyFileSearchSession(params)
            case "fuzzyFileSearch/sessionStop": result = try stopFuzzyFileSearchSession(params)
            case "thread/start":
                let outcome = try await startThread(params)
                result = outcome.result
                mcpStartupThreadToLaunch = outcome.threadID
            case "thread/resume":
                let outcome = try await resumeThread(params)
                result = outcome.result
                mcpStartupThreadToLaunch = outcome.threadID
            case "thread/fork":
                let outcome = try await forkThread(params)
                result = outcome.result
                mcpStartupThreadToLaunch = outcome.threadID
            case "thread/list": result = try await listThreads(params)
            case "thread/search": result = try await searchThreads(params)
            case "thread/loaded/list": result = try listLoadedThreads(params)
            case "thread/read": result = try await readThread(params)
            case "thread/turns/list": result = try await listThreadTurns(params)
            case "thread/turns/items/list":
                throw AppServerRPCError.methodNotSupported(method)
            case "thread/shellCommand":
                userShellToLaunch = try await startUserShellCommand(params)
                result = .object([:])
            case "thread/unsubscribe": result = try unsubscribeThread(params)
            case "thread/increment_elicitation": result = try await incrementThreadElicitation(params)
            case "thread/decrement_elicitation": result = try await decrementThreadElicitation(params)
            case "thread/metadata/update": result = try await updateThreadMetadata(params)
            case "thread/settings/update":
                let outcome = try await updateThreadSettings(params)
                result = outcome.result
                if let notification = outcome.notification {
                    notificationsAfterResponse.append(notification)
                }
            case "thread/memoryMode/set": result = try await setThreadMemoryMode(params)
            case "thread/archive": result = try await setThreadArchived(params, archived: true)
            case "thread/unarchive": result = try await setThreadArchived(params, archived: false)
            case "thread/delete": result = try await deleteThread(params)
            case "thread/name/set": result = try await setThreadName(params)
            case "thread/goal/set": result = try await setThreadGoal(params)
            case "thread/goal/get": result = try await getThreadGoal(params)
            case "thread/goal/clear": result = try await clearThreadGoal(params)
            case "thread/compact/start":
                compactionToLaunch = try await startThreadCompaction(params)
                result = .object([:])
            case "thread/rollback": result = try await rollbackThread(params)
            case "turn/start":
                result = try await startTurn(params)
                turnToLaunch = try threadID(from: AppServerParams(params))
            case "turn/steer": result = try await steerTurn(params)
            case "turn/interrupt": result = try await interruptTurn(params)
            case "review/start":
                let outcome = try await startReview(params)
                result = outcome.result
                reviewToLaunch = outcome.threadID
            default:
                throw AppServerRPCError.methodNotFound(method)
            }
            await send(.response(id: id, result: result))
            for notification in notificationsAfterResponse {
                await sendNotification(notification.method, params: notification.params)
            }
            if let accountAfterResponse {
                await performAccountAfterResponse(accountAfterResponse)
            }
            if let mcpOAuthLoginToLaunch {
                launchMCPServerOAuthLogin(mcpOAuthLoginToLaunch)
            }
            if let processToLaunch { launchProcessEventStream(processToLaunch) }
            if let mcpStartupThreadToLaunch { launchOptionalMCPServerStartups(for: mcpStartupThreadToLaunch) }
            if let compactionToLaunch { launchThreadCompaction(compactionToLaunch) }
            if let turnToLaunch { launchTurn(turnToLaunch) }
            if let reviewToLaunch { launchReview(reviewToLaunch) }
            if let userShellToLaunch { await launchUserShellCommand(userShellToLaunch) }
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
                let capabilityParams = try AppServerParams(.object(capabilities))
                let values = try capabilityParams.optionalArray("optOutNotificationMethods") ?? []
                optedOutNotifications = Set(try values.map { value in
                    guard let method = value.stringValue else {
                        throw AppServerRPCError.invalidParams(
                            "capabilities.optOutNotificationMethods must contain strings"
                        )
                    }
                    return method
                })
                if let experimental = capabilityParams.object["experimentalApi"] {
                    guard let enabled = experimental.boolValue else {
                        throw AppServerRPCError.invalidParams(
                            "capabilities.experimentalApi must be a boolean"
                        )
                    }
                    experimentalAPIEnabled = enabled
                }
                if let openAIForm = capabilityParams.object["mcpServerOpenaiFormElicitation"] {
                    guard let enabled = openAIForm.boolValue else {
                        throw AppServerRPCError.invalidParams(
                            "capabilities.mcpServerOpenaiFormElicitation must be a boolean"
                        )
                    }
                    mcpServerOpenAIFormElicitationEnabled = enabled
                }
            }
            await mcpRegistry.configure(clientCapabilities: .init(
                supportsFormElicitation: true,
                supportsOpenAIFormElicitation: mcpServerOpenAIFormElicitationEnabled
            ))
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
        if method.hasPrefix("turn/") || method.hasPrefix("item/"),
           let rawThreadID = params.objectValue?["threadId"]?.stringValue,
           let threadID = UUID(uuidString: rawThreadID),
           !subscribedThreadIDs.contains(threadID) {
            return
        }
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

    func runner(
        for record: AppServerThreadRecord,
        includesMCP: Bool = true
    ) async throws -> AppServerConfiguredRunner {
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
            appConfig: record.settings.runtimeAppConfig ?? appConfig,
            paths: paths,
            imageAttachmentStore: attachmentStore,
            environment: environment
        )
        var runner = runtime.applyingInvocationPolicy(to: try runnerFactory(runtime))
        var mcpRoutes: [String: MCPAgentToolRoute] = [:]
        if includesMCP {
            let mcpContext = try mcpContext(for: record)
            let mcpAdapter = try await MCPAgentRunnerAdapter.prepare(
                registry: mcpRegistry,
                scope: mcpContext.scope,
                configurations: mcpContext.configurations,
                elicitationHandler: { [weak self] serverName, request in
                    guard let self else { return .cancel() }
                    return await self.requestTurnMCPElicitation(
                        serverName: serverName,
                        request: request,
                        threadID: record.thread.id
                    )
                }
            )
            runner = mcpAdapter.configure(runner)
            mcpRoutes = mcpAdapter.routesByModelName
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
            mcpRoutes: mcpRoutes
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
