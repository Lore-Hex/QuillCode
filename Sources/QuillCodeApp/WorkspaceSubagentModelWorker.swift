import Foundation
import QuillCodeAgent
import QuillCodeCore

/// Executes a delegated job through the same configured agent path as a normal chat turn. Each
/// worker owns a fresh, ephemeral transcript while inheriting the parent chat's project, worktree,
/// model, mode, instructions, memories, goal, tools, and remote routing.
struct AgentWorkspaceSubagentWorker: Sendable {
    let sessionFactory: WorkspaceAgentSendSessionFactory
    let parentThread: ChatThread

    static func scheduledWorker(
        sessionFactory: WorkspaceAgentSendSessionFactory,
        parentThread: ChatThread
    ) -> WorkspaceSubagentScheduler.Worker {
        let worker = AgentWorkspaceSubagentWorker(
            sessionFactory: sessionFactory,
            parentThread: parentThread
        )
        return { job in try await worker.runWithTranscript(job) }
    }

    func run(_ job: WorkspaceSubagentJob) async throws -> String {
        try await runWithTranscript(job).summary
    }

    func runWithTranscript(_ job: WorkspaceSubagentJob) async throws -> WorkspaceSubagentWorkerResult {
        let prompt = WorkspaceSubagentPromptBuilder.prompt(objective: job.objective, job: job)
        let thread = WorkspaceSubagentThreadBuilder.thread(
            for: job,
            inheriting: parentThread
        )
        let session = sessionFactory.makeSession(prompt: prompt, thread: thread)
        let result = try await AgentRunRetryScope.$threadID.withValue(thread.id) {
            try await session.run()
        }

        if let approval = WorkspaceApprovalActionPlanner.undecidedRequests(in: result.thread).last {
            throw WorkspaceSubagentWorkerError.safetyBlocked(
                WorkspaceContextSummarySanitizer.diagnostic(from: approval.reason)
            )
        }

        let assistantText = result.thread.messages.last(where: { $0.role == .assistant })?.content ?? ""
        let summary = WorkspaceContextSummarySanitizer.summary(from: assistantText)
            .map(WorkspaceContextSummaryTextBounds.collapsedSingleLine)
        let finalSummary = summary.flatMap { $0.isEmpty ? nil : $0 } ?? "Completed \(job.role)"
        return WorkspaceSubagentWorkerResult(
            summary: finalSummary,
            transcript: WorkspaceSubagentTranscriptBuilder.entries(from: result.thread)
        )
    }
}

private enum WorkspaceSubagentThreadBuilder {
    static func thread(for job: WorkspaceSubagentJob, inheriting parent: ChatThread) -> ChatThread {
        ChatThread(
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
