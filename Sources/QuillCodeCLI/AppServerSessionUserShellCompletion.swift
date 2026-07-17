import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

extension AppServerSession {
    func consumeRemoteUserShellCommand(
        launch: UserShellLaunch,
        executor: AppServerRemoteEnvironmentToolExecutor,
        startedAt: Date
    ) async {
        let arguments = CLIJSONValue.object(["cmd": .string(launch.command)])
        let argumentsJSON = (try? CLIJSONCodec.encode(arguments))
            .map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        let result = await executor.executeUserShell(
            ToolCall(
                id: launch.itemID,
                name: ToolDefinition.shellRun.name,
                argumentsJSON: argumentsJSON
            ),
            timeoutSeconds: Self.userShellTimeoutSeconds
        )
        var output = ShellOutputAccumulator()
        for delta in [result.stdout, result.stderr] where !delta.isEmpty {
            output.append(delta)
            await sendNotification("item/commandExecution/outputDelta", params: .object([
                "threadId": .string(AppServerThreadProjection.identifier(launch.threadID)),
                "turnId": .string(launch.turnID),
                "itemId": .string(launch.itemID),
                "delta": .string(delta)
            ]))
        }
        await completeUserShellCommand(
            launch: launch,
            result: result,
            streamedOutput: output.text,
            startedAt: startedAt
        )
    }

    func consumeUserShellEvents(
        launch: UserShellLaunch,
        session: ShellStreamingSession,
        startedAt: Date
    ) async {
        var aggregatedOutput = ShellOutputAccumulator()
        for await event in session.events {
            switch event {
            case .stdout(let text), .stderr(let text):
                guard !text.isEmpty else { continue }
                aggregatedOutput.append(text)
                await sendNotification("item/commandExecution/outputDelta", params: .object([
                    "threadId": .string(AppServerThreadProjection.identifier(launch.threadID)),
                    "turnId": .string(launch.turnID),
                    "itemId": .string(launch.itemID),
                    "delta": .string(text)
                ]))
            case .finished(let result):
                await completeUserShellCommand(
                    launch: launch,
                    result: result,
                    streamedOutput: aggregatedOutput.text,
                    startedAt: startedAt
                )
                return
            }
        }

        await completeUserShellCommand(
            launch: launch,
            result: ToolResult(ok: false, error: "Command cancelled."),
            streamedOutput: aggregatedOutput.text,
            startedAt: startedAt
        )
    }

