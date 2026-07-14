import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence

/// Executes a delegated job through the same configured agent path as a normal chat turn. Each
/// worker owns a fresh, ephemeral transcript while inheriting the parent chat's project, worktree,
/// model, mode, instructions, memories, goal, tools, and remote routing.
struct AgentWorkspaceSubagentWorker: Sendable {
    let sessionFactory: WorkspaceAgentSendSessionFactory
    let parentThread: ChatThread
    let threadStore: SubagentThreadStore?
    let approvalPayloadStore: SubagentApprovalPayloadStore?

    init(
        sessionFactory: WorkspaceAgentSendSessionFactory,
        parentThread: ChatThread,
        threadStore: SubagentThreadStore? = nil,
        approvalPayloadStore: SubagentApprovalPayloadStore? = nil
    ) {
        self.sessionFactory = sessionFactory
        self.parentThread = parentThread
        self.threadStore = threadStore
        self.approvalPayloadStore = approvalPayloadStore
    }

    static func scheduledWorker(
        sessionFactory: WorkspaceAgentSendSessionFactory,
        parentThread: ChatThread,
        threadStore: SubagentThreadStore? = nil,
        approvalPayloadStore: SubagentApprovalPayloadStore? = nil
    ) -> WorkspaceSubagentScheduler.DetailedWorker {
        let worker = AgentWorkspaceSubagentWorker(
            sessionFactory: sessionFactory,
            parentThread: parentThread,
            threadStore: threadStore,
            approvalPayloadStore: approvalPayloadStore
        )
        return { job in await worker.runScheduled(job) }
    }

    /// Migration-only worker for whole-session records. It deliberately lets an approval pause
    /// escape so the legacy adapter can journal the exact continuation in its protected store.
    static func legacyScheduledWorker(
        sessionFactory: WorkspaceAgentSendSessionFactory,
        parentThread: ChatThread
    ) -> WorkspaceSubagentScheduler.DetailedWorker {
        let worker = AgentWorkspaceSubagentWorker(
            sessionFactory: sessionFactory,
            parentThread: parentThread
        )
        return { job in try await worker.runWithTranscript(job) }
    }

    func run(_ job: WorkspaceSubagentJob) async throws -> String {
        let result = try await execute(job)
        if result.status == .awaitingApproval {
            throw WorkspaceSubagentWorkerError.safetyBlocked(result.summary)
        }
        return result.summary
    }

    func runWithTranscript(_ job: WorkspaceSubagentJob) async throws -> WorkspaceSubagentWorkerResult {
        try await execute(job)
    }

    /// Production scheduler entry point. Unlike the direct test-facing `run`, this converts a
    /// stopped worker into a terminal result with its latest captured transcript, so failures and
    /// cancellations remain inspectable instead of disappearing with the task.
    private func runScheduled(_ job: WorkspaceSubagentJob) async -> WorkspaceSubagentWorkerResult {
        let initialThread = WorkspaceSubagentThreadBuilder.thread(for: job, inheriting: parentThread)
        let capture = WorkspaceSubagentTranscriptCapture(initialThread)
        do {
            return try await execute(job) { thread in
                await capture.update(thread)
                try? threadStore?.save(thread)
            }
        } catch is CancellationError {
            let thread = await capture.latest()
            try? threadStore?.save(thread)
            return result(
                status: .cancelled,
                summary: "Cancelled",
                transcript: WorkspaceSubagentTranscriptBuilder.entries(from: thread)
            )
        } catch {
            let thread = await capture.latest()
            try? threadStore?.save(thread)
            return result(
                status: .failed,
                summary: WorkspaceContextSummarySanitizer.diagnostic(from: error.localizedDescription),
                transcript: WorkspaceSubagentTranscriptBuilder.entries(from: thread)
            )
        }
    }

    private func execute(
        _ job: WorkspaceSubagentJob,
        onProgress: AgentRunProgressHandler? = nil
    ) async throws -> WorkspaceSubagentWorkerResult {
        let prompt = WorkspaceSubagentPromptBuilder.prompt(objective: job.objective, job: job)
        let thread = WorkspaceSubagentThreadBuilder.thread(
            for: job,
            inheriting: parentThread
        )
        // Recursive delegation stays under the scheduler's bounded spawn protocol. A child model
        // cannot start an independent scheduler tree that would bypass this run's depth/job limits.
        let session = sessionFactory.makeSubagentSession(
            prompt: prompt,
            thread: thread,
            parentThread: parentThread,
            job: job,
            runsStartHook: true
        )
        let result = try await AgentRunRetryScope.$threadID.withValue(thread.id) {
            try await session.run(onProgress: onProgress)
        }
        try threadStore?.save(result.thread)

        if let pendingApproval = result.pendingApproval {
            guard let approvalPayloadStore else {
                throw WorkspaceSubagentApprovalPause(
                    prompt: prompt,
                    thread: result.thread,
                    pendingApproval: pendingApproval
                )
            }
            let approval = pendingApproval.request
            let reason = WorkspaceContextSummarySanitizer.diagnostic(from: approval.reason)
            let payloadKey = UUID()
            let payload = try WorkspaceSubagentApprovalPayloadResolver.payload(
                for: approval,
                heldToolCall: pendingApproval.heldToolCall
            )
            try approvalPayloadStore.save(payload, key: payloadKey)
            return self.result(
                status: .awaitingApproval,
                summary: reason,
                pendingApproval: SubagentPendingApproval(
                    requestID: approval.id,
                    generation: 1,
                    payloadKey: payloadKey,
                    createdAt: Date(),
                    phase: .pending
                ),
                transcript: WorkspaceSubagentTranscriptBuilder.entries(from: result.thread)
            )
        }

        return Self.workerResult(from: result.thread, fallbackRole: job.role)
    }

