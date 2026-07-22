import Foundation
import QuillCodeCore
import QuillCodeSafety
import QuillCodeTools

public struct AgentRunner: Sendable {
    public static let streamingNotice = "Streaming model response"
    /// Conservative LIBRARY default only — every production composition (desktop RuntimeFactory,
    /// per-send configuredRunner, and the quill-code CLI) overrides this with the user-configurable
    /// `AppConfig.maxToolSteps` (default 64): real coding tasks need dozens of tool steps, and the
    /// spend fuse is the runaway guard. Bare `AgentRunner()` (tests, ad-hoc embedding) stays tight.
    public static let defaultMaxToolSteps = 6
    static let promisedWorkCorrectionLimit = 2
    /// Bounded recovery for a malformed model action (garbage/mojibake tokens) or a mid-stream
    /// transport reset: re-prompt/re-request up to this many times before the failure is terminal.
    /// One bad sample must not kill an unattended run ([F5/F6] coworker-program findings).
    static let malformedActionCorrectionLimit = 2

    public var llm: LLMClient
    public var safety: SafetyReviewer
    public var baseToolDefinitions: [ToolDefinition]
    public var additionalToolDefinitions: [ToolDefinition]
    /// Path reach for built-in file tools and shell working directories. The desktop and ordinary
    /// CLI runs stay workspace-relative; only explicit danger-full-access selects unrestricted.
    public var hostToolAccessScope: HostToolAccessScope
    public var toolExecutionOverride: AgentToolExecutionOverride?
    public var streamingToolExecutionOverride: AgentStreamingToolExecutionOverride?
    /// Trusted standard-plugin lifecycle hooks. The desktop supplies validated adapters; the core
    /// agent owns ordering so rewrites precede safety review and post hooks also run after a held
    /// approval resumes.
    public var preToolUseHook: AgentPreToolUseHook?
    public var postToolUseHook: AgentPostToolUseHook?
    public var permissionRequestHook: AgentPermissionRequestHook?
    /// Trusted standard-plugin hooks around both proactive/reactive automatic compaction. Manual
    /// compaction uses the same typed outcomes through the workspace model.
    public var preCompactHook: AgentCompactionHook?
    public var postCompactHook: AgentCompactionHook?
    /// Executes tools whose durable state must be merged back into the active thread. Keep ordinary
    /// host tools on `toolExecutionOverride`; this path is reserved for thread-owning workflows such
    /// as delegated agents.
    public var threadToolExecutionOverride: AgentThreadToolExecutionOverride?
    /// Converts trusted, managed tool artifacts into hidden model-feedback attachments. The app
    /// uses this for Computer Use screenshots; nil preserves text-only tool continuation.
    public var toolFeedbackAttachmentProvider: AgentToolFeedbackAttachmentProvider?
    /// Optional per-run skill roots. The desktop uses this to insert enabled plugin skill roots
    /// between direct project skills and global skills without changing the tool schema.
    public var skillResolver: SkillResolver?
    /// Backend for `host.web.search`. Injected (with TrustedRouter credentials) by the live
    /// runtime; nil in mock/test runs, where the tool reports that search is unavailable. Kept as
    /// a first-class runner dependency — rather than folded into `toolExecutionOverride` — so both
    /// the CLI and desktop wire it through one place and `configuredRunner(from:)` preserves it.
    public var webSearch: (any WebSearchClient)?
    /// Probes `host.web.search` result URLs and drops the ones that don't resolve before the model
    /// sees them. Set by the live runtime (a `WebFetchURLLivenessChecker`); nil in mock/test runs,
    /// where results pass through unfiltered. This is what stops the LLM-as-search-engine backend
    /// from surfacing hallucinated 404 URLs the model would otherwise fetch and cite.
    public var webSearchLivenessChecker: (any WebSearchURLLivenessChecking)?
    public var maxToolSteps: Int
    public var enablesImmediateActionPreflight: Bool
    /// Computes an opaque signature of the workspace state, sampled around tool steps to feed the
    /// flail detector's "did anything actually change" judgment. nil = the git-based default;
    /// injected in tests for determinism.
    public var workspaceStateSignature: (@Sendable (URL) -> String)?
    /// Compacts the thread and resumes when a model call overflows the context window (issue #862).
    /// nil disables compaction entirely (the mock runtime, and any caller that opts out) — the run
    /// then behaves exactly as before, surfacing an overflow error instead of compacting.
    public var compaction: AgentCompactionPolicy?
    /// LSP integration for the workspace (issue #863): after every write/apply_patch it feeds
    /// project-wide diagnostics back to the model and (opt-in) auto-formats on save, and it backs the
    /// `host.lsp.*` navigation tools. A single shared instance persists the language-server process
    /// across tool steps. nil (the default, and the mock runtime) disables every LSP behavior — writes
    /// behave exactly as before and the nav tools report "not available".
    public var lsp: LSPCoordinator?
    /// Optional cost-control gate. When configured with a positive fuse and priced model catalog,
    /// provider usage events pause the run before the next model/tool step once spend crosses a bucket.
    public var runSpendFusePolicy: RunSpendFusePolicy?

