import Foundation
import QuillCodeAgent
import QuillCodeCore

extension AppServerSession {
    func startThreadCompaction(_ raw: CLIJSONValue) async throws -> UUID {
        let params = try AppServerParams(raw)
        let rawThreadID = try params.requiredString("threadId")
        guard let threadID = UUID(uuidString: rawThreadID) else {
            throw AppServerRPCError.invalidRequest("invalid thread id: \(rawThreadID)")
        }
        guard !hasActiveOperation(for: threadID) else {
            throw AppServerRPCError.invalidRequest("thread already has an active turn")
        }

        let record: AppServerThreadRecord
        do {
            record = try await repository.load(threadID)
        } catch {
            throw AppServerRPCError.invalidRequest("thread not found: \(rawThreadID)")
        }
        let configured = try await runner(for: record)
        guard configured.runner.compaction != nil else {
            throw AppServerRPCError.internalError(
                "failed to start compaction: the configured agent runner has no compaction policy"
            )
        }

        activeCompactions[threadID] = ActiveCompaction(
            id: UUID().uuidString.lowercased(),
            itemID: UUID().uuidString.lowercased(),
            startedAt: Date(),
            settings: record.settings,
            latestThread: record.thread,
            persistenceFailure: nil,
            runner: configured.runner,
            task: nil
        )
        return threadID
    }

    func launchThreadCompaction(_ threadID: UUID) {
        guard var active = activeCompactions[threadID], active.task == nil else { return }
        active.task = Task { [weak self] in
            await self?.executeThreadCompaction(threadID)
        }
        activeCompactions[threadID] = active
    }

    private func executeThreadCompaction(_ threadID: UUID) async {
        guard let initial = activeCompactions[threadID] else { return }
        let item = contextCompactionItem(id: initial.itemID)
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
        await sendCompactionItemLifecycle(
            "item/started",
            timestampKey: "startedAtMs",
            at: initial.startedAt,
            item: item,
            threadID: threadID,
            turnID: initial.id
        )

        do {
            var thread = initial.latestThread
            _ = try await initial.runner.compactManually(
                thread: &thread,
                workspaceRoot: initial.settings.cwd,
                onProgress: { [weak self] snapshot in
                    await self?.receiveCompactionProgress(threadID: threadID, snapshot: snapshot)
                }
            )
            try Task.checkCancellation()
            if let failure = activeCompactions[threadID]?.persistenceFailure {
                throw AppServerCompactionExecutionError.persistence(failure)
            }
            try await repository.save(AppServerThreadRecord(thread: thread, settings: initial.settings))
            await finishThreadCompaction(threadID, snapshot: thread, status: "completed", error: nil)
        } catch is CancellationError {
            let snapshot = activeCompactions[threadID]?.latestThread ?? initial.latestThread
            if let failure = activeCompactions[threadID]?.persistenceFailure {
                await finishThreadCompaction(
                    threadID,
                    snapshot: snapshot,
                    status: "failed",
                    error: AppServerCompactionExecutionError.persistence(failure).localizedDescription
                )
            } else {
                await finishThreadCompaction(
                    threadID,
                    snapshot: snapshot,
                    status: "interrupted",
                    error: nil
                )
            }
        } catch {
            let snapshot = activeCompactions[threadID]?.latestThread ?? initial.latestThread
            await finishThreadCompaction(
                threadID,
                snapshot: snapshot,
                status: "failed",
                error: error.localizedDescription
            )
        }
    }

    private func receiveCompactionProgress(threadID: UUID, snapshot: ChatThread) async {
        guard var active = activeCompactions[threadID] else { return }
        active.latestThread = snapshot
        activeCompactions[threadID] = active
        do {
            try await repository.save(AppServerThreadRecord(thread: snapshot, settings: active.settings))
        } catch {
            guard var failed = activeCompactions[threadID] else { return }
            failed.persistenceFailure = error.localizedDescription
            failed.task?.cancel()
            activeCompactions[threadID] = failed
        }
    }

    private func finishThreadCompaction(
        _ threadID: UUID,
        snapshot: ChatThread,
        status: String,
        error: String?
    ) async {
        guard let active = activeCompactions.removeValue(forKey: threadID) else { return }
        let completedAt = Date()
        let item = contextCompactionItem(id: active.itemID)
        var completionStatus = status
        var completionError = error
        do {
            try await repository.save(AppServerThreadRecord(thread: snapshot, settings: active.settings))
        } catch {
            completionStatus = "failed"
            completionError = AppServerCompactionExecutionError.persistence(
                error.localizedDescription
            ).localizedDescription
        }
        await sendCompactionItemLifecycle(
            "item/completed",
            timestampKey: "completedAtMs",
            at: completedAt,
            item: item,
            threadID: threadID,
            turnID: active.id
        )
        await sendNotification("turn/completed", params: .object([
            "threadId": .string(AppServerThreadProjection.identifier(threadID)),
            "turn": AppServerThreadProjection.turn(
                id: active.id,
                items: [item],
                status: completionStatus,
                startedAt: active.startedAt,
                completedAt: completedAt,
                error: completionError
            )
        ]))
        await sendThreadStatus(threadID, active: false)
    }

    private func contextCompactionItem(id: String) -> CLIJSONValue {
        .object(["type": .string("contextCompaction"), "id": .string(id)])
    }

    private func sendCompactionItemLifecycle(
        _ method: String,
        timestampKey: String,
        at date: Date,
        item: CLIJSONValue,
        threadID: UUID,
        turnID: String
    ) async {
        await sendNotification(method, params: .object([
            "threadId": .string(AppServerThreadProjection.identifier(threadID)),
            "turnId": .string(turnID),
            "item": item,
            timestampKey: .number((date.timeIntervalSince1970 * 1_000).rounded())
        ]))
    }
}

private enum AppServerCompactionExecutionError: LocalizedError {
    case persistence(String)

    var errorDescription: String? {
        switch self {
        case .persistence(let reason):
            "Compaction persistence failed: \(reason)"
        }
    }
}
