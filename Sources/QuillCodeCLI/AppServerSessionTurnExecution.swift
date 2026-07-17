import Foundation
import QuillCodeAgent
import QuillCodeCore

extension AppServerSession {
    func executeTurn(_ threadID: UUID) async {
        guard let initial = activeTurns[threadID] else { return }
        await beginTurnExecution(threadID: threadID, active: initial)

        do {
            try await runTurnLoop(threadID)
        } catch is CancellationError {
            await finishInterruptedTurn(threadID, initial: initial)
        } catch {
            await finishFailedTurn(threadID, initial: initial, error: error)
        }
    }

    private func beginTurnExecution(threadID: UUID, active: ActiveTurn) async {
        await sendThreadStatus(threadID, active: true)
        await sendNotification("turn/started", params: .object([
            "threadId": .string(AppServerThreadProjection.identifier(threadID)),
            "turn": AppServerThreadProjection.turn(
                id: active.id,
                items: [],
                status: "inProgress",
                startedAt: active.startedAt,
                completedAt: nil
            )
        ]))
        await sendUserLifecycle(
            active.currentUserMessage,
            clientID: active.currentInput.clientUserMessageID,
            threadID: threadID,
            turnID: active.id
        )
    }

    private func runTurnLoop(_ threadID: UUID) async throws {
        while true {
            try Task.checkCancellation()
            guard var active = activeTurns[threadID] else { return }
            try checkPersistenceFailure(active)
            active.latestThread = mergingUserShellMessages(
                active.userShellMessages,
                into: active.latestThread
            )
            active.consumedUserShellMessageCount = active.userShellMessages.count
            activeTurns[threadID] = active

            try await runModelTurn(threadID: threadID, active: active)
            guard let settled = try await settledTurn(threadID) else { return }
            if settled.userShellMessages.count > settled.consumedUserShellMessageCount {
                continue
            }
            guard !settled.queuedSteering.isEmpty else {
                await finishTurn(
                    threadID,
                    snapshot: settled.latestThread,
                    status: "completed",
                    error: nil
                )
                return
            }
            try await applyNextSteeringInput(threadID: threadID, active: settled)
        }
    }

    private func runModelTurn(threadID: UUID, active: ActiveTurn) async throws {
        let record = AppServerThreadRecord(thread: active.latestThread, settings: active.settings)
        let configuredRunner = try await runner(for: record)
        guard var configuredActive = activeTurns[threadID] else { return }
        configuredActive.projector.registerMCPRoutes(configuredRunner.mcpRoutes)
        activeTurns[threadID] = configuredActive

        let durableMemories = active.latestThread.memories
        var modelThread = active.latestThread
        let transientContextMessageID = insertEnvironmentContext(
            configuredRunner.modelEnvironmentContext,
            into: &modelThread
        )
        let memoryFeatureEnabled = try await experimentalFeatureEnabled(
            .memories,
            cwd: active.settings.cwd
        )
        let memoriesEnabled = active.settings.effectiveMemoryMode == .enabled
            && memoryFeatureEnabled
        if !memoriesEnabled {
            modelThread.memories = []
        }

        var result = try await configuredRunner.runner.send(
            active.currentInput.text,
            in: modelThread,
            workspaceRoot: configuredRunner.workspaceRoot,
            recordUserMessage: false,
            onProgress: { [weak self] snapshot in
                await self?.receiveTurnProgress(
                    threadID: threadID,
                    snapshot: Self.removingMessage(transientContextMessageID, from: snapshot)
                )
            }
        )
        result.thread = Self.removingMessage(transientContextMessageID, from: result.thread)
        if !memoriesEnabled {
            result.thread.memories = durableMemories
        }
        try Task.checkCancellation()
        guard var latest = activeTurns[threadID] else { return }
        try checkPersistenceFailure(latest)
        let resultThread = preservingModelContext(from: latest.latestThread, in: result.thread)
        latest.latestThread = mergingUserShellMessages(latest.userShellMessages, into: resultThread)
        activeTurns[threadID] = latest
        try await repository.save(AppServerThreadRecord(
            thread: latest.latestThread,
            settings: latest.settings
        ))
    }

