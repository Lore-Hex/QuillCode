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
        record.settings = try threadSettings(
            from: params,
            base: record.settings,
            requirements: try managedRequirements()
        )
        try await applyEnvironmentSelection(from: params, to: &record.settings)
        record.thread.model = try model(from: params, fallback: record.thread.model)
        record.thread.mode = mode(for: record.settings)
        let input = try AppServerTurnInput(
            params: params,
            threadID: threadID,
            attachmentStore: attachmentStore,
            richInputResolver: richTurnInputResolver(cwd: record.settings.cwd)
        )
        let turnID = UUID().uuidString.lowercased()
        let userMessage = input.message(turnID: turnID)
        appendUserMessage(userMessage, to: &record.thread)
        do {
            try await repository.save(record)
        } catch {
            input.attachments.forEach { try? attachmentStore.remove($0) }
            throw error
        }
        markThreadLoaded(threadID, subscription: .ifNew)

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
            userShellMessages: [],
            consumedUserShellMessageCount: 0,
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
            attachmentStore: attachmentStore,
            richInputResolver: richTurnInputResolver(cwd: active.settings.cwd)
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
            await cancelPendingMCPElicitations(threadID: threadID, turnID: active.id)
            cancelUserShellCommands(threadID: threadID, turnID: active.id)
            active.task?.cancel()
            return .object([:])
        }
        if let active = activeUserShellTurns[threadID] {
            guard turnID == active.id else {
                throw AppServerRPCError.invalidParams("turnId does not match the active turn")
            }
            cancelUserShellCommands(threadID: threadID, turnID: active.id)
            return .object([:])
        }
        if let active = activeCompactions[threadID] {
            guard turnID == active.id else {
                throw AppServerRPCError.invalidParams("turnId does not match the active turn")
            }
            cancelUserShellCommands(threadID: threadID, turnID: active.id)
            active.task?.cancel()
            return .object([:])
        }
        if let active = activeReviews[threadID] {
            guard turnID == active.id else {
                throw AppServerRPCError.invalidParams("turnId does not match the active turn")
            }
            cancelUserShellCommands(threadID: threadID, turnID: active.id)
            active.task?.cancel()
            return .object([:])
        }
        if let active = activeGuardianRetries[threadID] {
            guard turnID == active.turnID else {
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

    func sendUserLifecycle(
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

    func sendTurnError(_ message: String, threadID: UUID, turnID: String) async {
        await sendNotification("error", params: .object([
            "error": .object([
                "message": .string(message),
                "additionalDetails": .null,
                "codexErrorInfo": .null
            ]),
            "willRetry": .bool(false),
            "threadId": .string(AppServerThreadProjection.identifier(threadID)),
            "turnId": .string(turnID)
        ]))
    }

    func send(_ notifications: [AppServerProjectedNotification]) async {
        for notification in notifications {
            await sendNotification(notification.method, params: notification.params)
        }
    }

    func appendUserMessage(_ message: ChatMessage, to thread: inout ChatThread) {
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