    public init(
        llm: LLMClient = MockLLMClient(),
        safety: SafetyReviewer = AutoSafetyReviewer(),
        baseToolDefinitions: [ToolDefinition] = ToolRouter.definitions,
        additionalToolDefinitions: [ToolDefinition] = [],
        hostToolAccessScope: HostToolAccessScope = .workspaceOnly,
        toolExecutionOverride: AgentToolExecutionOverride? = nil,
        streamingToolExecutionOverride: AgentStreamingToolExecutionOverride? = nil,
        preToolUseHook: AgentPreToolUseHook? = nil,
        postToolUseHook: AgentPostToolUseHook? = nil,
        permissionRequestHook: AgentPermissionRequestHook? = nil,
        preCompactHook: AgentCompactionHook? = nil,
        postCompactHook: AgentCompactionHook? = nil,
        threadToolExecutionOverride: AgentThreadToolExecutionOverride? = nil,
        toolFeedbackAttachmentProvider: AgentToolFeedbackAttachmentProvider? = nil,
        skillResolver: SkillResolver? = nil,
        webSearch: (any WebSearchClient)? = nil,
        webSearchLivenessChecker: (any WebSearchURLLivenessChecking)? = nil,
        maxToolSteps: Int = AgentRunner.defaultMaxToolSteps,
        enablesImmediateActionPreflight: Bool = false,
        workspaceStateSignature: (@Sendable (URL) -> String)? = nil,
        compaction: AgentCompactionPolicy? = nil,
        lsp: LSPCoordinator? = nil,
        runSpendFusePolicy: RunSpendFusePolicy? = nil
    ) {
        self.llm = llm
        self.safety = safety
        self.baseToolDefinitions = baseToolDefinitions
        self.additionalToolDefinitions = additionalToolDefinitions
        self.hostToolAccessScope = hostToolAccessScope
        self.toolExecutionOverride = toolExecutionOverride
        self.streamingToolExecutionOverride = streamingToolExecutionOverride
        self.preToolUseHook = preToolUseHook
        self.postToolUseHook = postToolUseHook
        self.permissionRequestHook = permissionRequestHook
        self.preCompactHook = preCompactHook
        self.postCompactHook = postCompactHook
        self.threadToolExecutionOverride = threadToolExecutionOverride
        self.toolFeedbackAttachmentProvider = toolFeedbackAttachmentProvider
        self.skillResolver = skillResolver
        self.webSearch = webSearch
        self.webSearchLivenessChecker = webSearchLivenessChecker
        self.maxToolSteps = maxToolSteps
        self.enablesImmediateActionPreflight = enablesImmediateActionPreflight
        self.workspaceStateSignature = workspaceStateSignature
        self.compaction = compaction
        self.lsp = lsp
        self.runSpendFusePolicy = runSpendFusePolicy
    }

