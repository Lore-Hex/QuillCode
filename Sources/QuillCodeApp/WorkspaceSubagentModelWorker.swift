import Foundation
import QuillCodeAgent
import QuillCodeCore

/// Runs a single subagent job as a focused, tool-free model turn and returns
/// the model's concise result text. This plugs into
/// `WorkspaceSubagentScheduler`'s worker closure so explicit subagent
/// workflows can be model-backed instead of producing deterministic
/// placeholder summaries.
///
/// The worker only holds the `Sendable` `LLMClient`, so it can run inside the
/// scheduler's task group without capturing the `@MainActor` workspace model.
struct LLMWorkspaceSubagentWorker: Sendable {
    var llm: any LLMClient

    init(llm: any LLMClient) {
        self.llm = llm
    }

    /// Builds a `WorkspaceSubagentScheduler` worker closure backed by `llm`.
    /// The closure only captures the `Sendable` client, so it is safe to run
    /// inside the scheduler's task group.
    static func scheduledWorker(llm: any LLMClient) -> WorkspaceSubagentScheduler.Worker {
        { job in try await LLMWorkspaceSubagentWorker(llm: llm).run(job) }
    }

    func run(_ job: WorkspaceSubagentJob) async throws -> String {
        let prompt = WorkspaceSubagentPromptBuilder.prompt(objective: job.objective, job: job)
        let action = try await llm.nextAction(
            thread: ChatThread(title: "Subagent: \(job.name)"),
            userMessage: prompt,
            tools: []
        )
        switch action {
        case .say(let text):
            let summary = Self.collapsedWhitespace(text)
            return summary.isEmpty ? "Completed \(job.role)" : summary
        case .tool(let call):
            return "Proposed \(call.name)"
        }
    }

    private static func collapsedWhitespace(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
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
        Return exactly one QuillCode action JSON object and no markdown:
        {"type":"say","text":"..."}

        The text must be a concise result of your role's work toward the
        objective: what you inspected or produced, key findings, and any next
        steps. Keep it to a few sentences. Do not include credentials, tokens,
        private keys, or other secrets.

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
