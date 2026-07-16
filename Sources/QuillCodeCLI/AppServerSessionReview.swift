import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeReview

struct AppServerReviewStartOutcome: Sendable {
    var result: CLIJSONValue
    var threadID: UUID
}

extension AppServerSession {
    func startReview(_ raw: CLIJSONValue) async throws -> AppServerReviewStartOutcome {
        let params = try AppServerParams(raw)
        let sourceID = try threadID(from: params)
        guard !hasActiveOperation(for: sourceID) else {
            throw AppServerRPCError.invalidParams("thread already has an active turn")
        }

        let delivery = try reviewDelivery(from: params)
        let request = try codeReviewRequest(from: params, delivery: delivery)
        let source = try await loadRecord(sourceID)
        let record: AppServerThreadRecord

        switch delivery {
        case .current:
            record = source
        case .detached:
            guard !source.settings.ephemeral else {
                throw AppServerRPCError.invalidParams(
                    "detached review requires a persisted parent thread"
                )
            }
            var settings = source.settings
            settings.ephemeral = false
            settings.sessionID = source.settings.sessionID ?? sourceID
            settings.forkedFromID = sourceID
            let fork = forkedThread(from: source.thread, sourceID: sourceID)
            record = AppServerThreadRecord(thread: fork, settings: settings)
        }

        let reviewThreadID = record.thread.id
        let turnUUID = UUID()
        let turnID = AppServerThreadProjection.identifier(turnUUID)
        let userMessage = ChatMessage(
            id: turnUUID,
            role: .user,
            content: request.appServerTranscriptPrompt,
            turnID: turnID
        )
        var updated = record
        appendUserMessage(userMessage, to: &updated.thread)
        if delivery == .detached {
            try await repository.create(updated)
            await notifyThreadStarted(updated)
        } else {
            try await repository.save(updated)
        }
        markThreadLoaded(reviewThreadID, subscription: .ifNew)

        let userItem = AppServerThreadProjection.userMessageItem(userMessage)
        let projector = AppServerProgressProjector(
            threadID: reviewThreadID,
            turnID: turnID,
            cwd: updated.settings.cwd,
            baseline: updated.thread,
            userItem: userItem
        )
        activeReviews[reviewThreadID] = ActiveReview(
            id: turnID,
            startedAt: Date(),
            request: request,
            delivery: delivery,
            settings: updated.settings,
            latestThread: updated.thread,
            userMessage: userMessage,
            baselineAssistantIDs: Set(updated.thread.messages.lazy.filter { $0.role == .assistant }.map(\.id)),
            baselineEventIDs: Set(updated.thread.events.map(\.id)),
            persistenceFailure: nil,
            task: nil,
            projector: projector
        )

        return AppServerReviewStartOutcome(
            result: .object([
                "reviewThreadId": .string(AppServerThreadProjection.identifier(reviewThreadID)),
                "turn": AppServerThreadProjection.turn(
                    id: turnID,
                    items: [userItem],
                    status: "inProgress",
                    startedAt: nil,
                    completedAt: nil,
                    itemsView: "notLoaded"
                )
            ]),
            threadID: reviewThreadID
        )
    }

    func launchReview(_ threadID: UUID) {
        guard var active = activeReviews[threadID], active.task == nil else { return }
        active.task = Task { [weak self] in
            await self?.executeReview(threadID)
        }
        activeReviews[threadID] = active
    }

