import Foundation
import QuillCodeAgent
import QuillCodeCore

extension AppServerSession {
    func startTurn(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try AppServerParams(raw)
        let threadID = try threadID(from: params)
        guard !hasActiveOperation(for: threadID) else {
            throw AppServerRPCError.invalidParams("thread already has an active turn")
        }
        if let outputSchema = params.object["outputSchema"], outputSchema != .null {
            throw AppServerRPCError.invalidParams("outputSchema is not supported yet")
        }
        try rejectUnsupportedValues(["effort", "personality", "serviceTier", "summary"], in: params)

        var record = try await loadRecord(threadID)
        record.settings = try threadSettings(from: params, base: record.settings)
        record.thread.model = try model(from: params, fallback: record.thread.model)
        record.thread.mode = mode(for: record.settings)
        let input = try AppServerTurnInput(
            params: params,
            threadID: threadID,
            attachmentStore: attachmentStore
        )
        let userMessage = input.message()
        appendUserMessage(userMessage, to: &record.thread)
        do {
            try await repository.save(record)
        } catch {
            input.attachments.forEach { try? attachmentStore.remove($0) }
            throw error
        }

        let turnID = UUID().uuidString.lowercased()
        let userItem = AppServerThreadProjection.userMessageItem(
            userMessage,
            clientID: input.clientUserMessageID
        )
        let projector = AppServerProgressProjector(
            threadID: threadID,
            turnID: turnID,
            cwd: record.settings.cwd,
            baseline: record.thread,
            userItem: userItem
        )
        let startedAt = Date()
        activeTurns[threadID] = ActiveTurn(
            id: turnID,
            startedAt: startedAt,
            settings: record.settings,
            latestThread: record.thread,
            currentInput: input,
            currentUserMessage: userMessage,
            queuedSteering: [],
            persistenceFailure: nil,
            task: nil,
            projector: projector
        )
        return .object([
            "turn": AppServerThreadProjection.turn(
                id: turnID,
                items: [],
                status: "inProgress",
                startedAt: startedAt,
                completedAt: nil
            )
        ])
    }

    func steerTurn(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try AppServerParams(raw)
        let threadID = try threadID(from: params)
        if activeCompactions[threadID] != nil {
            throw AppServerRPCError.invalidRequest("active compaction turn is not steerable")
        }
        guard var active = activeTurns[threadID] else {
            throw AppServerRPCError.invalidParams("thread has no active turn")
        }
        let expectedTurnID = try params.requiredString("expectedTurnId")
        guard expectedTurnID == active.id else {
            throw AppServerRPCError.invalidParams("expectedTurnId does not match the active turn")
        }
        let input = try AppServerTurnInput(
            params: params,
            threadID: threadID,
            attachmentStore: attachmentStore
        )
        active.queuedSteering.append(input)
        activeTurns[threadID] = active
        return .object(["turnId": .string(active.id)])
    }

    func interruptTurn(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try AppServerParams(raw)
        let threadID = try threadID(from: params)
        let turnID = try params.requiredString("turnId")
        if let active = activeTurns[threadID] {
            guard turnID == active.id else {
                throw AppServerRPCError.invalidParams("turnId does not match the active turn")
            }
            active.task?.cancel()
            return .object([:])
        }
        if let active = activeCompactions[threadID] {
            guard turnID == active.id else {
                throw AppServerRPCError.invalidParams("turnId does not match the active turn")
            }
            active.task?.cancel()
            return .object([:])
        }
        throw AppServerRPCError.invalidParams("thread has no active turn")
    }

    func launchTurn(_ threadID: UUID) {
        guard var active = activeTurns[threadID], active.task == nil else { return }
        active.task = Task { [weak self] in
            await self?.executeTurn(threadID)
        }
        activeTurns[threadID] = active
    }

    private func executeTurn(_ threadID: UUID) async {
        guard let initial = activeTurns[threadID] else { return }
        await sendThreadStatus(threadID, active: true)
        await sendNotification("turn/started", params: .object([
            "threadId": .string(AppServerThreadProjection.identifier(threadID)),
            "turn": AppServerThreadProjection.turn(
                id: initial.id,
                items: [],
                status: "inProgress",
                startedAt: initial.startedAt,
                completedAt: nil
            )
        ]))
        await sendUserLifecycle(
            initial.currentUserMessage,
            clientID: initial.currentInput.clientUserMessageID,
            threadID: threadID,
            turnID: initial.id
        )

        do {
            while true {
                try Task.checkCancellation()
                guard let active = activeTurns[threadID] else { return }
                if let failure = active.persistenceFailure {
                    throw AppServerTurnExecutionError.persistence(failure)
                }
                let record = AppServerThreadRecord(thread: active.latestThread, settings: active.settings)
                let configuredRunner = try await runner(for: record)
                guard var configuredActive = activeTurns[threadID] else { return }
                configuredActive.projector.registerMCPRoutes(configuredRunner.mcpRoutes)
                activeTurns[threadID] = configuredActive
                let result = try await configuredRunner.runner.send(
                    active.currentInput.text,
                    in: active.latestThread,
                    workspaceRoot: active.settings.cwd,
                    recordUserMessage: false,
                    onProgress: { [weak self] snapshot in
                        await self?.receiveTurnProgress(threadID: threadID, snapshot: snapshot)
                    }
                )
                try Task.checkCancellation()
                guard var latest = activeTurns[threadID] else { return }
                if let failure = latest.persistenceFailure {
                    throw AppServerTurnExecutionError.persistence(failure)
                }
                latest.latestThread = result.thread
                activeTurns[threadID] = latest
                try await repository.save(AppServerThreadRecord(thread: result.thread, settings: latest.settings))

                guard !latest.queuedSteering.isEmpty else {
                    await finishTurn(threadID, snapshot: result.thread, status: "completed", error: nil)
                    return
                }

                let next = latest.queuedSteering.removeFirst()
                let message = next.message()
                appendUserMessage(message, to: &latest.latestThread)
                latest.currentInput = next
                latest.currentUserMessage = message
                latest.projector.addUserMessage(message, clientID: next.clientUserMessageID)
                activeTurns[threadID] = latest
                try await repository.save(AppServerThreadRecord(
                    thread: latest.latestThread,
                    settings: latest.settings
                ))
                await sendUserLifecycle(
                    message,
                    clientID: next.clientUserMessageID,
                    threadID: threadID,
                    turnID: latest.id
                )
            }
        } catch is CancellationError {
            let snapshot = activeTurns[threadID]?.latestThread ?? initial.latestThread
            if let failure = activeTurns[threadID]?.persistenceFailure {
                await finishTurn(
                    threadID,
                    snapshot: snapshot,
                    status: "failed",
                    error: AppServerTurnExecutionError.persistence(failure).localizedDescription
                )
            } else {
                await finishTurn(threadID, snapshot: snapshot, status: "interrupted", error: nil)
            }
        } catch {
            let snapshot = activeTurns[threadID]?.latestThread ?? initial.latestThread
            await finishTurn(
                threadID,
                snapshot: snapshot,
                status: "failed",
                error: error.localizedDescription
            )
        }
    }