    func completeUserShellCommand(
        launch: UserShellLaunch,
        result: ToolResult,
        streamedOutput: String,
        startedAt: Date
    ) async {
        guard activeUserShellCommands[launch.itemID] != nil else { return }
        defer { activeUserShellCommands.removeValue(forKey: launch.itemID) }
        let completedAt = Date()
        let fallbackOutput = [result.stdout, result.stderr, result.error ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let output = ShellOutputCapper.cap(
            streamedOutput.isEmpty ? fallbackOutput : streamedOutput
        ).text
        let exitCode = result.exitCode ?? (result.ok ? 0 : -1)
        await sendNotification("item/completed", params: userShellLifecycleParams(
            launch: launch,
            item: userShellItem(
                launch: launch,
                status: result.ok ? "completed" : "failed",
                aggregatedOutput: output,
                exitCode: exitCode,
                durationMilliseconds: max(0, completedAt.timeIntervalSince(startedAt) * 1_000)
            ),
            timestampKey: "completedAtMs",
            date: completedAt
        ))

        let feedback = userShellFeedbackMessage(
            launch: launch,
            result: cappedUserShellResult(result),
            completedAt: completedAt
        )
        if await persistUserShellFeedbackInParent(feedback, launch: launch) { return }
        if await persistStandaloneUserShellFeedback(
            feedback,
            launch: launch,
            completedAt: completedAt
        ) { return }
        await persistDetachedUserShellFeedback(feedback, launch: launch)
    }

    private func persistUserShellFeedbackInParent(
        _ feedback: ChatMessage,
        launch: UserShellLaunch
    ) async -> Bool {
        if var active = activeTurns[launch.threadID], active.id == launch.turnID {
            appendUserShellFeedback(
                feedback,
                messages: &active.userShellMessages,
                thread: &active.latestThread
            )
            activeTurns[launch.threadID] = active
            do {
                try await repository.save(AppServerThreadRecord(
                    thread: active.latestThread,
                    settings: active.settings
                ))
            } catch {
                guard var failed = activeTurns[launch.threadID] else { return true }
                failed.persistenceFailure = error.localizedDescription
                failed.task?.cancel()
                activeTurns[launch.threadID] = failed
            }
            return true
        }

        if var active = activeCompactions[launch.threadID], active.id == launch.turnID {
            appendUserShellFeedback(
                feedback,
                messages: &active.userShellMessages,
                thread: &active.latestThread
            )
            activeCompactions[launch.threadID] = active
            await persistUserShellFeedback(
                thread: active.latestThread,
                settings: active.settings,
                parentTask: active.task,
                threadID: launch.threadID,
                operation: .compaction
            )
            return true
        }

        if var active = activeReviews[launch.threadID], active.id == launch.turnID {
            appendUserShellFeedback(
                feedback,
                messages: &active.userShellMessages,
                thread: &active.latestThread
            )
            activeReviews[launch.threadID] = active
            await persistUserShellFeedback(
                thread: active.latestThread,
                settings: active.settings,
                parentTask: active.task,
                threadID: launch.threadID,
                operation: .review
            )
            return true
        }
        return false
    }

    private func appendUserShellFeedback(
        _ feedback: ChatMessage,
        messages: inout [ChatMessage],
        thread: inout ChatThread
    ) {
        messages.append(feedback)
        thread = mergingUserShellMessages(messages, into: thread)
    }

    private func persistStandaloneUserShellFeedback(
        _ feedback: ChatMessage,
        launch: UserShellLaunch,
        completedAt: Date
    ) async -> Bool {
        guard var standalone = activeUserShellTurns[launch.threadID],
              standalone.id == launch.turnID else { return false }
        standalone.latestThread = mergingUserShellMessages(
            [feedback],
            into: standalone.latestThread
        )
        standalone.pendingItemIDs.remove(launch.itemID)
        standalone.latestThread.updatedAt = completedAt
        activeUserShellTurns[launch.threadID] = standalone
        do {
            try await repository.save(AppServerThreadRecord(
                thread: standalone.latestThread,
                settings: standalone.settings
            ))
        } catch {
            standalone.persistenceFailure = error.localizedDescription
            activeUserShellTurns[launch.threadID] = standalone
        }
        if standalone.pendingItemIDs.isEmpty {
            await finishStandaloneUserShellTurn(launch.threadID, completedAt: completedAt)
        }
        return true
    }

    private func finishStandaloneUserShellTurn(_ threadID: UUID, completedAt: Date) async {
        guard var turn = activeUserShellTurns.removeValue(forKey: threadID) else { return }
        turn.settings.userShellTurns = (turn.settings.userShellTurns ?? []) + [
            AppServerUserShellTurnRecord(
                id: turn.id,
                startedAt: turn.startedAt,
                completedAt: completedAt
            )
        ]
        turn.latestThread.updatedAt = completedAt
        var status = turn.interrupted ? "interrupted" : "completed"
        var errorMessage = turn.persistenceFailure
        do {
            try await repository.save(AppServerThreadRecord(
                thread: turn.latestThread,
                settings: turn.settings
            ))
        } catch {
            status = "failed"
            errorMessage = error.localizedDescription
            await sendTurnError(error.localizedDescription, threadID: threadID, turnID: turn.id)
        }
        if errorMessage != nil { status = "failed" }
        await sendNotification("turn/completed", params: .object([
            "threadId": .string(AppServerThreadProjection.identifier(threadID)),
            "turn": AppServerThreadProjection.turn(
                id: turn.id,
                items: [],
                status: status,
                startedAt: turn.startedAt,
                completedAt: completedAt,
                error: errorMessage
            )
        ]))
        await sendThreadStatus(threadID, active: false)
    }

    private func persistDetachedUserShellFeedback(
        _ feedback: ChatMessage,
        launch: UserShellLaunch
    ) async {
        do {
            var record = try await loadRecord(launch.threadID)
            record.thread = mergingUserShellMessages([feedback], into: record.thread)
            try await repository.save(record)
        } catch {
            await sendTurnError(
                "Could not persist user shell output: \(error.localizedDescription)",
                threadID: launch.threadID,
                turnID: launch.turnID
            )
        }
    }

    private enum UserShellParentOperation {
        case compaction
        case review
    }

    private func persistUserShellFeedback(
        thread: ChatThread,
        settings: AppServerThreadSettings,
        parentTask: Task<Void, Never>?,
        threadID: UUID,
        operation: UserShellParentOperation
    ) async {
        do {
            try await repository.save(AppServerThreadRecord(thread: thread, settings: settings))
        } catch {
            switch operation {
            case .compaction:
                guard var failed = activeCompactions[threadID] else { return }
                failed.persistenceFailure = error.localizedDescription
                failed.task?.cancel()
                activeCompactions[threadID] = failed
            case .review:
                guard var failed = activeReviews[threadID] else { return }
                failed.persistenceFailure = error.localizedDescription
                failed.task?.cancel()
                activeReviews[threadID] = failed
            }
            parentTask?.cancel()
        }
    }
}
