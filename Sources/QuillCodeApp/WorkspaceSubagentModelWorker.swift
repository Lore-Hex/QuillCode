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
                summary: Self.cancellationSummary(from: thread),
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

        return Self.workerResult(
            from: result.thread,
            fallbackRole: job.role,
            stopReason: result.stopReason
        )
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
        return Self.workerResult(
            from: result.thread,
            fallbackRole: job.role,
            stopReason: result.stopReason
        )
    }

    private static func workerResult(
        from thread: ChatThread,
        fallbackRole: String,
        stopReason: AgentRunStopReason
    ) -> WorkspaceSubagentWorkerResult {
        let assistantText = thread.messages.last(where: { $0.role == .assistant })?.content ?? ""
        let summary = WorkspaceContextSummarySanitizer.summary(from: assistantText)
            .map(WorkspaceContextSummaryTextBounds.collapsedSingleLine)
        let finalSummary = summary.flatMap { $0.isEmpty ? nil : $0 } ?? "Completed \(fallbackRole)"
        guard stopReason == .finished else {
            let stopSummary = stopSummary(for: stopReason)
            let summaryWithEvidence = Self.appendingEvidence(
                WorkspaceSubagentEvidenceDigest.summary(from: thread),
                to: finalSummary
            )
            return WorkspaceSubagentWorkerResult(
                status: .failed,
                summary: "\(stopSummary) Latest evidence: \(summaryWithEvidence)",
                transcript: WorkspaceSubagentTranscriptBuilder.entries(from: thread)
            )
        }
        let status = WorkspaceSubagentTerminalStatus.status(for: assistantText)
        let summaryWithEvidence = status == .failed
            ? Self.appendingEvidence(WorkspaceSubagentEvidenceDigest.summary(from: thread), to: finalSummary)
            : finalSummary
        return WorkspaceSubagentWorkerResult(
            status: status,
            summary: summaryWithEvidence,
            transcript: WorkspaceSubagentTranscriptBuilder.entries(from: thread)
        )
    }

    static func cancellationSummary(from thread: ChatThread) -> String {
        let latestNote = thread.messages
            .last(where: { $0.role == .assistant })
            .flatMap { WorkspaceContextSummarySanitizer.summary(from: $0.content) }
            .map(WorkspaceContextSummaryTextBounds.collapsedSingleLine)
            .flatMap { $0.isEmpty ? nil : $0 }
        guard let latestNote else {
            let prefix = "Cancelled at the delegation deadline before the worker produced a final summary."
            return appendingEvidence(WorkspaceSubagentEvidenceDigest.summary(from: thread), to: prefix)
        }
        let prefix = "Cancelled at the delegation deadline. Latest worker note: \(latestNote)"
        return appendingEvidence(WorkspaceSubagentEvidenceDigest.summary(from: thread), to: prefix)
    }

    private static func appendingEvidence(_ evidence: String?, to summary: String) -> String {
        guard let evidence, !evidence.isEmpty else { return summary }
        return "\(summary)\n\nRecovered grounded evidence:\n\(evidence)"
    }

    private static func stopSummary(for stopReason: AgentRunStopReason) -> String {
        switch stopReason {
        case .finished:
            return "Completed."
        case .toolStepCeilingExhausted(let limit):
            return "Stopped at the delegated \(limit)-step tool limit before finishing."
        case .flailDetected(let reason):
            let diagnostic = WorkspaceContextSummarySanitizer.diagnostic(from: reason)
            return "Stopped after repeated non-progress: \(diagnostic)."
        case .spendFuseApprovalRequired:
            return "Stopped because the delegated spend fuse requires approval."
        case .approvalRequired:
            return "Stopped because a delegated action requires approval."
        case .autoReviewCircuitBreaker(let reason):
            let diagnostic = WorkspaceContextSummarySanitizer.diagnostic(from: reason)
            return "Stopped after repeated safety denials: \(diagnostic)."
        }
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

        Do not finish while any recoverable part of your assigned role remains.
        Use the available tools now instead of returning a plan or "next steps".
        For research work, preserve each useful fact with its source URL as soon
        as you find it. Prefer direct evidence gathering over building helper
        scripts unless the role explicitly requires automation. If two focused
        fetches of the same page produce no new evidence, switch to another
        source or extraction method instead of rewriting the query again.
        End with COMPLETE: followed by a concise result only after every role
        requirement is satisfied and verified. If the role is genuinely blocked
        after concrete attempts, end with BLOCKED: followed by the exact blocker,
        what you tried, and the usable evidence you did gather. Do not include
        credentials, tokens, private keys, or other secrets.

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

enum WorkspaceSubagentTerminalStatus {
    static func status(for text: String) -> SubagentStatus {
        let lines = text
            .lowercased()
            .split(whereSeparator: \.isNewline)
            .map { line in
                line.trimmingCharacters(
                    in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "#*_`- "))
                )
            }
        if lines.contains(where: { $0.hasPrefix("blocked:") || $0 == "blocked" }) {
            return .blocked
        }
        if hasRecoverableWorkMarker(in: text.lowercased()) {
            return .failed
        }
        return .completed
    }

    private static func hasRecoverableWorkMarker(in text: String) -> Bool {
        let unfinishedStateMarkers = [
            "starting research", "not yet obtained", "not yet confirmed",
            "not fully complete", "i need to gather", "i need to verify", "now i need ",
        ]
        if unfinishedStateMarkers.contains(where: text.contains) {
            return true
        }
        if let range = text.range(of: "i need ") {
            let remainder = text[range.upperBound...].prefix(120)
            if remainder.contains(" to complete") || remainder.contains(" to finish") {
                return true
            }
        }
        if text.contains("still need to ") {
            return true
        }
        let clauses = text
            .split(whereSeparator: {
                $0 == "." || $0 == "!" || $0 == "?" || $0 == ";" || $0 == ":" || $0.isNewline
            })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if clauses.contains(where: { $0.hasPrefix("need ") || $0.hasPrefix("need to ") }) {
            return true
        }
        let promisedAttempts = [
            "i will try ", "i'll try ", "i will now ", "i'll now ",
            "i will switch ", "i'll switch ",
            "next i will ", "next i'll ", "let me try ", "let me check ",
            "let me search ", "let me fetch ", "going to try ",
            "now retrieving ", "now fetching ", "now searching ", "now checking ",
            "currently retrieving ", "currently fetching ", "currently searching ",
        ]
        if promisedAttempts.contains(where: text.contains) {
            return true
        }
        let terminalClause = text
            .split(whereSeparator: { $0 == "." || $0 == "!" || $0 == "?" || $0.isNewline })
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let actionGerunds = [
            "reading", "fetching", "searching", "checking", "reviewing", "retrying",
            "writing", "verifying",
        ]
        if actionGerunds.contains(where: { terminalClause.hasPrefix("\($0) ") }) {
            return true
        }
        let nextActionMarkers = [
            "next: re-fetch", "next: refetch", "next: retry", "next: fetch",
            "next: search", "next: read", "next: write", "next step: re-fetch",
            "next step: retry", "next step: fetch", "next step: search",
        ]
        if nextActionMarkers.contains(where: text.contains) {
            return true
        }
        let terminalWords = [
            "a", "an", "and", "as", "at", "before", "but", "by", "for", "from",
            "in", "into", "of", "on", "or", "the", "to", "with",
        ]
        let finalWord = text
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .last
            .map(String.init) ?? ""
        return terminalWords.contains(finalWord)
    }
}