    public func send(
        _ userMessage: String,
        in thread: ChatThread,
        workspaceRoot: URL,
        recordUserMessage: Bool = true,
        onProgress: AgentRunProgressHandler? = nil
    ) async throws -> AgentRunResult {
        var next = thread
        if recordUserMessage {
            next.messages.append(.init(role: .user, content: userMessage))
            next.events.append(.init(kind: .message, summary: userMessage))
            next.updatedAt = Date()
            if next.title == "New chat" {
                next.title = Self.title(from: userMessage)
            }
        }
        await onProgress?(next)

        do {
            try Task.checkCancellation()
            let tools = hostToolAccessScope.adapting(
                Self.mergedToolDefinitions(baseToolDefinitions, additionalToolDefinitions)
            )
            var runLoop = AgentRunLoopState()
            var autoReviewCircuit = AutoReviewCircuitBreaker()
            let limit = max(1, maxToolSteps)
            let stateSignature = workspaceStateSignature ?? Self.defaultWorkspaceStateSignature

            for _ in 0..<limit {
                let action = try await nextActionCompactingOnOverflow(
                    thread: &next,
                    userMessage: userMessage,
                    tools: tools,
                    workspaceRoot: workspaceRoot,
                    onProgress: onProgress
                )
                if let paused = await pauseIfSpendFuseRequiresApproval(
                    thread: &next,
                    onProgress: onProgress
                ) {
                    return AgentRunResult(
                        thread: next,
                        toolResults: runLoop.toolResults,
                        stopReason: paused.stopReason,
                        pendingApproval: paused.pendingApproval
                    )
                }
                let resolvedAction = try await actionByRetryingPromisedWorkIfNeeded(
                    action,
                    thread: next,
                    userMessage: userMessage,
                    tools: tools
                )
                try Task.checkCancellation()
                switch resolvedAction {
                case .say(let text):
                    appendAssistantMessage(text, to: &next)
                    await onProgress?(next)
                    return AgentRunResult(thread: next, toolResults: runLoop.toolResults)
                case .tool(let call):
                    if let lastCompletion = runLoop.repeatedCompletion(for: call) {
                        appendAssistantMessage(Self.finalAnswer(
                            for: lastCompletion.call,
                            result: lastCompletion.result,
                            followUpReviewResult: lastCompletion.followUpReviewResult
                        ), to: &next)
                        await onProgress?(next)
                        return AgentRunResult(thread: next, toolResults: runLoop.toolResults)
                    }

                    // Baseline the workspace state before the first tool step, so that step's own
                    // delta is measurable. (Lazy: a .say-only run never pays for a signature.)
                    runLoop.baselineWorkspaceStateIfNeeded(
                        workspaceRoot: workspaceRoot,
                        stateSignature: stateSignature
                    )
                    let step = try await runToolStep(
                        call,
                        userMessage: userMessage,
                        thread: &next,
                        workspaceRoot: workspaceRoot,
                        toolDefinitions: tools,
                        onProgress: onProgress
                    )
                    switch step {
                    case .blocked(let pendingApproval):
                        return AgentRunResult(
                            thread: next,
                            toolResults: runLoop.toolResults,
                            stopReason: .approvalRequired(requestID: pendingApproval.request.id),
                            pendingApproval: pendingApproval
                        )
                    case .denied(let completion):
                        appendToolFeedback(completion, to: &next)
                        runLoop.recordDeniedStep(completion)
                        if let reason = autoReviewCircuit.record(.denied) {
                            let message = reason.message
                                + " Review the exact denials with /approve before retrying one action."
                            appendAssistantMessage(message, to: &next)
                            next.events.append(.init(
                                kind: .notice,
                                summary: "Auto-review circuit breaker: \(reason.message)"
                            ))
                            next.updatedAt = Date()
                            await onProgress?(next)
                            return AgentRunResult(
                                thread: next,
                                toolResults: runLoop.toolResults,
                                stopReason: .autoReviewCircuitBreaker(reason: reason.message)
                            )
                        }
                    case .completed(let completion, let reviewOutcome):
                        if let reviewOutcome {
                            _ = autoReviewCircuit.record(reviewOutcome)
                        }
                        appendToolFeedback(completion, to: &next)
                        let verdict = runLoop.recordCompletedStep(
                            completion,
                            workspaceRoot: workspaceRoot,
                            stateSignature: stateSignature
                        )
                        switch verdict {
                        case .none:
                            break
                        case .suspected(let reason):
                            // ONE self-assessment nudge per run: make the model say why it is stuck
                            // and change course, instead of burning the rest of the budget.
                            if runLoop.recordFlailAssessmentIfNeeded() {
                                next.messages.append(.init(
                                    role: .user,
                                    content: Self.flailSelfAssessmentPrompt(reason: reason)
                                ))
                                next.events.append(.init(
                                    kind: .notice,
                                    summary: "Self-healing: \(reason.message) Asked the agent to reassess its approach."
                                ))
                                next.updatedAt = Date()
                                await onProgress?(next)
                            }
                        case .confirmed(let reason):
                            // The nudge didn't help — stop honestly, summarizing from the latest step,
                            // with a distinct stopReason so this is never mistaken for a real finish.
                            appendAssistantMessage(Self.finalAnswer(
                                for: completion.call,
                                result: completion.result,
                                followUpReviewResult: completion.followUpReviewResult
                            ), to: &next)
                            next.events.append(.init(
                                kind: .notice,
                                summary: "Self-healing: stopped the run — \(reason.message)"
                            ))
                            next.updatedAt = Date()
                            await onProgress?(next)
                            return AgentRunResult(
                                thread: next,
                                toolResults: runLoop.toolResults,
                                stopReason: .flailDetected(reason: reason.message)
                            )
                        }
                    }
                }
            }

            // Reaching here means the loop ran its full tool-step budget without the model ever
            // returning a final answer — the run hit its ceiling. Synthesize an answer as before, but
            // record it HONESTLY (a notice + a distinct stopReason) so it is not mistaken for a real
            // finish on an unattended run.
            if let lastCompletion = runLoop.latestCompletion {
                appendAssistantMessage(Self.finalAnswer(
                    for: lastCompletion.call,
                    result: lastCompletion.result,
                    followUpReviewResult: lastCompletion.followUpReviewResult
                ), to: &next)
            } else {
                let message = AgentError.tooManyToolSteps(limit).description
                next.messages.append(.init(role: .assistant, content: message))
                next.events.append(.init(kind: .message, summary: message))
                next.updatedAt = Date()
            }
            next.events.append(.init(
                kind: .notice,
                summary: "Reached the \(limit)-step tool limit before finishing; summary is from the latest step."
            ))
            await onProgress?(next)
            return AgentRunResult(
                thread: next,
                toolResults: runLoop.toolResults,
                stopReason: .toolStepCeilingExhausted(limit: limit)
            )
        } catch is CancellationError {
            AgentCancellationRecorder.recordCancelledRun(in: &next)
            await onProgress?(next)
            throw CancellationError()
        }
    }