    private func executeReview(_ threadID: UUID) async {
        guard let initial = activeReviews[threadID] else { return }
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
        if initial.delivery == .current {
            await sendReviewModeItem(
                type: "enteredReviewMode",
                review: initial.request.reviewModeLabel,
                threadID: threadID,
                turnID: initial.id
            )
        }
        await sendUserLifecycle(
            initial.userMessage,
            clientID: nil,
            threadID: threadID,
            turnID: initial.id
        )

        do {
            try Task.checkCancellation()
            let record = AppServerThreadRecord(
                thread: initial.latestThread,
                settings: initial.settings
            )
            let configured = try await runner(for: record, includesMCP: false)
            let collector = WorkspaceCodeReviewReportCollector()
            let reviewer = WorkspaceCodeReviewRunner.configure(
                configured.runner,
                reportCollector: collector
            )
            let prompt = WorkspaceCodeReviewPromptBuilder(request: initial.request).prompt()
            let result = try await reviewer.send(
                prompt,
                in: initial.latestThread,
                workspaceRoot: initial.settings.cwd,
                recordUserMessage: false,
                onProgress: { [weak self] snapshot in
                    await self?.receiveReviewProgress(threadID: threadID, snapshot: snapshot)
                }
            )
            try Task.checkCancellation()
            guard result.stopReason == .finished else {
                throw AppServerReviewExecutionError.incomplete(result.stopReason)
            }
            guard let report = await collector.report else {
                throw AppServerReviewExecutionError.missingReport
            }
            guard var active = activeReviews[threadID] else { return }
            if let failure = active.persistenceFailure {
                throw AppServerReviewExecutionError.persistence(failure)
            }
            var snapshot = visibleReviewSnapshot(result.thread, active: active)
            let reviewText = report.transcriptMarkdown
            snapshot.messages.append(ChatMessage(
                role: .assistant,
                content: reviewText,
                turnID: active.id
            ))
            snapshot.events.append(ThreadEvent(kind: .message, summary: report.summary))
            snapshot.updatedAt = Date()
            active.latestThread = snapshot
            activeReviews[threadID] = active
            try await repository.save(AppServerThreadRecord(
                thread: snapshot,
                settings: active.settings
            ))
            await finishReview(
                threadID,
                snapshot: snapshot,
                status: "completed",
                error: nil,
                review: reviewText
            )
        } catch is CancellationError {
            let snapshot = activeReviews[threadID]?.latestThread ?? initial.latestThread
            if let failure = activeReviews[threadID]?.persistenceFailure {
                await finishReview(
                    threadID,
                    snapshot: snapshot,
                    status: "failed",
                    error: AppServerReviewExecutionError.persistence(failure).localizedDescription,
                    review: nil
                )
            } else {
                await finishReview(
                    threadID,
                    snapshot: snapshot,
                    status: "interrupted",
                    error: nil,
                    review: nil
                )
            }
        } catch {
            let snapshot = activeReviews[threadID]?.latestThread ?? initial.latestThread
            await finishReview(
                threadID,
                snapshot: snapshot,
                status: "failed",
                error: error.localizedDescription,
                review: nil
            )
        }
    }

    private func receiveReviewProgress(threadID: UUID, snapshot: ChatThread) async {
        guard var active = activeReviews[threadID] else { return }
        let visible = visibleReviewSnapshot(snapshot, active: active)
        active.latestThread = visible
        let notifications = active.projector.project(visible)
        activeReviews[threadID] = active
        do {
            try await repository.save(AppServerThreadRecord(
                thread: visible,
                settings: active.settings
            ))
        } catch {
            guard var failed = activeReviews[threadID] else { return }
            failed.persistenceFailure = error.localizedDescription
            failed.task?.cancel()
            activeReviews[threadID] = failed
        }
        await send(notifications)
    }

    private func visibleReviewSnapshot(
        _ snapshot: ChatThread,
        active: ActiveReview
    ) -> ChatThread {
        var visible = snapshot
        visible.messages.removeAll {
            $0.role == .assistant && !active.baselineAssistantIDs.contains($0.id)
        }
        visible.events.removeAll {
            $0.kind == .message && !active.baselineEventIDs.contains($0.id)
        }
        return visible
    }

    private func finishReview(
        _ threadID: UUID,
        snapshot: ChatThread,
        status: String,
        error: String?,
        review: String?
    ) async {
        guard var active = activeReviews.removeValue(forKey: threadID) else { return }
        let completedAt = Date()
        let notifications = active.projector.finish(snapshot, completedAt: completedAt)
        var completionStatus = status
        var completionError = error
        if active.delivery == .current {
            await sendReviewModeItem(
                type: "exitedReviewMode",
                review: review ?? "",
                threadID: threadID,
                turnID: active.id
            )
        }
        do {
            try await repository.save(AppServerThreadRecord(
                thread: snapshot,
                settings: active.settings
            ))
        } catch {
            let message = "Could not persist the completed review: \(error.localizedDescription)"
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

    private func sendReviewModeItem(
        type: String,
        review: String,
        threadID: UUID,
        turnID: String
    ) async {
        let item: CLIJSONValue = .object([
            "type": .string(type),
            "id": .string(turnID),
            "review": .string(review)
        ])
        let common: [String: CLIJSONValue] = [
            "threadId": .string(AppServerThreadProjection.identifier(threadID)),
            "turnId": .string(turnID),
            "item": item
        ]
        var started = common
        started["startedAtMs"] = .number((Date().timeIntervalSince1970 * 1_000).rounded())
        await sendNotification("item/started", params: .object(started))
        var completed = common
        completed["completedAtMs"] = .number((Date().timeIntervalSince1970 * 1_000).rounded())
        await sendNotification("item/completed", params: .object(completed))
    }

}

private enum AppServerReviewExecutionError: LocalizedError {
    case incomplete(AgentRunStopReason)
    case missingReport
    case persistence(String)

    var errorDescription: String? {
        switch self {
        case .incomplete(let reason):
            "The code reviewer stopped before completing its report (\(reason))."
        case .missingReport:
            "The code reviewer did not submit the required structured report."
        case .persistence(let reason):
            "Review persistence failed: \(reason)"
        }
    }
}
