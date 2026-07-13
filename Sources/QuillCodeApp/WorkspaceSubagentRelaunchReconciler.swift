import Foundation
import QuillCodeCore
import QuillCodePersistence

struct WorkspaceSubagentRelaunchReconciliation: Sendable, Hashable {
    var threads: [ChatThread]
    var changedThreadIDs: Set<UUID>
}

enum WorkspaceSubagentRelaunchReconciler {
    static func reconcile(
        _ originalThreads: [ChatThread],
        childStore: SubagentThreadStore,
        payloadStore: SubagentApprovalPayloadStore,
        now: Date = Date()
    ) -> WorkspaceSubagentRelaunchReconciliation {
        var threads = originalThreads
        var changedThreadIDs = Set<UUID>()

        for threadIndex in threads.indices {
            var changed = false
            for runIndex in threads[threadIndex].subagentRuns.indices {
                for workerIndex in threads[threadIndex].subagentRuns[runIndex].workers.indices {
                    var worker = threads[threadIndex].subagentRuns[runIndex].workers[workerIndex]
                    var workerChanged = false

                    if worker.status == .running {
                        if let pending = worker.pendingApproval {
                            try? payloadStore.delete(pending.payloadKey)
                        }
                        interrupt(&worker, now: now)
                        workerChanged = true
                    } else if let pending = worker.pendingApproval {
                        let isValidPendingGate = worker.status == .awaitingApproval
                            && pending.phase == .pending
                            && hasMatchingUndecidedRequest(
                                worker: worker,
                                pending: pending,
                                childStore: childStore,
                                payloadStore: payloadStore
                            )
                        if !isValidPendingGate {
                            try? payloadStore.delete(pending.payloadKey)
                            interrupt(&worker, now: now)
                            workerChanged = true
                        }
                    } else if worker.status == .awaitingApproval {
                        interrupt(&worker, now: now)
                        workerChanged = true
                    }

                    if workerChanged {
                        threads[threadIndex].subagentRuns[runIndex].workers[workerIndex] = worker
                        threads[threadIndex].subagentRuns[runIndex].finishedAt = nil
                        threads[threadIndex].subagentRuns[runIndex].updatedAt = now
                        changed = true
                    }
                }
            }
            if changed {
                threads[threadIndex].updatedAt = now
                changedThreadIDs.insert(threads[threadIndex].id)
            }
        }

        return WorkspaceSubagentRelaunchReconciliation(
            threads: threads,
            changedThreadIDs: changedThreadIDs
        )
    }

    private static func hasMatchingUndecidedRequest(
        worker: SubagentWorkerRecord,
        pending: SubagentPendingApproval,
        childStore: SubagentThreadStore,
        payloadStore: SubagentApprovalPayloadStore
    ) -> Bool {
        guard let child = try? childStore.load(worker.childThreadID),
              let request = WorkspaceApprovalActionPlanner.pendingRequest(id: pending.requestID, in: child),
              let payload = try? payloadStore.load(pending.payloadKey)
        else { return false }
        return WorkspaceSubagentApprovalPayloadResolver.matches(payload, request.toolCall)
    }

    private static func interrupt(_ worker: inout SubagentWorkerRecord, now: Date) {
        worker.status = .interrupted
        worker.summary = "Interrupted before completion"
        worker.pendingApproval = nil
        worker.updatedAt = now
    }
}