    private func receiveTurnProgress(threadID: UUID, snapshot: ChatThread) async {
        guard var active = activeTurns[threadID] else { return }
        active.latestThread = snapshot
        let notifications = active.projector.project(snapshot)
        activeTurns[threadID] = active
        do {
            try await repository.save(AppServerThreadRecord(thread: snapshot, settings: active.settings))
        } catch {
            guard var failed = activeTurns[threadID] else { return }
            failed.persistenceFailure = error.localizedDescription
            failed.task?.cancel()
            activeTurns[threadID] = failed
        }
        await send(notifications)
    }

    private func finishTurn(
        _ threadID: UUID,
        snapshot: ChatThread,
        status: String,
        error: String?
    ) async {
        guard var active = activeTurns.removeValue(forKey: threadID) else { return }
        active.queuedSteering
            .flatMap(\.attachments)
            .forEach { try? attachmentStore.remove($0) }
        let completedAt = Date()
        let notifications = active.projector.finish(snapshot, completedAt: completedAt)
        var completionStatus = status
        var completionError = error
        do {
            try await repository.save(AppServerThreadRecord(thread: snapshot, settings: active.settings))
        } catch {
            let message = "Could not persist the completed turn: \(error.localizedDescription)"
            completionStatus = "failed"
            completionError = message
            await sendNotification("error", params: .object([
                "error": .object([
                    "message": .string(message),
                    "additionalDetails": .null,
                    "codexErrorInfo": .null
                ]),
                "willRetry": .bool(false),
                "threadId": .string(AppServerThreadProjection.identifier(threadID)),
                "turnId": .string(active.id)
            ]))
        }
        await send(notifications)
        await sendNotification("turn/completed", params: .object([
            "threadId": .string(AppServerThreadProjection.identifier(threadID)),
            "turn": AppServerThreadProjection.turn(
                id: active.id,
                items: active.projector.items,
                status: completionStatus,
                startedAt: active.startedAt,
                completedAt: completedAt,
                error: completionError
            )
        ]))
        await sendThreadStatus(threadID, active: false)
    }

    private func sendUserLifecycle(
        _ message: ChatMessage,
        clientID: String?,
        threadID: UUID,
        turnID: String
    ) async {
        let item = AppServerThreadProjection.userMessageItem(message, clientID: clientID)
        let common: [String: CLIJSONValue] = [
            "threadId": .string(AppServerThreadProjection.identifier(threadID)),
            "turnId": .string(turnID),
            "item": item
        ]
        var started = common
        started["startedAtMs"] = .number((message.createdAt.timeIntervalSince1970 * 1_000).rounded())
        await sendNotification("item/started", params: .object(started))
        var completed = common
        completed["completedAtMs"] = .number((Date().timeIntervalSince1970 * 1_000).rounded())
        await sendNotification("item/completed", params: .object(completed))
    }

    func sendThreadStatus(_ threadID: UUID, active: Bool) async {
        let status: CLIJSONValue = active
            ? .object(["type": .string("active"), "activeFlags": .array([])])
            : .object(["type": .string("idle")])
        await sendNotification("thread/status/changed", params: .object([
            "threadId": .string(AppServerThreadProjection.identifier(threadID)),
            "status": status
        ]))
    }

    private func send(_ notifications: [AppServerProjectedNotification]) async {
        for notification in notifications {
            await sendNotification(notification.method, params: notification.params)
        }
    }

    private func appendUserMessage(_ message: ChatMessage, to thread: inout ChatThread) {
        thread.messages.append(message)
        let summary = message.content.isEmpty
            ? "Attached \(message.attachments.count) image\(message.attachments.count == 1 ? "" : "s")"
            : message.content
        thread.events.append(ThreadEvent(kind: .message, summary: summary))
        if thread.title == "New chat" {
            thread.title = message.content.isEmpty
                ? "Image: \(message.attachments.first?.displayName ?? "attachment")"
                : String(message.content.split(whereSeparator: \.isWhitespace).prefix(6).joined(separator: " "))
        }
        thread.updatedAt = Date()
    }
}

private enum AppServerTurnExecutionError: LocalizedError {
    case persistence(String)

    var errorDescription: String? {
        switch self {
        case .persistence(let reason):
            "Turn persistence failed: \(reason)"
        }
    }
}
