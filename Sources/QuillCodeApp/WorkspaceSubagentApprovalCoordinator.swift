import Foundation
import QuillCodeAgent
import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
    func resolveSubagentApproval(
        _ command: WorkspaceSubagentApprovalCommand,
        workspaceRoot: URL
    ) async {
        let resolutionID = "\(command.runID):\(command.requestID)"
        guard resolvingSubagentApprovals.insert(resolutionID).inserted else { return }
        defer { resolvingSubagentApprovals.remove(resolutionID) }

        guard let store = subagentSessionStore else {
            reportSubagentApprovalFailure("Delegated approval state is unavailable.")
            return
        }

        do {
            var record = try store.load(command.runID)
            guard let parentThread = root.threads.first(where: { $0.id == record.parentThreadID }),
                  let pauseKey = record.state.pausedWorkers.first(where: {
                      $0.value.pendingApproval.request.id == command.requestID
                  })?.key,
                  var pause = record.state.pausedWorkers[pauseKey],
                  let itemIndex = record.state.items.firstIndex(where: {
                      $0.approvalGate?.requestID == command.requestID
                  })
            else {
                reportSubagentApprovalFailure("This delegated approval is no longer pending.")
                return
            }

            switch command.action {
            case .approve:
                record.state.items[itemIndex].status = .running
                record.state.items[itemIndex].summary = "Continuing after approval"
                record.state.items[itemIndex].approvalGate = nil
                record.updatedAt = Date()
                try store.save(record)
                recordSubagentProgress(
                    SubagentProgressUpdate(
                        objective: record.state.objective,
                        subagents: record.state.items
                    ),
                    threadID: record.parentThreadID
                )
                refreshTopBar(agentStatus: TopBarAgentStatusLabel.running)

                let runProject = parentThread.projectID.flatMap(project(id:))
                let sessionFactory = agentSendSessionFactory(
                    workspaceRoot: workspaceRoot,
                    runProject: runProject
                )
                let worker = AgentWorkspaceSubagentWorker(
                    sessionFactory: sessionFactory,
                    parentThread: parentThread
                )
                let progress: AgentRunProgressHandler = { snapshot in
                    guard var durable = try? store.load(command.runID),
                          var durablePause = durable.state.pausedWorkers[pauseKey]
                    else { return }
                    durablePause.thread = snapshot
                    durable.state.pausedWorkers[pauseKey] = durablePause
                    durable.updatedAt = Date()
                    try? store.save(durable)
                }

                do {
                    let workerResult = try await worker.resume(
                        pause,
                        fallbackRole: record.state.items[itemIndex].role,
                        onProgress: progress
                    )
                    record = (try? store.load(command.runID)) ?? record
                    record.state.pausedWorkers.removeValue(forKey: pauseKey)
                    record.state.items[itemIndex].status = .completed
                    record.state.items[itemIndex].summary = workerResult.summary
                    record.state.items[itemIndex].transcript = workerResult.transcript
                    record.state.items[itemIndex].approvalGate = nil
                } catch let nextPause as WorkspaceSubagentApprovalPause {
                    record = (try? store.load(command.runID)) ?? record
                    pause = nextPause
                    record.state.pausedWorkers[pauseKey] = pause
                    applyApprovalPause(
                        pause,
                        runID: record.state.id,
                        to: &record.state.items[itemIndex]
                    )
                } catch is CancellationError {
                    record = (try? store.load(command.runID)) ?? record
                    record.state.pausedWorkers.removeValue(forKey: pauseKey)
                    record.state.items[itemIndex].status = .cancelled
                    record.state.items[itemIndex].summary = "Cancelled"
                    record.state.items[itemIndex].approvalGate = nil
                } catch {
                    record = (try? store.load(command.runID)) ?? record
                    record.state.pausedWorkers.removeValue(forKey: pauseKey)
                    record.state.items[itemIndex].status = .failed
                    record.state.items[itemIndex].summary = boundedSubagentFailure(error.localizedDescription)
                    record.state.items[itemIndex].approvalGate = nil
                }

            case .reject:
                record.state.pausedWorkers.removeValue(forKey: pauseKey)
                appendRejectedDecision(to: &pause)
                record.state.items[itemIndex].status = .cancelled
                record.state.items[itemIndex].summary = "Skipped by user"
                record.state.items[itemIndex].transcript = WorkspaceSubagentTranscriptBuilder.entries(from: pause.thread)
                record.state.items[itemIndex].approvalGate = nil
            }

            record.updatedAt = Date()
            try store.save(record)
            let update = SubagentProgressUpdate(
                objective: record.state.objective,
                subagents: record.state.items
            )

            guard record.state.pausedWorkers.isEmpty else {
                recordSubagentProgress(update, threadID: record.parentThreadID)
                refreshTopBar(agentStatus: TopBarAgentStatusLabel.review)
                return
            }

            let latestParent = root.threads.first(where: { $0.id == record.parentThreadID }) ?? parentThread
            let runProject = latestParent.projectID.flatMap(project(id:))
            let scheduler = subagentSchedulerOverride ?? WorkspaceSubagentScheduler(
                worker: AgentWorkspaceSubagentWorker.scheduledWorker(
                    sessionFactory: agentSendSessionFactory(
                        workspaceRoot: workspaceRoot,
                        runProject: runProject
                    ),
                    parentThread: latestParent
                )
            )
            let parentThreadID = record.parentThreadID
            let result = await scheduler.run(
                state: record.state,
                progress: { [weak self] progressUpdate in
                    await self?.recordSubagentProgress(progressUpdate, threadID: parentThreadID)
                },
                spawn: { _, summary in
                    WorkspaceSubagentSpawnDirectiveParser.parse(summary)
                }
            )
            finishSubagentSchedulerResult(result, parentThreadID: parentThreadID)
        } catch {
            reportSubagentApprovalFailure("Could not continue delegated work: \(error.localizedDescription)")
        }
    }

    private func applyApprovalPause(
        _ pause: WorkspaceSubagentApprovalPause,
        runID: String,
        to item: inout SubagentProgressItem
    ) {
        let request = pause.pendingApproval.request
        item.status = .awaitingApproval
        item.summary = boundedSubagentFailure(
            "Approval needed for \(request.toolCall.name): \(request.reason)"
        )
        item.transcript = WorkspaceSubagentTranscriptBuilder.entries(from: pause.thread)
        item.approvalGate = SubagentApprovalGate(
            runID: runID,
            requestID: request.id,
            toolName: request.toolCall.name,
            reason: request.reason
        )
    }

    private func appendRejectedDecision(to pause: inout WorkspaceSubagentApprovalPause) {
        let request = pause.pendingApproval.request
        let decision = ApprovalDecision(
            requestID: request.id,
            verdict: .deny,
            rationale: "Skipped delegated worker action.",
            reviewTelemetry: request.reviewTelemetry
        )
        pause.thread.events.append(.init(
            kind: .approvalDecided,
            summary: "deny: \(decision.rationale)",
            payloadJSON: try? JSONHelpers.encodePretty(decision)
        ))
        let notice = "Skipped \(request.toolCall.name)."
        pause.thread.messages.append(.init(role: .assistant, content: notice))
        pause.thread.events.append(.init(kind: .message, summary: notice))
        pause.thread.updatedAt = Date()
    }

    private func reportSubagentApprovalFailure(_ message: String) {
        setLastError(message)
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.failed)
    }

    private func boundedSubagentFailure(_ message: String) -> String {
        let normalized = message
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard normalized.count > 220 else { return normalized }
        return String(normalized.prefix(220)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
