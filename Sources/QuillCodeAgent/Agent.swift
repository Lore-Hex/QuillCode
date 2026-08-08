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
    /// Wall-clock cap for ONE model turn (first token → completed action). Generous on purpose:
    /// legitimate turns finish in seconds-to-a-couple-minutes even for verbose reasoners; the F20
    /// spiral streamed thinking for 25 minutes without ever acting. Overrun → bounded corrective
    /// re-prompt, not a dead run.
    public static let defaultTurnDeadlineSeconds: TimeInterval = 300
    /// Character budget for streamed reasoning before the model starts an action. This catches a
    /// steady reasoner spiral much earlier than the wall-clock deadline while preserving normal
    /// reasoning and every stream that has begun producing action JSON.
    public static let defaultPreActionReasoningCharacterLimit = 12_000
    /// Wider per-turn budget while the model is synthesizing from tool results but has not yet
    /// produced a workspace mutation. Large grounded deliverables need more room than startup
    /// routing; the bound still prevents an inter-action reasoner spiral.
    public static let defaultInterActionReasoningCharacterLimit = 16_000
    /// Corrective samples must converge faster than the sample they replace; otherwise recovery
    /// can consume the remaining turn deadline by repeating the same reasoning spiral.
    public static let correctiveActionReasoningCharacterLimit = 2_000
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
    /// Wall-clock budget for a SINGLE model turn (first token to completed action), in seconds.
    /// Exceeding it cancels the stream and triggers the bounded "stop planning — emit the next
    /// action" correction (F20: a reasoner can stream thinking tokens indefinitely without ever
    /// acting; no terminal say means the phrase guards never see it). nil disables the deadline.
    public var turnDeadlineSeconds: TimeInterval?
    /// Maximum streamed reasoning characters at run startup and after a successful workspace
    /// mutation, when the next action should be a bounded verification or final answer. nil
    /// disables the tight-phase guard.
    public var preActionReasoningCharacterLimit: Int?
    /// Maximum streamed reasoning characters between source-gathering actions and the run's first
    /// successful workspace mutation. nil disables the synthesis-phase guard.
    public var interActionReasoningCharacterLimit: Int?
    /// Last-resort model for a step the primary cannot produce at all (F22): when the primary
    /// exhausts the empty-response correction budget — a route-quality failure observed at ~1-in-6
    /// runs on one provider while an alternate model completed the same step first try — the
    /// resolver retries the SAME step once on this client instead of killing the run. All prior
    /// tool work is preserved (same thread); the switch is recorded as a Self-healing notice.
    /// nil (the default) keeps today's behavior: exhaustion is terminal.
    public var fallbackLLM: LLMClient?

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
        runSpendFusePolicy: RunSpendFusePolicy? = nil,
        turnDeadlineSeconds: TimeInterval? = AgentRunner.defaultTurnDeadlineSeconds,
        preActionReasoningCharacterLimit: Int? = AgentRunner.defaultPreActionReasoningCharacterLimit,
        interActionReasoningCharacterLimit: Int? = AgentRunner.defaultInterActionReasoningCharacterLimit,
        fallbackLLM: LLMClient? = nil
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
        self.turnDeadlineSeconds = turnDeadlineSeconds
        self.preActionReasoningCharacterLimit = preActionReasoningCharacterLimit
        self.interActionReasoningCharacterLimit = interActionReasoningCharacterLimit
        self.fallbackLLM = fallbackLLM
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
            var hasEmittedModelAction = false
            var hasCompletedWorkspaceMutation = false
            /// One-shot corrective for the next sample only (Cline learning #2 repeat nudge).
            var pendingRepeatNudge: String?
            /// A premature read of a task-named output is redirected once per path. A repeated
            /// attempt is allowed to execute normally so this guard can never create a loop.
            var preWriteVerificationNudgedPaths = Set<String>()
            /// Unsafe shell paths get one preflight correction per exact call. A repeated proposal
            /// still reaches the approval gate, preserving its authority and bounded termination.
            var preflightCorrectedShellCalls = Set<ToolCallFingerprint>()
            /// A successful read/fetch may be followed by an exhausted empty or passive model turn.
            /// Give each failure class one run-level continuation; the action resolver still owns
            /// its own bounded retries, so provider instability cannot create an unbounded loop.
            var recoveredExhaustedEmptyAfterTool = false
            var recoveredExhaustedPromisedWorkAfterTool = false
            /// Listing a not-yet-created output directory is predictably unsuccessful. Correct each
            /// exact proposal once, then allow a repeat through so this preflight stays bounded.
            var preflightCorrectedMissingListCalls = Set<ToolCallFingerprint>()
            /// Source paths and data labels are not commands. Redirect each exact model proposal
            /// once after tool work has begun; a repeated proposal still reaches the shell.
            var preflightCorrectedInvalidShellCalls = Set<ToolCallFingerprint>()
            /// A malformed named prose artifact receives one corrective rewrite request per path.
            var artifactTextQualityNudgedPaths = Set<String>()
            /// If the model ignores that request, one deterministic escape-decoding repair is
            /// allowed per path. The resulting write re-arms the normal readback gate.
            var artifactTextQualityRepairedPaths = Set<String>()
            /// An explicitly placeholder-free named artifact receives one corrective rewrite per path.
            var artifactPlaceholderNudgedPaths = Set<String>()
            /// If the model ignores that rewrite request, one deterministic blank-field repair is
            /// allowed per path. The resulting write re-arms the normal readback gate.
            var artifactPlaceholderRepairedPaths = Set<String>()
            /// A named text artifact with a contradictory enumerated count receives one semantic
            /// rewrite request, followed by at most one deterministic numeral correction.
            var artifactCountConsistencyNudgedPaths = Set<String>()
            var artifactCountConsistencyRepairedPaths = Set<String>()
            /// Explicitly source-only named artifacts receive one post-draft semantic audit. A
            /// rewrite from that audit receives one verification pass; read-only audits stop at one.
            var sourceGroundingAuditCounts: [String: Int] = [:]
            var sourceGroundingVerificationPaths = Set<String>()
            var pendingSourceGroundingAuditPath: String?
            var pendingSourceGroundingAuditBaseline: String?
            var sourceGroundingRepairedPaths = Set<String>()
            /// A deterministic source repair owns finalization. Keeping this action across the
            /// forced readback prevents a fresh model turn from restoring the removed claims.
            var controlledSourceGroundingFinalization: AgentAction?
            var pendingSourceGroundingRepairPath: String?
            // F29: URLs from the request and the thread's prior turns are grounded provenance —
            // a follow-up send must not flag citations the previous send legitimately fetched.
            runLoop.seedCitationProvenance(userMessage: userMessage, thread: next)
            runLoop.seedSourceGrounding(userMessage: userMessage)
            var autoReviewCircuit = AutoReviewCircuitBreaker()
            let limit = max(1, maxToolSteps)
            let stateSignature = workspaceStateSignature ?? Self.defaultWorkspaceStateSignature

            actionLoop: for _ in 0..<limit {
                let repeatNudge = pendingRepeatNudge
                pendingRepeatNudge = nil
                let reasoningBudgetPhase: AgentReasoningBudgetPhase = if !hasEmittedModelAction {
                    .startup
                } else if hasCompletedWorkspaceMutation {
                    .checkpoint
                } else {
                    .synthesis
                }
                let action: AgentAction
                if let controlledSourceGroundingFinalization {
                    action = controlledSourceGroundingFinalization
                } else {
                    do {
                        action = try await nextActionCompactingOnOverflow(
                            thread: &next,
                            userMessage: userMessage,
                            tools: tools,
                            workspaceRoot: workspaceRoot,
                            onProgress: onProgress,
                            injectedCorrection: repeatNudge,
                            reasoningBudgetPhase: reasoningBudgetPhase
                        )
                    } catch AgentError.emptyStreamingResponse {
                        try Task.checkCancellation()
                        guard let completion = runLoop.latestCompletion,
                              completion.result.ok
                        else { throw AgentError.emptyStreamingResponse }
                        if let recoveredRead = AgentExplicitSourceReadRecovery.nextAction(
                            userMessage: userMessage,
                            workspaceRoot: workspaceRoot,
                            tools: tools,
                            successfullyReadPaths: runLoop.successfullyReadWorkspacePaths
                        ) {
                            action = recoveredRead
                            next.events.append(.init(
                                kind: .notice,
                                summary: "Self-healing: advanced an explicit requested source read "
                                    + "after repeated empty model responses."
                            ))
                            next.updatedAt = Date()
                            await onProgress?(next)
                        } else if hasCompletedWorkspaceMutation {
                            action = .say(Self.finalAnswer(
                                for: completion.call,
                                result: completion.result,
                                followUpReviewResult: completion.followUpReviewResult
                            ))
                            next.events.append(.init(
                                kind: .notice,
                                summary: "Self-healing: the model returned no final action after "
                                    + "completing workspace work; finalized from the latest "
                                    + "successful tool result."
                            ))
                            next.updatedAt = Date()
                            await onProgress?(next)
                        } else if !recoveredExhaustedEmptyAfterTool {
                            recoveredExhaustedEmptyAfterTool = true
                            pendingRepeatNudge = Self.exhaustedActionContinuationPrompt(
                                after: completion.call,
                                failure: "an empty response"
                            )
                            next.events.append(.init(
                                kind: .notice,
                                summary: "Self-healing: the model returned no action after successful "
                                    + "source work; requested the next concrete step once."
                            ))
                            next.updatedAt = Date()
                            await onProgress?(next)
                            continue actionLoop
                        } else {
                            throw AgentError.emptyStreamingResponse
                        }
                    } catch TrustedRouterAgentError.invalidActionJSON(let malformedText) {
                        try Task.checkCancellation()
                        guard hasCompletedWorkspaceMutation,
                              let completion = runLoop.latestCompletion,
                              completion.result.ok
                        else { throw TrustedRouterAgentError.invalidActionJSON(malformedText) }
                        // Treat malformed terminal text after a successful mutation like the existing
                        // empty-final-action recovery. The synthesized say still passes every named
                        // deliverable, citation, word-budget, and artifact-readback gate below.
                        action = .say(Self.finalAnswer(
                            for: completion.call,
                            result: completion.result,
                            followUpReviewResult: completion.followUpReviewResult
                        ))
                        next.events.append(.init(
                            kind: .notice,
                            summary: "Self-healing: the model returned malformed terminal output after "
                                + "workspace work; continued through completion verification."
                        ))
                        next.updatedAt = Date()
                        await onProgress?(next)
                    } catch TrustedRouterAgentError.emptyToolArguments(let toolName) {
                        try Task.checkCancellation()
                        guard toolName == ToolDefinition.fileRead.name,
                              hasCompletedWorkspaceMutation,
                              let completion = runLoop.latestCompletion,
                              completion.result.ok
                        else { throw TrustedRouterAgentError.emptyToolArguments(toolName) }
                        // The resolver already exhausted bounded schema corrections. Converting only
                        // an empty read after a successful mutation into a candidate final answer lets
                        // the artifact-verification gate below supply the exact required readback path.
                        action = .say(Self.finalAnswer(
                            for: completion.call,
                            result: completion.result,
                            followUpReviewResult: completion.followUpReviewResult
                        ))
                        next.events.append(.init(
                            kind: .notice,
                            summary: "Self-healing: completed a required artifact readback after the "
                                + "model repeatedly omitted the file path."
                        ))
                        next.updatedAt = Date()
                        await onProgress?(next)
                    }
                }
                hasEmittedModelAction = true
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
                var resolvedAction: AgentAction
                do {
                    resolvedAction = try await actionByRetryingPromisedWorkIfNeeded(
                        action,
                        thread: next,
                        userMessage: userMessage,
                        tools: tools
                    )
                } catch AgentError.promisedWorkWithoutToolAction {
                    try Task.checkCancellation()
                    guard let completion = runLoop.latestCompletion,
                          completion.result.ok
                    else { throw AgentError.promisedWorkWithoutToolAction }
                    if let recoveredRead = AgentExplicitSourceReadRecovery.nextAction(
                        userMessage: userMessage,
                        workspaceRoot: workspaceRoot,
                        tools: tools,
                        successfullyReadPaths: runLoop.successfullyReadWorkspacePaths
                    ) {
                        resolvedAction = recoveredRead
                        next.events.append(.init(
                            kind: .notice,
                            summary: "Self-healing: advanced an explicit requested source read "
                                + "after repeated passive model responses."
                        ))
                        next.updatedAt = Date()
                        await onProgress?(next)
                    } else {
                        guard !recoveredExhaustedPromisedWorkAfterTool
                        else { throw AgentError.promisedWorkWithoutToolAction }
                        recoveredExhaustedPromisedWorkAfterTool = true
                        pendingRepeatNudge = Self.exhaustedActionContinuationPrompt(
                            after: completion.call,
                            failure: "a passive promise instead of a tool action"
                        )
                        next.events.append(.init(
                            kind: .notice,
                            summary: "Self-healing: the model stopped at a promise after successful "
                                + "tool work; requested the next concrete step once."
                        ))
                        next.updatedAt = Date()
                        await onProgress?(next)
                        continue actionLoop
                    }
                }
                if case .say = resolvedAction,
                   let correction = AgentArtifactTextQualityGate.correction(
                    userMessage: userMessage,
                    malformedPaths: runLoop.malformedWrittenTextPaths
                   ) {
                    if artifactTextQualityNudgedPaths.insert(correction.path).inserted {
                        pendingRepeatNudge = correction.prompt
                        next.events.append(.init(
                            kind: .notice,
                            summary: "Self-healing: requested clean text formatting for "
                                + "./\(correction.path) before completion."
                        ))
                        next.updatedAt = Date()
                        await onProgress?(next)
                        continue actionLoop
                    }
                    if artifactTextQualityRepairedPaths.insert(correction.path).inserted,
                       let repairCall = Self.malformedTextRepairCall(
                        path: correction.path,
                        contentsByPath: runLoop.malformedWrittenTextContents
                       ) {
                        resolvedAction = .tool(repairCall)
                        next.events.append(.init(
                            kind: .notice,
                            summary: "Self-healing: decoded literal formatting escapes in "
                                + "./\(correction.path) before completion."
                        ))
                        next.updatedAt = Date()
                        await onProgress?(next)
                    }
                }
                if case .say = resolvedAction,
                   let correction = AgentArtifactTextQualityGate.placeholderCorrection(
                    userMessage: userMessage,
                    placeholderPaths: runLoop.placeholderWrittenTextPaths
                   ) {
                    if artifactPlaceholderNudgedPaths.insert(correction.path).inserted {
                        pendingRepeatNudge = correction.prompt
                        next.events.append(.init(
                            kind: .notice,
                            summary: "Self-healing: requested placeholder-free text for "
                                + "./\(correction.path) before completion."
                        ))
                        next.updatedAt = Date()
                        await onProgress?(next)
                        continue actionLoop
                    }
                    if artifactPlaceholderRepairedPaths.insert(correction.path).inserted,
                       let repairCall = Self.placeholderRepairCall(
                        path: correction.path,
                        contentsByPath: runLoop.placeholderWrittenTextContents
                       ) {
                        resolvedAction = .tool(repairCall)
                        next.events.append(.init(
                            kind: .notice,
                            summary: "Self-healing: replaced bracketed fill-in fields with blanks in "
                                + "./\(correction.path) before completion."
                        ))
                        next.updatedAt = Date()
                        await onProgress?(next)
                    }
                }
                if case .say = resolvedAction,
                   let correction = AgentArtifactTextQualityGate.enumeratedCountCorrection(
                    userMessage: userMessage,
                    contradictoryPaths: runLoop.contradictoryCountWrittenTextPaths
                   ) {
                    if artifactCountConsistencyNudgedPaths.insert(correction.path).inserted {
                        pendingRepeatNudge = correction.prompt
                        next.events.append(.init(
                            kind: .notice,
                            summary: "Self-healing: requested consistent enumerated counts for "
                                + "./\(correction.path) before completion."
                        ))
                        next.updatedAt = Date()
                        await onProgress?(next)
                        continue actionLoop
                    }
                    if artifactCountConsistencyRepairedPaths.insert(correction.path).inserted,
                       let repairCall = Self.enumeratedCountRepairCall(
                        path: correction.path,
                        contentsByPath: runLoop.contradictoryCountWrittenTextContents
                       ) {
                        resolvedAction = .tool(repairCall)
                        next.events.append(.init(
                            kind: .notice,
                            summary: "Self-healing: reconciled an enumerated record count in "
                                + "./\(correction.path) before completion."
                        ))
                        next.updatedAt = Date()
                        await onProgress?(next)
                    }
                }
                if case .say = resolvedAction,
                   let correction = AgentSourceGroundingGate.correction(
                    userMessage: userMessage,
                    writtenPaths: runLoop.writtenWorkspacePaths,
                    auditCounts: sourceGroundingAuditCounts,
                    verificationPaths: sourceGroundingVerificationPaths
                   ) {
                    sourceGroundingAuditCounts[correction.path, default: 0] += 1
                    sourceGroundingVerificationPaths.remove(correction.path)
                    pendingSourceGroundingAuditPath = correction.path
                    pendingSourceGroundingAuditBaseline = runLoop.latestWrittenTextContent(
                        for: correction.path
                    )
                    pendingRepeatNudge = correction.prompt
                    next.events.append(.init(
                        kind: .notice,
                        summary: "Self-healing: requested a source-grounding audit for "
                            + "./\(correction.path) before completion."
                    ))
                    next.updatedAt = Date()
                    await onProgress?(next)
                    continue actionLoop
                }
                if case .say = resolvedAction,
                   let path = AgentSourceGroundingGate.unsupportedSensitiveClaimPath(
                    userMessage: userMessage,
                    unsupportedPaths: runLoop.unsupportedSourceClaimWrittenTextPaths
                   ),
                   sourceGroundingRepairedPaths.insert(path).inserted,
                   let repairCall = Self.unsupportedSourceClaimRepairCall(
                    path: path,
                    contentsByPath: runLoop.unsupportedSourceClaimWrittenTextContents,
                    sourceText: runLoop.sourceGroundingText
                   ) {
                    resolvedAction = .tool(repairCall)
                    pendingSourceGroundingRepairPath = path
                    next.events.append(.init(
                        kind: .notice,
                        summary: "Self-healing: removed unsupported sensitive claims from "
                            + "./\(path) before completion."
                    ))
                    next.updatedAt = Date()
                    await onProgress?(next)
                }
                // F23: a terminal say may not end the run while a task-named created file is
                // missing on disk. A corrective re-sample that returns a tool action flows into
                // the tool arm below and the loop continues; the gate re-checks at the next say.
                // Skipped when any tool action was denied this run — a blocked write is a
                // legitimate reason for the file to be missing, not a model failure.
                if !runLoop.hadDeniedStep {
                    resolvedAction = try await actionByRequiringNamedDeliverables(
                        resolvedAction,
                        thread: next,
                        userMessage: userMessage,
                        tools: tools,
                        workspaceRoot: workspaceRoot
                    )
                }
                // F29: terminal citations must trace to grounded provenance. Deliberately NOT
                // behind the hadDeniedStep guard — a denied write explains a missing file, never
                // an ungrounded citation — and its failure mode is a bounded corrective plus an
                // honest notice, so a denied-run false flag costs a note, not the run.
                if runLoop.didFetchSuccessfully {
                    resolvedAction = try await actionByRequiringCitationIntegrity(
                        resolvedAction,
                        thread: next,
                        userMessage: userMessage,
                        tools: tools,
                        workspaceRoot: workspaceRoot,
                        groundedURLs: runLoop.groundedURLs,
                        writtenWorkspacePaths: runLoop.writtenWorkspacePaths
                    )
                }
                // F30: explicit N-word specs are checked mechanically, like every other gate.
                if !runLoop.hadDeniedStep {
                    resolvedAction = try await actionByRequiringWordBudget(
                        resolvedAction,
                        thread: next,
                        userMessage: userMessage,
                        tools: tools,
                        workspaceRoot: workspaceRoot
                    )
                    resolvedAction = AgentArtifactVerificationGate.actionByRequiringReadback(
                        resolvedAction,
                        userMessage: userMessage,
                        tools: tools,
                        unverifiedPaths: runLoop.unverifiedWrittenWorkspacePaths
                    )
                }
                try Task.checkCancellation()
                switch resolvedAction {
                case .say(let text):
                    appendAssistantMessage(text, to: &next)
                    await onProgress?(next)
                    return AgentRunResult(thread: next, toolResults: runLoop.toolResults)
                case .tool(let call):
                    var activeCall = call
                    if let lastCompletion = runLoop.repeatedCompletion(for: activeCall) {
                        // Cline learning #2 (graded loop detection): finalizing on the FIRST repeat
                        // converts a recoverable moment into a terminal answer — the F25 incident
                        // was exactly that (an enrichment run repeated a search and "finished" with
                        // raw search results instead of writing the required CSV). Hand the model
                        // the result it already has and let it take one more turn. The nudge rides
                        // the resolver's corrective seam, so it never enters the durable transcript
                        // and its action still passes every guard and gate.
                        //
                        // A preflight action is re-derived deterministically from the user's own
                        // message each iteration — the MODEL never chose to repeat it, so nudging
                        // it would spend a provider round-trip that direct commands are designed
                        // never to need.
                        let isPreflightRepeat: Bool = {
                            guard enablesImmediateActionPreflight,
                                  case .tool(let planned)? = AgentImmediateActionPlanner.action(
                                    for: userMessage,
                                    tools: tools
                                  )
                            else { return false }
                            return planned.name == activeCall.name
                                && planned.argumentsJSON == activeCall.argumentsJSON
                        }()
                        if !isPreflightRepeat, runLoop.shouldSoftWarnOnRepeat(of: activeCall) {
                            pendingRepeatNudge = AgentRepeatedCallGuard.softWarning(
                                call: activeCall,
                                previousResult: lastCompletion.result
                            )
                            next.events.append(.init(
                                kind: .notice,
                                summary: "Self-healing: repeated the same \(activeCall.name) call; "
                                    + "asked for a different step before finalizing."
                            ))
                            next.updatedAt = Date()
                            await onProgress?(next)
                            continue
                        }
                        // F25: repeated-call finalization synthesizes an answer from the last tool
                        // result — it must not slip past the named-deliverable gate the ordinary
                        // terminal-say path enforces (live: an enrichment run repeated a search,
                        // "finalized" with raw search results, and exited with the required CSV
                        // never written). Route the synthesized say through the same gate; if the
                        // corrective sample answers with a fresh tool action (e.g. the missing
                        // file's write), execute it below like any tool step.
                        var finalized: AgentAction = .say(Self.finalAnswer(
                            for: lastCompletion.call,
                            result: lastCompletion.result,
                            followUpReviewResult: lastCompletion.followUpReviewResult
                        ))
                        if let correction = AgentArtifactTextQualityGate.correction(
                            userMessage: userMessage,
                            malformedPaths: runLoop.malformedWrittenTextPaths
                        ) {
                            if artifactTextQualityNudgedPaths.insert(correction.path).inserted {
                                pendingRepeatNudge = correction.prompt
                                next.events.append(.init(
                                    kind: .notice,
                                    summary: "Self-healing: requested clean text formatting for "
                                        + "./\(correction.path) before completion."
                                ))
                                next.updatedAt = Date()
                                await onProgress?(next)
                                continue actionLoop
                            }
                            if artifactTextQualityRepairedPaths.insert(correction.path).inserted,
                               let repairCall = Self.malformedTextRepairCall(
                                path: correction.path,
                                contentsByPath: runLoop.malformedWrittenTextContents
                               ) {
                                finalized = .tool(repairCall)
                                next.events.append(.init(
                                    kind: .notice,
                                    summary: "Self-healing: decoded literal formatting escapes in "
                                        + "./\(correction.path) before completion."
                                ))
                                next.updatedAt = Date()
                                await onProgress?(next)
                            }
                        }
                        if let correction = AgentArtifactTextQualityGate.placeholderCorrection(
                            userMessage: userMessage,
                            placeholderPaths: runLoop.placeholderWrittenTextPaths
                        ) {
                            if artifactPlaceholderNudgedPaths.insert(correction.path).inserted {
                                pendingRepeatNudge = correction.prompt
                                next.events.append(.init(
                                    kind: .notice,
                                    summary: "Self-healing: requested placeholder-free text for "
                                        + "./\(correction.path) before completion."
                                ))
                                next.updatedAt = Date()
                                await onProgress?(next)
                                continue actionLoop
                            }
                            if artifactPlaceholderRepairedPaths.insert(correction.path).inserted,
                               let repairCall = Self.placeholderRepairCall(
                                path: correction.path,
                                contentsByPath: runLoop.placeholderWrittenTextContents
                               ) {
                                finalized = .tool(repairCall)
                                next.events.append(.init(
                                    kind: .notice,
                                    summary: "Self-healing: replaced bracketed fill-in fields with "
                                        + "blanks in ./\(correction.path) before completion."
                                ))
                                next.updatedAt = Date()
                                await onProgress?(next)
                            }
                        }
                        if let correction = AgentArtifactTextQualityGate.enumeratedCountCorrection(
                            userMessage: userMessage,
                            contradictoryPaths: runLoop.contradictoryCountWrittenTextPaths
                        ) {
                            if artifactCountConsistencyNudgedPaths.insert(correction.path).inserted {
                                pendingRepeatNudge = correction.prompt
                                next.events.append(.init(
                                    kind: .notice,
                                    summary: "Self-healing: requested consistent enumerated counts for "
                                        + "./\(correction.path) before completion."
                                ))
                                next.updatedAt = Date()
                                await onProgress?(next)
                                continue actionLoop
                            }
                            if artifactCountConsistencyRepairedPaths.insert(correction.path).inserted,
                               let repairCall = Self.enumeratedCountRepairCall(
                                path: correction.path,
                                contentsByPath: runLoop.contradictoryCountWrittenTextContents
                               ) {
                                finalized = .tool(repairCall)
                                next.events.append(.init(
                                    kind: .notice,
                                    summary: "Self-healing: reconciled an enumerated record count in "
                                        + "./\(correction.path) before completion."
                                ))
                                next.updatedAt = Date()
                                await onProgress?(next)
                            }
                        }
                        if let correction = AgentSourceGroundingGate.correction(
                            userMessage: userMessage,
                            writtenPaths: runLoop.writtenWorkspacePaths,
                            auditCounts: sourceGroundingAuditCounts,
                            verificationPaths: sourceGroundingVerificationPaths
                        ) {
                            sourceGroundingAuditCounts[correction.path, default: 0] += 1
                            sourceGroundingVerificationPaths.remove(correction.path)
                            pendingSourceGroundingAuditPath = correction.path
                            pendingSourceGroundingAuditBaseline = runLoop.latestWrittenTextContent(
                                for: correction.path
                            )
                            pendingRepeatNudge = correction.prompt
                            next.events.append(.init(
                                kind: .notice,
                                summary: "Self-healing: requested a source-grounding audit for "
                                    + "./\(correction.path) before completion."
                            ))
                            next.updatedAt = Date()
                            await onProgress?(next)
                            continue actionLoop
                        }
                        if let path = AgentSourceGroundingGate.unsupportedSensitiveClaimPath(
                            userMessage: userMessage,
                            unsupportedPaths: runLoop.unsupportedSourceClaimWrittenTextPaths
                        ), sourceGroundingRepairedPaths.insert(path).inserted,
                           let repairCall = Self.unsupportedSourceClaimRepairCall(
                            path: path,
                            contentsByPath: runLoop.unsupportedSourceClaimWrittenTextContents,
                            sourceText: runLoop.sourceGroundingText
                           ) {
                            finalized = .tool(repairCall)
                            pendingSourceGroundingRepairPath = path
                            next.events.append(.init(
                                kind: .notice,
                                summary: "Self-healing: removed unsupported sensitive claims from "
                                    + "./\(path) before completion."
                            ))
                            next.updatedAt = Date()
                            await onProgress?(next)
                        }
                        if !runLoop.hadDeniedStep {
                            finalized = try await actionByRequiringNamedDeliverables(
                                finalized,
                                thread: next,
                                userMessage: userMessage,
                                tools: tools,
                                workspaceRoot: workspaceRoot
                            )
                        }
                        // F29: the synthesized finalization answer is a terminal say and must
                        // clear the citation gate like the model-say path (F25 lesson). The
                        // grounded set includes the repeated fetch's own content, so a
                        // finalization that quotes the fetched page never self-flags.
                        if runLoop.didFetchSuccessfully {
                            finalized = try await actionByRequiringCitationIntegrity(
                                finalized,
                                thread: next,
                                userMessage: userMessage,
                                tools: tools,
                                workspaceRoot: workspaceRoot,
                                groundedURLs: runLoop.groundedURLs,
                                writtenWorkspacePaths: runLoop.writtenWorkspacePaths
                            )
                        }
                        // F30: the finalized say is a terminal say (F25 lesson) — same gates.
                        if !runLoop.hadDeniedStep {
                            finalized = try await actionByRequiringWordBudget(
                                finalized,
                                thread: next,
                                userMessage: userMessage,
                                tools: tools,
                                workspaceRoot: workspaceRoot
                            )
                            finalized = AgentArtifactVerificationGate.actionByRequiringReadback(
                                finalized,
                                userMessage: userMessage,
                                tools: tools,
                                unverifiedPaths: runLoop.unverifiedWrittenWorkspacePaths
                            )
                        }
                        switch finalized {
                        case .say(let text):
                            appendAssistantMessage(text, to: &next)
                            await onProgress?(next)
                            return AgentRunResult(thread: next, toolResults: runLoop.toolResults)
                        case .tool(let recoveredCall):
                            activeCall = recoveredCall
                        }
                    }

                    if let correction = AgentArtifactVerificationGate.preWriteCorrection(
                        for: activeCall,
                        userMessage: userMessage,
                        workspaceRoot: workspaceRoot
                    ), preWriteVerificationNudgedPaths.insert(correction.path).inserted {
                        pendingRepeatNudge = correction.prompt
                        next.events.append(.init(
                            kind: .notice,
                            summary: "Self-healing: attempted to verify ./\(correction.path) before "
                                + "creating it; asked the agent to write it first."
                        ))
                        next.updatedAt = Date()
                        await onProgress?(next)
                        continue
                    }

                    let listFingerprint = ToolCallFingerprint.make(
                        name: activeCall.name,
                        argumentsJSON: activeCall.argumentsJSON
                    )
                    if let missingPath = AgentMissingDirectoryListPreflight.missingPath(
                        in: activeCall,
                        workspaceRoot: workspaceRoot
                    ), preflightCorrectedMissingListCalls.insert(listFingerprint).inserted {
                        pendingRepeatNudge = """
                        The directory ./\(missingPath) does not exist yet, so listing it will fail. \
                        If it is an output directory, write the requested file directly; \
                        host.file.write creates parent directories. Otherwise list an existing \
                        source directory. Do not retry the same missing-directory list.
                        """
                        next.events.append(.init(
                            kind: .notice,
                            summary: "Self-healing: avoided listing a missing workspace directory."
                        ))
                        next.updatedAt = Date()
                        await onProgress?(next)
                        continue
                    }

                    let shellFingerprint = ToolCallFingerprint.make(
                        name: activeCall.name,
                        argumentsJSON: activeCall.argumentsJSON
                    )
                    if runLoop.latestCompletion != nil,
                       let correction = AgentInvalidShellProposalPreflight.correction(
                        for: activeCall,
                        workspaceRoot: workspaceRoot
                       ), preflightCorrectedInvalidShellCalls.insert(shellFingerprint).inserted {
                        pendingRepeatNudge = correction.prompt
                        next.events.append(.init(kind: .notice, summary: correction.summary))
                        next.updatedAt = Date()
                        await onProgress?(next)
                        continue
                    }
                    let outsideWorkspacePaths = OutsideWorkspaceShellCommandPreflight.offendingPaths(
                        in: activeCall,
                        userMessage: userMessage,
                        workspaceRoot: workspaceRoot
                    )
                    if !outsideWorkspacePaths.isEmpty,
                       preflightCorrectedShellCalls.insert(shellFingerprint).inserted {
                        let paths = outsideWorkspacePaths.prefix(4).joined(separator: ", ")
                        pendingRepeatNudge = """
                        That shell call references path(s) outside the selected workspace: \(paths). \
                        Keep temporary scripts and generated files inside the workspace using \
                        relative paths, then retry the step. Do not request or assume approval for \
                        an outside-workspace path the user did not name.
                        """
                        next.events.append(.init(
                            kind: .notice,
                            summary: "Self-healing: redirected an outside-workspace shell path "
                                + "before approval review."
                        ))
                        next.updatedAt = Date()
                        await onProgress?(next)
                        continue
                    }

                    // Baseline the workspace state before the first tool step, so that step's own
                    // delta is measurable. (Lazy: a .say-only run never pays for a signature.)
                    runLoop.baselineWorkspaceStateIfNeeded(
                        workspaceRoot: workspaceRoot,
                        stateSignature: stateSignature
                    )
                    let step = try await runToolStep(
                        activeCall,
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
                        if let repairPath = pendingSourceGroundingRepairPath,
                           let deniedPath = AgentArtifactVerificationGate.pathArgument(
                            from: completion.call
                           ), AgentArtifactVerificationGate.pathsMatch(repairPath, deniedPath) {
                            pendingSourceGroundingRepairPath = nil
                        }
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
                        if let auditPath = pendingSourceGroundingAuditPath {
                            if completion.result.ok,
                               completion.call.name == ToolDefinition.fileWrite.name,
                               let writtenPath = AgentArtifactVerificationGate.pathArgument(
                                from: completion.call
                               ),
                               AgentArtifactVerificationGate.pathsMatch(auditPath, writtenPath),
                               sourceGroundingAuditCounts[auditPath, default: 0] < 2,
                               let auditedContent = try? ToolArguments(
                                completion.call.argumentsJSON
                               ).requiredString("content"),
                               pendingSourceGroundingAuditBaseline.map({
                                AgentSourceGroundingGate.isMateriallyDifferent(
                                    $0,
                                    auditedContent
                                )
                               }) ?? true {
                                sourceGroundingVerificationPaths.insert(auditPath)
                            }
                            pendingSourceGroundingAuditPath = nil
                            pendingSourceGroundingAuditBaseline = nil
                        }
                        if let repairPath = pendingSourceGroundingRepairPath {
                            if completion.result.ok,
                               completion.call.name == ToolDefinition.fileWrite.name,
                               let writtenPath = AgentArtifactVerificationGate.pathArgument(
                                from: completion.call
                               ), AgentArtifactVerificationGate.pathsMatch(repairPath, writtenPath) {
                                controlledSourceGroundingFinalization = .say(Self.finalAnswer(
                                    for: completion.call,
                                    result: completion.result,
                                    followUpReviewResult: completion.followUpReviewResult
                                ))
                            }
                            pendingSourceGroundingRepairPath = nil
                        }
                        if completion.result.ok,
                           (completion.call.name == ToolDefinition.fileWrite.name
                            || completion.call.name == ToolDefinition.applyPatch.name) {
                            hasCompletedWorkspaceMutation = true
                        }
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

    static func exhaustedActionContinuationPrompt(after call: ToolCall, failure: String) -> String {
        """
        [QuillCode continuation] The successful \(call.name) result is already in the conversation, \
        but your next turn ended with \(failure). Continue the original request now. Return exactly \
        one concrete next tool action; do not repeat the completed call, describe future work, ask \
        for confirmation, or return an empty response. If every requested deliverable already exists, \
        return the concise final answer instead.
        """
    }

    private static func placeholderRepairCall(
        path: String,
        contentsByPath: [String: String]
    ) -> ToolCall? {
        guard let content = contentsByPath[path],
              let repaired = AgentArtifactTextQualityGate.replacingBracketedPlaceholders(
                content: content,
                path: path
              )
        else { return nil }
        return ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": path,
                "content": repaired,
            ])
        )
    }

    private static func malformedTextRepairCall(
        path: String,
        contentsByPath: [String: String]
    ) -> ToolCall? {
        guard let content = contentsByPath[path],
              let repaired = AgentArtifactTextQualityGate.replacingMalformedLiteralEscapes(
                content: content,
                path: path
              )
        else { return nil }
        return ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": path,
                "content": repaired,
            ])
        )
    }

    private static func enumeratedCountRepairCall(
        path: String,
        contentsByPath: [String: String]
    ) -> ToolCall? {
        guard let content = contentsByPath[path],
              let repaired = AgentArtifactTextQualityGate.replacingContradictoryEnumeratedCounts(
                content: content,
                path: path
              )
        else { return nil }
        return ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": path,
                "content": repaired,
            ])
        )
    }

    private static func unsupportedSourceClaimRepairCall(
        path: String,
        contentsByPath: [String: String],
        sourceText: String
    ) -> ToolCall? {
        guard let content = contentsByPath.first(where: {
            AgentArtifactVerificationGate.pathsMatch($0.key, path)
        })?.value,
              let repaired = AgentSourceGroundingGate.removingUnsupportedSensitiveClaims(
                content: content,
                path: path,
                sourceText: sourceText
              )
        else { return nil }
        return ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": path,
                "content": repaired,
            ])
        )
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