    private func settledTurn(_ threadID: UUID) async throws -> ActiveTurn? {
        guard let active = activeTurns[threadID] else { return nil }
        await waitForUserShellCommands(threadID: threadID, turnID: active.id)
        try Task.checkCancellation()
        guard let settled = activeTurns[threadID] else { return nil }
        try checkPersistenceFailure(settled)
        return settled
    }

    private func applyNextSteeringInput(threadID: UUID, active: ActiveTurn) async throws {
        var steered = active
        let next = steered.queuedSteering.removeFirst()
        let message = next.message(turnID: steered.id)
        appendUserMessage(message, to: &steered.latestThread)
        steered.currentInput = next
        steered.currentUserMessage = message
        steered.projector.addUserMessage(message, clientID: next.clientUserMessageID)
        activeTurns[threadID] = steered
        try await repository.save(AppServerThreadRecord(
            thread: steered.latestThread,
            settings: steered.settings
        ))
        await sendUserLifecycle(
            message,
            clientID: next.clientUserMessageID,
            threadID: threadID,
            turnID: steered.id
        )
    }

    private func receiveTurnProgress(threadID: UUID, snapshot: ChatThread) async {
        guard var active = activeTurns[threadID] else { return }
        let snapshot = preservingModelContext(from: active.latestThread, in: snapshot)
        let merged = mergingUserShellMessages(active.userShellMessages, into: snapshot)
        active.latestThread = merged
        let notifications = active.projector.project(merged)
        activeTurns[threadID] = active
        do {
            try await repository.save(AppServerThreadRecord(thread: merged, settings: active.settings))
        } catch {
            guard var failed = activeTurns[threadID] else { return }
            failed.persistenceFailure = error.localizedDescription
            failed.task?.cancel()
            activeTurns[threadID] = failed
        }
        await send(notifications)
    }

    private func finishInterruptedTurn(_ threadID: UUID, initial: ActiveTurn) async {
        if let turnID = activeTurns[threadID]?.id {
            cancelUserShellCommands(threadID: threadID, turnID: turnID)
            await waitForUserShellCommands(threadID: threadID, turnID: turnID)
        }
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
    }

    private func finishFailedTurn(_ threadID: UUID, initial: ActiveTurn, error: Error) async {
        if let turnID = activeTurns[threadID]?.id {
            await waitForUserShellCommands(threadID: threadID, turnID: turnID)
        }
        await finishTurn(
            threadID,
            snapshot: activeTurns[threadID]?.latestThread ?? initial.latestThread,
            status: "failed",
            error: error.localizedDescription
        )
    }

    private func finishTurn(
        _ threadID: UUID,
        snapshot: ChatThread,
        status: String,
        error: String?
    ) async {
        guard var active = activeTurns.removeValue(forKey: threadID) else { return }
        await cancelPendingMCPElicitations(threadID: threadID, turnID: active.id)
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
            await sendTurnError(message, threadID: threadID, turnID: active.id)
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

    private func insertEnvironmentContext(_ context: String?, into thread: inout ChatThread) -> UUID? {
        guard let context else { return nil }
        let message = ChatMessage(role: .system, content: context)
        let insertionIndex = thread.messages.lastIndex { $0.role == .user }
            ?? thread.messages.endIndex
        thread.messages.insert(message, at: insertionIndex)
        return message.id
    }

    private static func removingMessage(_ id: UUID?, from thread: ChatThread) -> ChatThread {
        guard let id else { return thread }
        var sanitized = thread
        sanitized.messages.removeAll { $0.id == id }
        return sanitized
    }

    private func checkPersistenceFailure(_ active: ActiveTurn) throws {
        if let failure = active.persistenceFailure {
            throw AppServerTurnExecutionError.persistence(failure)
        }
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