enum WorkspaceSubagentEvidenceDigest {
    private static let maximumCharacters = 5_200
    private static let maximumReasoningCharacters = 1_200
    private static let maximumToolCharacters = 900
    private static let maximumReasoningEntries = 1
    private static let maximumToolEntries = 4

    private struct ToolEvidence {
        let index: Int
        let sourceKey: String
        let text: String
        let score: Int
    }

    /// A worker can be cancelled after gathering the answer but before producing a terminal summary.
    /// Preserve a compact, redacted projection of its grounded trace so the parent can still synthesize.
    static func summary(from thread: ChatThread) -> String? {
        let reasoning = thread.events
            .filter { $0.kind == .notice && $0.summary.hasPrefix("Thinking:") }
            .suffix(maximumReasoningEntries)
            .map { bounded($0.summary, limit: maximumReasoningCharacters) }

        let toolCandidates = thread.messages.enumerated().compactMap { index, message -> ToolEvidence? in
            guard message.role == .tool,
                  let data = message.content.data(using: .utf8),
                  let feedback = try? JSONDecoder().decode(AgentToolFeedback.self, from: data),
                  feedback.result.ok
            else { return nil }
            let output = [feedback.result.stdout, feedback.result.stderr]
                .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? ""
            guard !output.isEmpty else { return nil }
            return ToolEvidence(
                index: index,
                sourceKey: sourceKey(for: feedback),
                text: "\(feedback.toolCall.name): \(bounded(output, limit: maximumToolCharacters))",
                score: evidenceScore(output)
            )
        }
        var bestBySource: [String: ToolEvidence] = [:]
        for candidate in toolCandidates {
            guard let existing = bestBySource[candidate.sourceKey] else {
                bestBySource[candidate.sourceKey] = candidate
                continue
            }
            if candidate.score > existing.score
                || (candidate.score == existing.score && candidate.index > existing.index)
            {
                bestBySource[candidate.sourceKey] = candidate
            }
        }
        let tools = bestBySource.values
            .sorted {
                if $0.score == $1.score { return $0.index > $1.index }
                return $0.score > $1.score
            }
            .prefix(maximumToolEntries)
            .sorted { $0.index < $1.index }
            .map(\.text)

        // Grounded outputs come first so the final bound cannot discard them behind long reasoning.
        let combined = (tools + reasoning).joined(separator: "\n\n")
        guard !combined.isEmpty,
              let sanitized = WorkspaceContextSummarySanitizer.summary(from: combined)
        else { return nil }
        return bounded(sanitized, limit: maximumCharacters)
    }

    private static func sourceKey(for feedback: AgentToolFeedback) -> String {
        guard let data = feedback.toolCall.argumentsJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return "\(feedback.toolCall.name):\(feedback.toolCall.argumentsJSON)" }
        for key in ["url", "path", "query"] {
            if let value = object[key] as? String, !value.isEmpty {
                return "\(feedback.toolCall.name):\(value)"
            }
        }
        return "\(feedback.toolCall.name):\(feedback.toolCall.argumentsJSON)"
    }

    private static func evidenceScore(_ output: String) -> Int {
        let lowercased = output.lowercased()
        var score = min(output.filter(\.isNumber).count, 24)
        if lowercased.contains("http://") || lowercased.contains("https://") { score += 12 }
        if output.contains("$") || output.contains("%") { score += 18 }
        if lowercased.contains("million") || lowercased.contains("billion") { score += 12 }
        let evidenceTerms = [
            "total revenue", "quarter", "evidence", "verified", "passed", "failed",
            "error", "created", "wrote", "found", "result", "source",
        ]
        score += evidenceTerms.reduce(into: 0) { total, term in
            if lowercased.contains(term) { total += 8 }
        }
        return score
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        let collapsed = WorkspaceContextSummaryTextBounds.collapsedSingleLine(text)
        guard collapsed.count > limit else { return collapsed }
        return WorkspaceContextSummaryTextBounds.prefix(collapsed, limit: limit)
    }
}