    private func appendAssistantMessage(_ text: String, to thread: inout ChatThread) {
        if let lastIndex = thread.messages.indices.last,
           thread.messages[lastIndex].role == .assistant {
            thread.messages[lastIndex].content = text
        } else {
            thread.messages.append(.init(role: .assistant, content: text))
        }
        thread.events.append(.init(kind: .message, summary: text))
        thread.updatedAt = Date()
    }

    private func pauseIfSpendFuseRequiresApproval(
        thread: inout ChatThread,
        onProgress: AgentRunProgressHandler?
    ) async -> (stopReason: AgentRunStopReason, pendingApproval: AgentPendingApproval?)? {
        guard let runSpendFusePolicy else { return nil }
        switch runSpendFusePolicy.approvalState(for: thread) {
        case .allowed:
            return nil
        case .blocked(let existingRequestID):
            thread.events.append(.init(
                kind: .notice,
                summary: "Spend limit is waiting on approval \(existingRequestID)."
            ))
            thread.updatedAt = Date()
            await onProgress?(thread)
            let summary = runSpendFusePolicy.spendSummary(for: thread)
            return (
                .spendFuseApprovalRequired(
                    totalUSD: summary.totalUSD,
                    fuseUSD: runSpendFusePolicy.fuseUSD ?? 0
                ),
                pendingApproval(in: thread, requestID: existingRequestID)
            )
        case .request(let request):
            let payload = try? JSONHelpers.decode(
                RunSpendFuseApprovalPayload.self,
                from: request.toolCall.argumentsJSON
            )
            let limitLabel = payload?.approvalLimitKind == .threadFuse
                ? "Thread spend"
                : payload?.approvalLimitKind.label.capitalized ?? "Spend limit"
            let spend = RunSpendFusePolicy.costLabel(payload?.totalUSD ?? 0)
            let text = "\(limitLabel) reached \(spend). "
                + "Approve to continue this run."
            thread.events.append(.init(
                kind: .approvalRequested,
                summary: request.reason,
                payloadJSON: try? JSONHelpers.encodePretty(request)
            ))
            thread.messages.append(.init(role: .assistant, content: text))
            thread.events.append(.init(kind: .message, summary: text))
            thread.updatedAt = Date()
            await onProgress?(thread)
            return (
                .spendFuseApprovalRequired(
                    totalUSD: payload?.totalUSD ?? 0,
                    fuseUSD: payload?.fuseUSD ?? runSpendFusePolicy.fuseUSD ?? 0
                ),
                AgentPendingApproval(request: request)
            )
        }
    }

    private func pendingApproval(in thread: ChatThread, requestID: String) -> AgentPendingApproval? {
        for event in thread.events.reversed() where event.kind == .approvalRequested {
            guard let payloadJSON = event.payloadJSON,
                  let request = try? JSONHelpers.decode(ApprovalRequest.self, from: payloadJSON),
                  request.id == requestID else { continue }
            return AgentPendingApproval(request: request)
        }
        return nil
    }

    static func mergedToolDefinitions(
        _ base: [ToolDefinition],
        _ additional: [ToolDefinition]
    ) -> [ToolDefinition] {
        var seen = Set<String>()
        var definitions: [ToolDefinition] = []
        for definition in base + additional {
            guard !seen.contains(definition.name) else { continue }
            seen.insert(definition.name)
            definitions.append(definition)
        }
        return definitions
    }

    /// The one nudge a suspected-flailing run gets before being stopped: name the loop it is in and
    /// demand a change of course or an honest final answer.
    static func flailSelfAssessmentPrompt(reason: FlailStuckReason) -> String {
        "[QuillCode self-check] \(reason.message) Stop and reassess: state in one or two sentences why "
            + "the previous attempts did not work, then either take a clearly different approach or give "
            + "your best final answer now."
    }

    static func finalAnswer(
        for call: ToolCall,
        result: ToolResult,
        followUpReviewResult: ToolResult? = nil
    ) -> String {
        AgentFinalAnswerBuilder.finalAnswer(
            for: call,
            result: result,
            followUpReviewResult: followUpReviewResult
        )
    }

    static func title(from userMessage: String) -> String {
        let words = userMessage.split(separator: " ").prefix(6).joined(separator: " ")
        return words.isEmpty ? "New chat" : words
    }
}
