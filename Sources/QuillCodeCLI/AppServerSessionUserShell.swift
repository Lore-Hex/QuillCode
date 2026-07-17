import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

private enum AppServerUserShellDestination {
    case turn(id: String, settings: AppServerThreadSettings)
    case compaction(id: String, settings: AppServerThreadSettings)
    case review(id: String, settings: AppServerThreadSettings)
    case existingStandalone(id: String, settings: AppServerThreadSettings)
    case newStandalone(id: String, record: AppServerThreadRecord)

    var turnID: String {
        switch self {
        case .turn(let id, _),
             .compaction(let id, _),
             .review(let id, _),
             .existingStandalone(let id, _),
             .newStandalone(let id, _):
            id
        }
    }

    var settings: AppServerThreadSettings {
        switch self {
        case .turn(_, let settings),
             .compaction(_, let settings),
             .review(_, let settings),
             .existingStandalone(_, let settings):
            settings
        case .newStandalone(_, let record):
            record.settings
        }
    }

    var startsStandaloneTurn: Bool {
        if case .newStandalone = self { return true }
        return false
    }
}

extension AppServerSession {
    static let userShellTimeoutSeconds: TimeInterval = 60 * 60

    func startUserShellCommand(_ raw: CLIJSONValue) async throws -> UserShellLaunch {
        let params = try AppServerParams(raw)
        let threadID = try threadID(from: params)
        guard let commandValue = params.object["command"] else {
            throw AppServerRPCError.invalidRequest("Invalid request: missing field `command`")
        }
        guard let rawCommand = commandValue.stringValue else {
            throw AppServerRPCError.invalidRequest(
                "Invalid request: invalid type for `command`, expected a string"
            )
        }
        let command = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            throw AppServerRPCError.invalidRequest("command must not be empty")
        }

        _ = try await loadRecord(threadID)
        markThreadLoaded(threadID, subscription: .ifNew)
        let itemID = UUID().uuidString.lowercased()