    func resume(
        _ pause: WorkspaceSubagentApprovalPause,
        job: WorkspaceSubagentJob,
        onProgress: AgentRunProgressHandler? = nil
    ) async throws -> WorkspaceSubagentWorkerResult {
        let result = try await AgentRunRetryScope.$threadID.withValue(pause.thread.id) {
            try await sessionFactory.makeSubagentSession(
                prompt: pause.prompt,
                thread: pause.thread,
                parentThread: parentThread,
                job: job,
                recordsUserMessage: false,
                runsStartHook: false
            ).resumeApproved(pause.pendingApproval, onProgress: onProgress)
        }
        if let pendingApproval = result.pendingApproval {
            throw WorkspaceSubagentApprovalPause(
                prompt: pause.prompt,
                thread: result.thread,
                pendingApproval: pendingApproval
            )
        }
        return Self.workerResult(from: result.thread, fallbackRole: job.role)
    }

    private static func workerResult(
        from thread: ChatThread,
        fallbackRole: String
    ) -> WorkspaceSubagentWorkerResult {
        let assistantText = thread.messages.last(where: { $0.role == .assistant })?.content ?? ""
        let summary = WorkspaceContextSummarySanitizer.summary(from: assistantText)
            .map(WorkspaceContextSummaryTextBounds.collapsedSingleLine)
        let finalSummary = summary.flatMap { $0.isEmpty ? nil : $0 } ?? "Completed \(fallbackRole)"
        return WorkspaceSubagentWorkerResult(
            status: .completed,
            summary: finalSummary,
            transcript: WorkspaceSubagentTranscriptBuilder.entries(from: thread)
        )
    }

    private func result(
        status: SubagentStatus,
        summary: String,
        pendingApproval: SubagentPendingApproval? = nil,
        transcript: [SubagentTranscriptEntry] = []
    ) -> WorkspaceSubagentWorkerResult {
        WorkspaceSubagentWorkerResult(
            status: status,
            summary: summary,
            pendingApproval: pendingApproval,
            transcript: transcript
        )
    }
}

private actor WorkspaceSubagentTranscriptCapture {
    private var thread: ChatThread

    init(_ thread: ChatThread) {
        self.thread = thread
    }

    func update(_ thread: ChatThread) {
        self.thread = thread
    }

    func latest() -> ChatThread {
        thread
    }
}

private enum WorkspaceSubagentThreadBuilder {
    static func thread(for job: WorkspaceSubagentJob, inheriting parent: ChatThread) -> ChatThread {
        ChatThread(
            id: job.childThreadID,
            title: "Subagent: \(job.name)",
            projectID: parent.projectID,
            mode: parent.mode,
            model: parent.model,
            goal: parent.goal,
            instructions: parent.instructions,
            memories: parent.memories,
            worktree: parent.worktree
        )
    }
}

private enum WorkspaceSubagentWorkerError: LocalizedError {
    case safetyBlocked(String)

    var errorDescription: String? {
        switch self {
        case .safetyBlocked(let reason):
            return "Safety review blocked delegated work: \(reason)"
        }
    }
}

enum WorkspaceSubagentPromptBuilder {
    static func prompt(objective: String, job: WorkspaceSubagentJob) -> String {
        """
        You are the "\(job.name)" subagent collaborating on this objective:
        \(objective)

        Your role: \(job.role)
        \(groupPathSection(for: job))
        \(priorResultsSection(job.priorResults))
        Work autonomously with the available tools. Inspect the real workspace,
        perform the role's requested actions, and verify the result before you
        finish. Do not merely announce what you intend to do. Respect the
        workspace boundary and the active safety mode.

        Finish with a concise result: what you inspected or produced, key
        findings, verification, and any remaining next steps. Keep it to a few
        sentences. Do not include credentials, tokens, private keys, or other
        secrets.

        If — and only if — your work genuinely splits into independent sub-tasks
        that a separate subagent should own, you may delegate by adding one or
        more markers of the form [[DELEGATE: short name | what that subagent
        should do]] anywhere in your text. Each marker becomes a child subagent
        that runs after you and sees your result. Use this sparingly; most roles
        need no delegation, so prefer to just do the work yourself.
        """
    }

    private static func groupPathSection(for job: WorkspaceSubagentJob) -> String {
        let groupPath = job.groupPath
        guard !groupPath.isEmpty else { return "" }
        return """

        Nested plan path: \((groupPath + [job.name.components(separatedBy: "/").last ?? job.name]).joined(separator: " / "))
        Parent group: \(groupPath.joined(separator: " / "))

        """
    }

    /// Renders the results of completed prerequisite workers so a dependent job can build on them.
    /// Returns an empty string when the job has no prerequisites, keeping root-job prompts unchanged.
    private static func priorResultsSection(_ priorResults: [WorkspaceSubagentPriorResult]) -> String {
        guard !priorResults.isEmpty else { return "" }
        let lines = priorResults.map { "- \($0.name): \($0.summary)" }.joined(separator: "\n")
        return """

        Results from the prerequisite subagents you depend on:
        \(lines)

        """
    }
}
