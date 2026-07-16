import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

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

        let record = try await loadRecord(threadID)
        markThreadLoaded(threadID, subscription: .ifNew)
        let itemID = UUID().uuidString.lowercased()
        let shellExecutableURL = userShellExecutableURL()

        let launch: UserShellLaunch
        if let active = activeTurns[threadID] {
            launch = UserShellLaunch(
                threadID: threadID,
                turnID: active.id,
                itemID: itemID,
                command: command,
                cwd: active.settings.cwd,
                shellExecutableURL: shellExecutableURL,
                startsStandaloneTurn: false
            )
        } else if let active = activeCompactions[threadID] {
            launch = UserShellLaunch(
                threadID: threadID,
                turnID: active.id,
                itemID: itemID,
                command: command,
                cwd: active.settings.cwd,
                shellExecutableURL: shellExecutableURL,
                startsStandaloneTurn: false
            )
        } else if let active = activeReviews[threadID] {
            launch = UserShellLaunch(
                threadID: threadID,
                turnID: active.id,
                itemID: itemID,
                command: command,
                cwd: active.settings.cwd,
                shellExecutableURL: shellExecutableURL,
                startsStandaloneTurn: false
            )
        } else if var active = activeUserShellTurns[threadID] {
            active.pendingItemIDs.insert(itemID)
            activeUserShellTurns[threadID] = active
            launch = UserShellLaunch(
                threadID: threadID,
                turnID: active.id,
                itemID: itemID,
                command: command,
                cwd: active.settings.cwd,
                shellExecutableURL: shellExecutableURL,
                startsStandaloneTurn: false
            )
        } else {
            guard !activeRollbacks.contains(threadID) else {
                throw AppServerRPCError.invalidRequest(
                    "the active thread operation cannot accept a user shell command"
                )
            }
            let turnID = UUID().uuidString.lowercased()
            activeUserShellTurns[threadID] = ActiveUserShellTurn(
                id: turnID,
                startedAt: Date(),
                settings: record.settings,
                latestThread: record.thread,
                pendingItemIDs: [itemID],
                lifecycleStarted: false,
                interrupted: false,
                persistenceFailure: nil
            )
            launch = UserShellLaunch(
                threadID: threadID,
                turnID: turnID,
                itemID: itemID,
                command: command,
                cwd: record.settings.cwd,
                shellExecutableURL: shellExecutableURL,
                startsStandaloneTurn: true
            )
        }

        activeUserShellCommands[itemID] = ActiveUserShellCommand(
            launch: launch,
            session: nil,
            task: nil
        )
        return launch
    }

    func launchUserShellCommand(_ launch: UserShellLaunch) async {
        guard var commandState = activeUserShellCommands[launch.itemID] else { return }
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
        if inputFinished { session.cancel() }

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

        let task = Task { [weak self] in
            guard let self else { return }
            await self.consumeUserShellEvents(
                launch: launch,
                session: session,
                startedAt: startedAt
            )
        }
        guard var launched = activeUserShellCommands[launch.itemID] else {
            session.cancel()
            return
        }
        launched.task = task
        activeUserShellCommands[launch.itemID] = launched
    }

    func cancelUserShellCommands(threadID: UUID, turnID: String) {
        if var standalone = activeUserShellTurns[threadID], standalone.id == turnID {
            standalone.interrupted = true
            activeUserShellTurns[threadID] = standalone
        }
        for command in activeUserShellCommands.values
        where command.launch.threadID == threadID && command.launch.turnID == turnID {
            command.session?.cancel()
        }
    }

    func cancelAllUserShellCommands() {
        for (threadID, var turn) in activeUserShellTurns {
            turn.interrupted = true
            activeUserShellTurns[threadID] = turn
        }
        for command in activeUserShellCommands.values {
            command.session?.cancel()
        }
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
}