        while true {
            let destination = try await userShellDestination(threadID: threadID)
            let launch = try await userShellLaunch(
                threadID: threadID,
                turnID: destination.turnID,
                itemID: itemID,
                command: command,
                settings: destination.settings,
                startsStandaloneTurn: destination.startsStandaloneTurn
            )
            guard try await commitUserShellDestination(
                destination,
                threadID: threadID,
                itemID: itemID
            ) else {
                continue
            }
            activeUserShellCommands[itemID] = ActiveUserShellCommand(
                launch: launch,
                session: nil,
                remoteSession: nil,
                task: nil,
                terminationRequested: false
            )
            return launch
        }
    }

    func launchUserShellCommand(_ launch: UserShellLaunch) async {
        guard var commandState = activeUserShellCommands[launch.itemID] else { return }

        if launch.startsStandaloneTurn,
           var turn = activeUserShellTurns[launch.threadID],
           !turn.lifecycleStarted {
            turn.lifecycleStarted = true
            activeUserShellTurns[launch.threadID] = turn
            await sendThreadStatus(launch.threadID, active: true)
            await sendNotification("turn/started", params: .object([
                "threadId": .string(AppServerThreadProjection.identifier(launch.threadID)),
                "turn": AppServerThreadProjection.turn(
                    id: launch.turnID,
                    items: [],
                    status: "inProgress",
                    startedAt: turn.startedAt,
                    completedAt: nil
                )
            ]))
        }

        let startedAt = Date()
        await sendNotification("item/started", params: userShellLifecycleParams(
            launch: launch,
            item: userShellItem(
                launch: launch,
                status: "inProgress",
                aggregatedOutput: nil,
                exitCode: nil,
                durationMilliseconds: nil
            ),
            timestampKey: "startedAtMs",
            date: startedAt
        ))

        if let remoteExecutor = launch.remoteExecutor {
            await launchRemoteUserShellCommand(
                launch: launch,
                executor: remoteExecutor,
                startedAt: startedAt
            )
            return
        }

        let request = ShellExecutionRequest(
            command: launch.command,
            cwd: launch.cwd,
            timeoutSeconds: Self.userShellTimeoutSeconds,
            environment: environment.isEmpty ? nil : environment,
            shellExecutableURL: launch.shellExecutableURL
        )
        let session = ShellToolExecutor().startStreamingSession(request)
        commandState.session = session
        activeUserShellCommands[launch.itemID] = commandState
        let task = Task { [weak self] in
            guard let self else { return }
            await self.consumeUserShellEvents(
                launch: launch,
                session: session,
                startedAt: startedAt
            )
        }
        guard var launched = activeUserShellCommands[launch.itemID] else {
            task.cancel()
            return
        }
        launched.task = task
        activeUserShellCommands[launch.itemID] = launched
        if launched.terminationRequested || inputFinished {
            launched.session?.cancel()
            task.cancel()
        }
    }

    private func launchRemoteUserShellCommand(
        launch: UserShellLaunch,
        executor: AppServerRemoteEnvironmentToolExecutor,
        startedAt: Date
    ) async {
        guard let processID = launch.remoteProcessID else {
            await completeUserShellCommand(
                launch: launch,
                result: ToolResult(ok: false, error: "Remote command has no process id."),
                streamedOutput: "",
                startedAt: startedAt
            )
            return
        }

        do {
            let session = try await executor.startUserShell(
                command: launch.command,
                processID: processID,
                timeoutSeconds: Self.userShellTimeoutSeconds
            )
            guard var command = activeUserShellCommands[launch.itemID] else {
                await session.terminate()
                return
            }
            command.remoteSession = session
            let task = Task { [weak self] in
                guard let self else { return }
                await self.consumeRemoteUserShellCommand(
                    launch: launch,
                    session: session,
                    startedAt: startedAt
                )
            }
            command.task = task
            let shouldTerminate = command.terminationRequested || inputFinished
            activeUserShellCommands[launch.itemID] = command
            if shouldTerminate {
                await session.terminate()
                task.cancel()
            }
        } catch {
            let cancelled = activeUserShellCommands[launch.itemID]?.terminationRequested == true
                || error is CancellationError
            await completeUserShellCommand(
                launch: launch,
                result: ToolResult(
                    ok: false,
                    error: cancelled ? "Command cancelled." : Self.userShellErrorMessage(error)
                ),
                streamedOutput: "",
                startedAt: startedAt
            )
        }
    }

    func cancelUserShellCommands(threadID: UUID, turnID: String) async {
        if var standalone = activeUserShellTurns[threadID], standalone.id == turnID {
            standalone.interrupted = true
            activeUserShellTurns[threadID] = standalone
        }
        await requestUserShellCommandTermination {
            $0.launch.threadID == threadID && $0.launch.turnID == turnID
        }
    }

    func cancelAllUserShellCommands() async {
        for (threadID, var turn) in activeUserShellTurns {
            turn.interrupted = true
            activeUserShellTurns[threadID] = turn
        }
        await requestUserShellCommandTermination { _ in true }
    }

    @discardableResult
    func requestUserShellCommandTermination(
        where predicate: (ActiveUserShellCommand) -> Bool
    ) async -> Int {
        let itemIDs = activeUserShellCommands.compactMap { itemID, command in
            !command.terminationRequested && predicate(command) ? itemID : nil
        }
        var remoteSessions: [AppServerRemoteProcessSession] = []
        var tasks: [Task<Void, Never>] = []
        for itemID in itemIDs {
            guard var command = activeUserShellCommands[itemID] else { continue }
            command.terminationRequested = true
            activeUserShellCommands[itemID] = command
            command.session?.cancel()
            if let remoteSession = command.remoteSession { remoteSessions.append(remoteSession) }
            if let task = command.task { tasks.append(task) }
        }
        for session in remoteSessions { await session.terminate() }
        for task in tasks { task.cancel() }
        return itemIDs.count
    }

    func waitForUserShellCommands(threadID: UUID, turnID: String) async {
        while true {
            let pending = activeUserShellCommands.values.filter {
                $0.launch.threadID == threadID && $0.launch.turnID == turnID
            }
            guard !pending.isEmpty else { return }
            let tasks = pending.compactMap(\.task)
            if tasks.isEmpty {
                await Task.yield()
                continue
            }
            for task in tasks { await task.value }
        }
    }

    func mergingUserShellMessages(_ messages: [ChatMessage], into thread: ChatThread) -> ChatThread {
        guard !messages.isEmpty else { return thread }
        var merged = thread
        let existing = Set(merged.messages.map(\.id))
        merged.messages.append(contentsOf: messages.filter { !existing.contains($0.id) })
        merged.messages.sort { $0.createdAt < $1.createdAt }
        if let latest = messages.map(\.createdAt).max() {
            merged.updatedAt = max(merged.updatedAt, latest)
        }
        return merged
    }

    func userShellExecutableURL() -> URL {
        let fallback = URL(fileURLWithPath: "/bin/sh")
        guard let path = environment["SHELL"],
              NSString(string: path).isAbsolutePath,
              FileManager.default.isExecutableFile(atPath: path) else {
            return fallback
        }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    private static func userShellErrorMessage(_ error: any Error) -> String {
        if let localized = error as? any LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            return description
        }
        return String(describing: error)
    }

    private func userShellLaunch(
        threadID: UUID,
        turnID: String,
        itemID: String,
        command: String,
        settings: AppServerThreadSettings,
        startsStandaloneTurn: Bool
    ) async throws -> UserShellLaunch {
        let selected = try await executionEnvironment(for: settings)
        switch selected.access {
        case .disabled:
            throw AppServerRPCError.invalidRequest(
                "environment access is disabled for this thread"
            )
        case .local:
            let executable = userShellExecutableURL()
            return UserShellLaunch(
                threadID: threadID,
                turnID: turnID,
                itemID: itemID,
                command: command,
                cwd: selected.workspaceRoot,
                shellExecutableURL: executable,
                shellExecutablePath: executable.path,
                remoteExecutor: nil,
                remoteProcessID: nil,
                startsStandaloneTurn: startsStandaloneTurn
            )
        case .remote(let executor):
            let workspace = await executor.logicalWorkspaceURL
            let shellPath = executor.environmentInfo.shell.path
            return UserShellLaunch(
                threadID: threadID,
                turnID: turnID,
                itemID: itemID,
                command: command,
                cwd: workspace,
                shellExecutableURL: URL(fileURLWithPath: shellPath),
                shellExecutablePath: shellPath,
                remoteExecutor: executor,
                remoteProcessID: reserveRemoteBackgroundProcessID(),
                startsStandaloneTurn: startsStandaloneTurn
            )
        }
    }

    private func reserveRemoteBackgroundProcessID() -> Int32 {
        let activeIDs = Set(activeUserShellCommands.values.compactMap { command -> Int32? in
            command.launch.remoteProcessID ?? command.session?.processIdentifier
        })
        var candidate = nextRemoteBackgroundProcessID
        while activeIDs.contains(candidate) {
            candidate = candidate == 1 ? Int32.max : candidate - 1
        }
        nextRemoteBackgroundProcessID = candidate == 1 ? Int32.max : candidate - 1
        return candidate
    }

    private func userShellDestination(
        threadID: UUID
    ) async throws -> AppServerUserShellDestination {
        if let active = activeTurns[threadID] {
            return .turn(id: active.id, settings: active.settings)
        }
        if let active = activeCompactions[threadID] {
            return .compaction(id: active.id, settings: active.settings)
        }
        if let active = activeReviews[threadID] {
            return .review(id: active.id, settings: active.settings)
        }
        if let active = activeUserShellTurns[threadID] {
            return .existingStandalone(id: active.id, settings: active.settings)
        }
        guard !activeRollbacks.contains(threadID) else {
            throw AppServerRPCError.invalidRequest(
                "the active thread operation cannot accept a user shell command"
            )
        }
        return .newStandalone(
            id: UUID().uuidString.lowercased(),
            record: try await loadRecord(threadID)
        )
    }

    private func commitUserShellDestination(
        _ destination: AppServerUserShellDestination,
        threadID: UUID,
        itemID: String
    ) async throws -> Bool {
        switch destination {
        case .turn(let id, _):
            return activeTurns[threadID]?.id == id
        case .compaction(let id, _):
            return activeCompactions[threadID]?.id == id
        case .review(let id, _):
            return activeReviews[threadID]?.id == id
        case .existingStandalone(let id, _):
            guard var active = activeUserShellTurns[threadID], active.id == id else {
                return false
            }
            active.pendingItemIDs.insert(itemID)
            activeUserShellTurns[threadID] = active
            return true
        case .newStandalone(let id, let record):
            let latest = try await loadRecord(threadID)
            guard latest.settings == record.settings,
                  activeTurns[threadID] == nil,
                  activeCompactions[threadID] == nil,
                  activeReviews[threadID] == nil,
                  activeUserShellTurns[threadID] == nil,
                  !activeRollbacks.contains(threadID) else {
                return false
            }
            activeUserShellTurns[threadID] = ActiveUserShellTurn(
                id: id,
                startedAt: Date(),
                settings: latest.settings,
                latestThread: latest.thread,
                pendingItemIDs: [itemID],
                lifecycleStarted: false,
                interrupted: false,
                persistenceFailure: nil
            )
            return true
        }
    }
}
