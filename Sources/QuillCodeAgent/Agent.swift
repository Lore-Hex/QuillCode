import Foundation
import QuillCodeCore
import QuillCodeSafety
import QuillCodeTools

public struct AgentRunner: Sendable {
    public static let streamingNotice = "Streaming model response"
    public static let defaultMaxToolSteps = 6
    static let promisedWorkCorrectionLimit = 2

    public var llm: LLMClient
    public var safety: SafetyReviewer
    public var baseToolDefinitions: [ToolDefinition]
    public var additionalToolDefinitions: [ToolDefinition]
    public var toolExecutionOverride: AgentToolExecutionOverride?
    public var maxToolSteps: Int
    public var enablesImmediateActionPreflight: Bool
    /// Computes an opaque signature of the workspace state, sampled around tool steps to feed the
    /// flail detector's "did anything actually change" judgment. nil = the git-based default;
    /// injected in tests for determinism.
    public var workspaceStateSignature: (@Sendable (URL) -> String)?

    public init(
        llm: LLMClient = MockLLMClient(),
        safety: SafetyReviewer = AutoSafetyReviewer(),
        baseToolDefinitions: [ToolDefinition] = ToolRouter.definitions,
        additionalToolDefinitions: [ToolDefinition] = [],
        toolExecutionOverride: AgentToolExecutionOverride? = nil,
        maxToolSteps: Int = AgentRunner.defaultMaxToolSteps,
        enablesImmediateActionPreflight: Bool = false,
        workspaceStateSignature: (@Sendable (URL) -> String)? = nil
    ) {
        self.llm = llm
        self.safety = safety
        self.baseToolDefinitions = baseToolDefinitions
        self.additionalToolDefinitions = additionalToolDefinitions
        self.toolExecutionOverride = toolExecutionOverride
        self.maxToolSteps = maxToolSteps
        self.enablesImmediateActionPreflight = enablesImmediateActionPreflight
        self.workspaceStateSignature = workspaceStateSignature
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
            let tools = Self.mergedToolDefinitions(baseToolDefinitions, additionalToolDefinitions)
            var toolResults: [ToolResult] = []
            var lastExecutedCall: ToolCall?
            var lastCompletion: AgentToolStepCompletion?
            let limit = max(1, maxToolSteps)
            // Flail detection: catch a run that is busy but going NOWHERE (same action / same failure
            // repeating with zero workspace change) — the overnight failure mode the exact-repeat
            // short-circuit above and the step ceiling below both miss.
            var flailDetector = FlailDetector()
            let stateSignature = workspaceStateSignature ?? Self.defaultWorkspaceStateSignature
            var previousWorkspaceState: String?
            var flailAssessmentInjected = false

            for _ in 0..<limit {
                let action = try await nextAction(
                    thread: &next,
                    userMessage: userMessage,
                    tools: tools,
                    onProgress: onProgress
                )
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
                    return AgentRunResult(thread: next, toolResults: toolResults)
                case .tool(let call):
                    if let lastExecutedCall,
                       lastExecutedCall.name == call.name,
                       lastExecutedCall.argumentsJSON == call.argumentsJSON,
                       let lastCompletion {
                        appendAssistantMessage(Self.finalAnswer(
                            for: lastCompletion.call,
                            result: lastCompletion.result,
                            followUpReviewResult: lastCompletion.followUpReviewResult
                        ), to: &next)
                        await onProgress?(next)
                        return AgentRunResult(thread: next, toolResults: toolResults)
                    }

                    // Baseline the workspace state before the first tool step, so that step's own
                    // delta is measurable. (Lazy: a .say-only run never pays for a signature.)
                    if previousWorkspaceState == nil {
                        previousWorkspaceState = stateSignature(workspaceRoot)
                    }
                    let step = try await runToolStep(
                        call,
                        userMessage: userMessage,
                        thread: &next,
                        workspaceRoot: workspaceRoot,
                        toolDefinitions: tools,
                        onProgress: onProgress
                    )
                    switch step {
                    case .blocked:
                        return AgentRunResult(thread: next, toolResults: toolResults)
                    case .completed(let completion):
                        toolResults.append(contentsOf: completion.toolResults)
                        lastExecutedCall = call
                        lastCompletion = completion
                        appendToolFeedback(completion, to: &next)

                        let workspaceState = stateSignature(workspaceRoot)
                        let verdict = flailDetector.record(FlailTurnRecord(
                            fingerprints: [ToolCallFingerprint.make(call: call, workspaceRoot: workspaceRoot)],
                            deltaSignature: workspaceState == previousWorkspaceState ? "" : workspaceState,
                            failureSignature: FlailSignatures.failureSignature(fromToolOutput: [
                                completion.result.stdout,
                                completion.result.stderr,
                                completion.result.error ?? "",
                            ].joined(separator: "\n"))
                        ))
                        previousWorkspaceState = workspaceState
                        switch verdict {
                        case .none:
                            break
                        case .suspected(let reason):
                            // ONE self-assessment nudge per run: make the model say why it is stuck
                            // and change course, instead of burning the rest of the budget.
                            if !flailAssessmentInjected {
                                flailAssessmentInjected = true
                                flailDetector.recordAssessment()
                                next.messages.append(.init(role: .user, content: Self.flailSelfAssessmentPrompt(reason: reason)))
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
                                toolResults: toolResults,
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
            if let lastCompletion {
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
                toolResults: toolResults,
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

    private static func mergedToolDefinitions(
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

    /// The default workspace-state signature: a git hash over status + diff, so "nothing changed" is
    /// judged by the actual tree, not by what the tools claimed. One fast local git invocation per
    /// completed tool step; a non-git workspace degrades to a constant (flail rules then rely on
    /// fingerprints and failure signatures alone).
    static func defaultWorkspaceStateSignature(_ root: URL) -> String {
        let result = ShellToolExecutor().run(.init(
            command: "{ git status --porcelain; git diff HEAD; } 2>/dev/null | git hash-object --stdin 2>/dev/null || echo no-git",
            cwd: root,
            timeoutSeconds: 10
        ))
        let signature = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return signature.isEmpty ? "no-git" : signature
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
