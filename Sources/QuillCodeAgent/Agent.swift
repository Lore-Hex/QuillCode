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
    /// Once a bounded host enters finalization, individual model turns must leave enough of the
    /// remaining wall-clock reserve for the artifact write and mandatory readback.
    public static let boundedRunFinalizationTurnDeadlineSeconds: TimeInterval = 60
    /// Corrective samples must remain bounded, but complex fallback reasoners need enough room to
    /// turn retained research evidence into a concrete action. The resolver's two-attempt recovery
    /// budget and per-turn deadline still prevent an unbounded correction spiral.
    public static let correctiveActionReasoningCharacterLimit = 12_000
    static let fallbackSwitchNotice = "Self-healing: the model kept returning empty responses; "
        + "switching to the fallback model for this step."
    static let reasoningFallbackSwitchNotice = "Self-healing: the model repeatedly exhausted its "
        + "reasoning budget without acting; switching to the fallback model for this step."
    static let turnDeadlineFallbackSwitchNotice = "Self-healing: the model exhausted its turn "
        + "deadline without acting; switching to the fallback model for this step."
    static let boundedFinalizationFallbackSwitchNotice = "Self-healing: the selected model "
        + "repeatedly rejected the required bounded-finalization action; switching closure to the "
        + "fallback model and retaining the selected route as standby."
    static let promisedWorkCorrectionLimit = 2
    /// A long-running task can encounter passive or empty model turns after many different tools.
    /// Keep this budget scoped to the latest completed tool instead of consuming one allowance for
    /// the entire run. Three run-level continuations, on top of the action resolver's local retry,
    /// are enough to survive a stubborn route while remaining bounded if the model never acts.
    static let exhaustedActionContinuationLimit = 3
    /// Some reasoning-heavy routes can exhaust the action resolver's empty-response retries before
    /// emitting their first action. Give the run loop a few explicit action-only continuations so
    /// a transient startup spiral does not kill an otherwise unattended task.
    static let startupActionContinuationLimit = 3
    /// Bounded recovery for a malformed model action (garbage/mojibake tokens) or a mid-stream
    /// transport reset: re-prompt/re-request up to this many times before the failure is terminal.
    /// One bad sample must not kill an unattended run ([F5/F6] coworker-program findings).
    static let malformedActionCorrectionLimit = 2
    /// Empty streams are transport failures, not malformed model actions. Give the selected route
    /// a separate bounded recovery budget so transient zero-token responses cannot consume the
    /// semantic correction budget or kill an unattended turn during a brief route outage.
    static let emptyResponseRetryLimit = 6

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
    /// Elapsed wall-clock time after which a host-bounded run must stop collecting evidence and
    /// write its named deliverable. nil keeps ordinary interactive desktop runs unbounded.
    public var boundedRunFinalizationAfterSeconds: TimeInterval?
    /// Last-resort model for a step the primary cannot produce at all (F22): when the primary
    /// exhausts the empty-response correction budget — a route-quality failure observed at ~1-in-6
    /// runs on one provider while an alternate model completed the same step first try — the
    /// resolver retries the SAME step once on this client instead of killing the run. All prior
    /// tool work is preserved (same thread); after a successful fallback action that route becomes
    /// active and the displaced route remains as a standby for a later, different failure mode.
    /// Per-step retry limits and the send's tool-step cap keep route recovery bounded. The switch is
    /// recorded as a Self-healing notice.
    /// nil (the default) keeps today's behavior: exhaustion is terminal.
    public var fallbackLLM: LLMClient?
    /// Pauses between clean-but-empty model streams. Immediate resampling can hit the same brief
    /// provider outage three times in a few seconds; the production default uses cancellation-aware
    /// system sleep, while tests can inject a deterministic sleeper.
    public var emptyResponseRetrySleeper: any RetrySleeper

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
        boundedRunFinalizationAfterSeconds: TimeInterval? = nil,
        fallbackLLM: LLMClient? = nil,
        emptyResponseRetrySleeper: any RetrySleeper = SystemRetrySleeper()
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
        self.boundedRunFinalizationAfterSeconds = boundedRunFinalizationAfterSeconds
        self.fallbackLLM = fallbackLLM
        self.emptyResponseRetrySleeper = emptyResponseRetrySleeper
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
            // Route ownership belongs to the whole send, not one action. Once a fallback proves it
            // can produce the next action, this value copy promotes it through subsequent tools and
            // keeps the displaced route as a standby. The thread still preserves the selected model.
            var actionRunner = self
            var runLoop = AgentRunLoopState()
            let runStartedAt = Date()
            var hasEnteredBoundedRunFinalization = false
            var boundedRunFinalizationPath: String?
            /// One successful confirmed research loop may spend the run's reserved finalization
            /// path instead of discarding evidence that is already sufficient for a named artifact.
            var hasRecoveredConfirmedFlailIntoFinalization = false
            /// Mechanical closure actions do not need another model turn once the model has
            /// authored a validator. They still execute through the normal tool and safety path.
            var pendingBoundedRunFinalizationAction: AgentAction?
            var autoReadbackAfterContractAuditPath: String?
            var hasEmittedModelAction = false
            var hasCompletedWorkspaceMutation = false
            /// One-shot corrective for the next sample only (Cline learning #2 repeat nudge).
            var pendingRepeatNudge: String?
            /// Some corrections include the rejected proposal for repair context. Track their stable
            /// violation identity separately so changing invalid code still escalates as one loop.
            var pendingRepeatCorrectionID: String?
            /// Gate-specific limits cannot safely bound their combined effect. Keep one monotonic
            /// budget across consecutive corrective turns and reset it only after a tool executes.
            var correctiveTurnBudget = AgentCorrectiveTurnBudget()
            /// A premature read of a task-named output is redirected once per path. A repeated
            /// attempt is allowed to execute normally so this guard can never create a loop.
            var preWriteVerificationNudgedPaths = Set<String>()
            /// If corrective sampling cannot express a required read after a successful write,
            /// execute that exact read once through the normal tool and safety path.
            var forcedArtifactReadbackPaths = Set<String>()
            /// Unsafe shell paths get one preflight correction per exact call. A repeated proposal
            /// still reaches the approval gate, preserving its authority and bounded termination.
            var preflightCorrectedShellCalls = Set<ToolCallFingerprint>()
            /// A successful tool may be followed by an exhausted empty or passive model turn. Keep a
            /// shared bounded budget for both failure shapes and reset it after the next executed tool,
            /// so one recovered phase cannot make every later phase of a long run less resilient.
            var exhaustedActionContinuationAttempts = 0
            /// Startup recovery is separate from post-tool continuation recovery because there is no
            /// completed call to anchor the latter's prompt or reset semantics yet.
            var startupActionContinuationAttempts = 0
            /// Listing a not-yet-created output directory is predictably unsuccessful. Correct each
            /// exact proposal once, then allow a repeat through so this preflight stays bounded.
            var preflightCorrectedMissingListCalls = Set<ToolCallFingerprint>()
            /// Source paths and data labels are not commands. Redirect each exact model proposal
            /// once after tool work has begun; a repeated proposal still reaches the shell.
            var preflightCorrectedInvalidShellCalls = Set<ToolCallFingerprint>()
            /// Codex-envelope patches are not reversible by the git-diff patch engine. Redirect
            /// each exact proposal once before it becomes a failed tool event.
            var preflightCorrectedInvalidPatchCalls = Set<ToolCallFingerprint>()
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
            /// Markdown sections receive one semantic completion pass, followed by at most one
            /// deterministic removal of headings that remain empty.
            var artifactCompletenessNudgedPaths = Set<String>()
            var artifactCompletenessRepairedPaths = Set<String>()
            /// Aggregate rows with explicit source IDs receive at most two exact reconciliation
            /// passes before the broader semantic source audit takes over.
            var tabularSourceAuditCounts: [String: Int] = [:]
            /// A model that repeatedly declines the required deterministic artifact validator is
            /// stopped honestly instead of spending the full run budget on identical corrections.
            var artifactContractAuditCorrectionCounts: [String: Int] = [:]
            /// Source contradictions get two immediate rewrite opportunities. The deterministic
            /// validator owns the terminal result after that bounded correction budget is spent.
            var sourceContradictionCorrectionCounts: [String: Int] = [:]
            /// Explicitly source-only named artifacts receive one post-draft semantic audit. After
            /// that bounded model pass, deterministic gates own repair, readback, and finalization.
            var sourceGroundingAuditCounts: [String: Int] = [:]
            /// Live evidence gathered after a named text artifact was drafted gets two bounded
            /// opportunities per path to force an incorporated, re-verified final artifact.
            var researchRefreshCorrectionCounts: [String: Int] = [:]
            /// A long read-only research phase gets two bounded opportunities to checkpoint a
            /// named text deliverable before more evidence collection can continue.
            var researchCheckpointCorrectionCounts: [String: Int] = [:]
            /// Repeated serial pre-draft browsing is redirected into one early delegated batch.
            /// This is separate from checkpointing because the worker evidence should arrive first.
            var earlyDelegationCorrectionCounts: [String: Int] = [:]
            /// A forced checkpoint cannot terminate the run until web work resumes and the named
            /// deliverable is rewritten. This budget is separate from checkpoint creation.
            var researchCheckpointContinuationCorrectionCounts: [String: Int] = [:]
            /// Bounded post-checkpoint research must be synthesized before another read-only step.
            var researchCheckpointFinalizationCorrectionCounts: [String: Int] = [:]
            /// After the cumulative post-draft budget, no new direct research may displace final
            /// synthesis. Two exact rewrite requests are followed by deterministic finalization.
            var researchBudgetExhaustionCorrectionCounts: [String: Int] = [:]
            /// Once a delegated batch has returned and a named deliverable exists, redirect one
            /// redundant broad batch into synthesis. Further repeats become terminal candidates
            /// and flow through the ordinary stale-artifact gate without executing the batch.
            var repeatedDelegationNudgedPaths = Set<String>()
            var pendingSourceGroundingAuditPath: String?
            var sourceGroundingRepairedPaths = Set<String>()
            /// A completed semantic audit or deterministic source repair owns finalization. Keeping
            /// this action across the forced readback prevents a fresh model turn from restoring or
            /// contradicting the grounded artifact.
            var controlledSourceGroundingFinalization: AgentAction?
            var pendingSourceGroundingRepairPath: String?
            runLoop.seedArtifactVerification(userMessage: userMessage)
            // F29: URLs from the request and the thread's prior turns are grounded provenance —
            // a follow-up send must not flag citations the previous send legitimately fetched.
            runLoop.seedCitationProvenance(userMessage: userMessage, thread: next)
            runLoop.seedSourceGrounding(userMessage: userMessage)
            var autoReviewCircuit = AutoReviewCircuitBreaker()
            /// One standby rescue does not displace an established route. Two consecutive rescues
            /// show that the active route is currently unhealthy, so the successful standby may
            /// reclaim ownership without letting isolated failures make the clients ping-pong.
            var hasPromotedFallbackRoute = false
            var consecutiveStandbyRecoveries = 0
            let limit = max(1, maxToolSteps)
            let stateSignature = workspaceStateSignature ?? Self.defaultWorkspaceStateSignature

            actionLoop: for _ in 0..<limit {
                if hasEnteredBoundedRunFinalization {
                    boundedRunFinalizationPath = runLoop.boundedRunFinalizationTargetPath()
                }
                if !hasEnteredBoundedRunFinalization,
                   AgentBoundedRunFinalizationGate.shouldEnter(
                    elapsedSeconds: Date().timeIntervalSince(runStartedAt),
                    finalizationAfterSeconds: boundedRunFinalizationAfterSeconds
                   ), tools.contains(where: { $0.name == ToolDefinition.fileWrite.name }),
                   let path = runLoop.boundedRunFinalizationTargetPath() {
                    hasEnteredBoundedRunFinalization = true
                    boundedRunFinalizationPath = path
                    actionRunner.turnDeadlineSeconds = min(
                        actionRunner.turnDeadlineSeconds
                            ?? Self.boundedRunFinalizationTurnDeadlineSeconds,
                        Self.boundedRunFinalizationTurnDeadlineSeconds
                    )
                    pendingRepeatNudge = AgentBoundedRunFinalizationGate.correctionPrompt(
                        path: path,
                        userMessage: userMessage,
                        phase: runLoop.boundedRunFinalizationPhase(at: path),
                        evidenceReceipt: runLoop.latestAuthoritativeEvidenceReceipt
                    )
                    next.events.append(.init(
                        kind: .notice,
                        summary: "Self-healing: entered the bounded run's reserved finalization "
                            + "window and required ./\(path) before more research."
                    ))
                    next.updatedAt = Date()
                    await onProgress?(next)
                }
                let repeatNudge = pendingRepeatNudge
                pendingRepeatNudge = nil
                let repeatCorrectionID = pendingRepeatCorrectionID
                pendingRepeatCorrectionID = nil
                let boundedFinalizationPhase = boundedRunFinalizationPath.map {
                    runLoop.boundedRunFinalizationPhase(at: $0)
                }
                let boundedFinalizationPrompt: String? = if let path = boundedRunFinalizationPath,
                                                            let boundedFinalizationPhase {
                    AgentBoundedRunFinalizationGate.correctionPrompt(
                        path: path,
                        userMessage: userMessage,
                        phase: boundedFinalizationPhase,
                        evidenceReceipt: runLoop.latestAuthoritativeEvidenceReceipt
                    )
                } else {
                    nil
                }
                let isBoundedFinalizationCorrection = repeatNudge != nil
                    && repeatNudge == boundedFinalizationPrompt
                let isSemanticArtifactCorrection = repeatNudge != nil
                    && !isBoundedFinalizationCorrection
                if let repeatNudge,
                   !correctiveTurnBudget.beginCorrectiveTurn(
                    correctionID: repeatCorrectionID ?? repeatNudge
                   ) {
                    if !runLoop.hadDeniedStep,
                       runLoop.researchStaleWorkspacePaths.isEmpty,
                       let readCall = AgentArtifactVerificationGate.requiredReadbackCall(
                        userMessage: userMessage,
                        tools: tools,
                        unverifiedPaths: runLoop.pendingArtifactReadbackWorkspacePaths
                       ), let path = AgentArtifactVerificationGate.pathArgument(from: readCall),
                       forcedArtifactReadbackPaths.insert(path).inserted {
                        pendingBoundedRunFinalizationAction = .tool(readCall)
                        next.events.append(.init(
                            kind: .notice,
                            summary: "Self-healing: corrective sampling could not express the "
                                + "required readback; advanced one exact read of ./\(path) through "
                                + "the normal tool path."
                        ))
                        next.updatedAt = Date()
                        await onProgress?(next)
                        continue actionLoop
                    }
                    let reason = if correctiveTurnBudget.aggregateTurns
                        >= AgentCorrectiveTurnBudget.aggregateLimit {
                        "the model did not produce an executable tool action after "
                            + "\(AgentCorrectiveTurnBudget.aggregateLimit) aggregate corrective "
                            + "turns without an intervening tool"
                    } else {
                        "the model did not produce an executable tool action after "
                            + "\(AgentCorrectiveTurnBudget.limit) consecutive corrective turns "
                            + "for the same required correction"
                    }
                    appendAssistantMessage(
                        "Stopped because \(reason). The partial workspace results were preserved.",
                        to: &next
                    )
                    next.events.append(.init(
                        kind: .notice,
                        summary: "Self-healing: stopped the run because \(reason)."
                    ))
                    next.updatedAt = Date()
                    await onProgress?(next)
                    return AgentRunResult(
                        thread: next,
                        toolResults: runLoop.toolResults,
                        stopReason: .flailDetected(reason: reason)
                    )
                }
                let injectedCorrection: String? = if isBoundedFinalizationCorrection,
                                                     let path = boundedRunFinalizationPath,
                                                     let boundedFinalizationPhase {
                    AgentBoundedRunFinalizationGate.escalatedCorrectionPrompt(
                        path: path,
                        userMessage: userMessage,
                        phase: boundedFinalizationPhase,
                        attempt: correctiveTurnBudget.consecutiveTurns - 1,
                        limit: AgentCorrectiveTurnBudget.limit,
                        evidenceReceipt: runLoop.latestAuthoritativeEvidenceReceipt
                    )
                } else if let repeatNudge {
                    AgentCorrectionEscalation.escalated(
                        repeatNudge,
                        attempt: correctiveTurnBudget.consecutiveTurns - 1,
                        limit: AgentCorrectiveTurnBudget.limit,
                        alternatives: [
                            "emit exactly one executable tool action that directly performs the "
                                + "requested correction; do not explain, summarize, or claim "
                                + "completion",
                        ]
                    )
                } else if hasEnteredBoundedRunFinalization {
                    boundedFinalizationPrompt
                } else {
                    nil
                }
                let reasoningBudgetPhase: AgentReasoningBudgetPhase = if isSemanticArtifactCorrection {
                    .correction
                } else if hasEnteredBoundedRunFinalization,
                          boundedFinalizationPhase == .synthesize {
                    .boundedFinalization
                } else if hasEnteredBoundedRunFinalization {
                    .correction
                } else if !hasEmittedModelAction {
                    .startup
                } else if runLoop.requiresGroundedSynthesisReasoningBudget() {
                    .synthesis
                } else if hasCompletedWorkspaceMutation {
                    .checkpoint
                } else {
                    .synthesis
                }
                let isControlledBoundedRunFinalizationAction =
                    pendingBoundedRunFinalizationAction != nil
                let action: AgentAction
                if let controlledAction = pendingBoundedRunFinalizationAction {
                    pendingBoundedRunFinalizationAction = nil
                    action = controlledAction
                } else if let controlledSourceGroundingFinalization {
                    action = controlledSourceGroundingFinalization
                } else {
                    do {
                        let priorEventIDs = Set(next.events.map(\.id))
                        let absoluteTurnDeadline: Date? = if !hasEnteredBoundedRunFinalization,
                                                            let finalizationAfterSeconds =
                                                                boundedRunFinalizationAfterSeconds,
                                                            finalizationAfterSeconds.isFinite,
                                                            finalizationAfterSeconds >= 0 {
                            runStartedAt.addingTimeInterval(finalizationAfterSeconds)
                        } else {
                            nil
                        }
                        action = try await actionRunner.nextActionCompactingOnOverflow(
                            thread: &next,
                            userMessage: userMessage,
                            tools: tools,
                            workspaceRoot: workspaceRoot,
                            onProgress: onProgress,
                            injectedCorrection: injectedCorrection,
                            reasoningBudgetPhase: reasoningBudgetPhase,
                            emptyResponseRetryPolicy: runLoop.latestCompletion?.result.ok == true
                                ? .afterSuccessfulTool
                                : .standard,
                            absoluteTurnDeadline: absoluteTurnDeadline
                        )
                        let recoveredWithFallback = next.events.contains(where: {
                               !priorEventIDs.contains($0.id)
                                   && ($0.summary == Self.fallbackSwitchNotice
                                       || $0.summary == Self.reasoningFallbackSwitchNotice
                                       || $0.summary == Self.turnDeadlineFallbackSwitchNotice)
                           })
                        if let fallback = actionRunner.fallbackLLM, recoveredWithFallback {
                            if !hasPromotedFallbackRoute {
                                let displacedLLM = actionRunner.llm
                                actionRunner.llm = fallback
                                actionRunner.fallbackLLM = displacedLLM
                                hasPromotedFallbackRoute = true
                                consecutiveStandbyRecoveries = 0
                                next.events.append(.init(
                                    kind: .notice,
                                    summary: "Self-healing: the fallback model completed the step; "
                                        + "promoting that route and retaining the prior route as standby."
                                ))
                            } else {
                                consecutiveStandbyRecoveries += 1
                                if consecutiveStandbyRecoveries >= 2 {
                                    let displacedLLM = actionRunner.llm
                                    actionRunner.llm = fallback
                                    actionRunner.fallbackLLM = displacedLLM
                                    consecutiveStandbyRecoveries = 0
                                    next.events.append(.init(
                                        kind: .notice,
                                        summary: "Self-healing: the standby route recovered two "
                                            + "consecutive failed steps; promoting that route and "
                                            + "retaining the prior route as standby."
                                    ))
                                } else {
                                    next.events.append(.init(
                                        kind: .notice,
                                        summary: "Self-healing: the standby route completed the "
                                            + "step; keeping the established route active unless "
                                            + "another consecutive recovery is required."
                                    ))
                                }
                            }
                            next.updatedAt = Date()
                            await onProgress?(next)
                        } else {
                            consecutiveStandbyRecoveries = 0
                        }
                    } catch AgentError.emptyStreamingResponse {
                        try Task.checkCancellation()
                        if runLoop.latestCompletion == nil, !hasEmittedModelAction {
                            guard startupActionContinuationAttempts
                                    < Self.startupActionContinuationLimit
                            else { throw AgentError.emptyStreamingResponse }
                            startupActionContinuationAttempts += 1
                            pendingRepeatNudge = Self.startupActionContinuationPrompt(
                                attempt: startupActionContinuationAttempts
                            )
                            next.events.append(.init(
                                kind: .notice,
                                summary: "Self-healing: the model produced no actionable startup "
                                    + "response; requested one concrete action "
                                    + "(attempt \(startupActionContinuationAttempts) of "
                                    + "\(Self.startupActionContinuationLimit))."
                            ))
                            next.updatedAt = Date()
                            await onProgress?(next)
                            continue actionLoop
                        }
                        guard let completion = runLoop.latestCompletion else {
                            throw AgentError.emptyStreamingResponse
                        }
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
                        } else if hasCompletedWorkspaceMutation, completion.result.ok {
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
                        } else if exhaustedActionContinuationAttempts
                                    < Self.exhaustedActionContinuationLimit {
                            exhaustedActionContinuationAttempts += 1
                            pendingRepeatNudge = Self.exhaustedActionContinuationPrompt(
                                after: completion.call,
                                failure: "an empty response",
                                attempt: exhaustedActionContinuationAttempts
                            )
                            next.events.append(.init(
                                kind: .notice,
                                summary: "Self-healing: the model returned no action after "
                                    + (completion.result.ok
                                        ? "successful source work"
                                        : "a failed tool result")
                                    + "; requested a concrete continuation "
                                    + "(attempt \(exhaustedActionContinuationAttempts) of "
                                    + "\(Self.exhaustedActionContinuationLimit))."
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
                    } catch {
                        try Task.checkCancellation()
                        let exhaustedActionTurn = error is AgentPreActionReasoningBudgetExceededError
                            || error is AgentTurnDeadlineExceededError
                            || error is AgentReasoningOnlyResponseError
                        let reachedBoundedFinalizationDeadline =
                            AgentBoundedRunFinalizationGate.shouldEnter(
                                elapsedSeconds: Date().timeIntervalSince(runStartedAt),
                                finalizationAfterSeconds: boundedRunFinalizationAfterSeconds
                            )
                        guard exhaustedActionTurn,
                              (runLoop.latestCompletion?.result.ok == true
                               || reachedBoundedFinalizationDeadline),
                              tools.contains(where: { $0.name == ToolDefinition.fileWrite.name }),
                              let path = runLoop.boundedRunFinalizationTargetPath()
                        else { throw error }

                        let enteredEarly = !hasEnteredBoundedRunFinalization
                        // A deadline means `nextAction` already exhausted its bounded wall-clock
                        // samples and alternate route for this step. Re-entering closure resets
                        // those local counters and can otherwise loop until the host kills the run.
                        // Reasoning-budget exhaustion still flows through the shared corrective
                        // budget, which can advance deterministic artifact readback on exhaustion.
                        if error is AgentTurnDeadlineExceededError {
                            guard enteredEarly else { throw error }
                        }
                        hasEnteredBoundedRunFinalization = true
                        boundedRunFinalizationPath = path
                        actionRunner.turnDeadlineSeconds = min(
                            actionRunner.turnDeadlineSeconds
                                ?? Self.boundedRunFinalizationTurnDeadlineSeconds,
                            Self.boundedRunFinalizationTurnDeadlineSeconds
                        )
                        pendingRepeatNudge = AgentBoundedRunFinalizationGate.correctionPrompt(
                            path: path,
                            userMessage: userMessage,
                            phase: runLoop.boundedRunFinalizationPhase(at: path),
                            evidenceReceipt: runLoop.latestAuthoritativeEvidenceReceipt
                        )
                        next.events.append(.init(
                            kind: .notice,
                            summary: enteredEarly
                                ? "Self-healing: the model exhausted its action-turn budget after "
                                    + "successful tool work; moved early into bounded finalization "
                                    + "for ./\(path) using retained evidence."
                                : "Self-healing: the model exhausted its action-turn budget during "
                                    + "bounded finalization for ./\(path); required the next closure "
                                    + "action using retained evidence."
                        ))
                        next.updatedAt = Date()
                        await onProgress?(next)
                        continue actionLoop
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
                    resolvedAction = try await actionRunner.actionByRetryingPromisedWorkIfNeeded(
                        action,
                        thread: next,
                        userMessage: userMessage,
                        tools: tools
                    )
                } catch AgentError.promisedWorkWithoutToolAction {
                    try Task.checkCancellation()
                    guard let completion = runLoop.latestCompletion else {
                        throw AgentError.promisedWorkWithoutToolAction
                    }
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
                        guard exhaustedActionContinuationAttempts
                                < Self.exhaustedActionContinuationLimit
                        else { throw AgentError.promisedWorkWithoutToolAction }
                        exhaustedActionContinuationAttempts += 1
                        pendingRepeatNudge = Self.exhaustedActionContinuationPrompt(
                            after: completion.call,
                            failure: "a passive promise instead of a tool action",
                            attempt: exhaustedActionContinuationAttempts
                        )
                        next.events.append(.init(
                            kind: .notice,
                            summary: "Self-healing: the model stopped at a promise after "
                                + (completion.result.ok
                                    ? "successful tool work"
                                    : "a failed tool result")
                                + "; requested a concrete continuation "
                                + "(attempt \(exhaustedActionContinuationAttempts) of "
                                + "\(Self.exhaustedActionContinuationLimit))."
                        ))
                        next.updatedAt = Date()
                        await onProgress?(next)
                        continue actionLoop
                    }
                }
                if case .say = resolvedAction,
                   let requiredRead = AgentExplicitSourceReadRecovery.nextAction(
                    userMessage: userMessage,
                    workspaceRoot: workspaceRoot,
                    tools: tools,
                    successfullyReadPaths: runLoop.successfullyReadWorkspacePaths
                   ) {
                    resolvedAction = requiredRead
                    next.events.append(.init(
                        kind: .notice,
                        summary: "Self-healing: completed an explicitly required source read "
                            + "before accepting the final answer."
                    ))
                    next.updatedAt = Date()
                    await onProgress?(next)
                }
                if let path = boundedRunFinalizationPath,
                   !AgentBoundedRunFinalizationGate.allows(
                    resolvedAction,
                    deliverablePath: path,
                    phase: runLoop.boundedRunFinalizationPhase(at: path)
                   ), !isControlledBoundedRunFinalizationAction,
                   !(isSemanticArtifactCorrection
                        && AgentBoundedRunFinalizationGate.allowsSemanticAuditReadback(
                            resolvedAction,
                            deliverablePath: path
                        )),
                   !(runLoop.needsContractAuditRepairReadback(at: path)
                        && AgentBoundedRunFinalizationGate.allowsSemanticAuditReadback(
                            resolvedAction,
                            deliverablePath: path
                        )) {
                    pendingRepeatNudge = AgentBoundedRunFinalizationGate.correctionPrompt(
                        path: path,
                        userMessage: userMessage,
                        phase: runLoop.boundedRunFinalizationPhase(at: path),
                        evidenceReceipt: runLoop.latestAuthoritativeEvidenceReceipt
                    )
                    let rejectedAction = switch resolvedAction {
                    case .tool(let call):
                        "tool \(call.name)"
                    case .say:
                        "terminal say"
                    }
                    next.events.append(.init(
                        kind: .notice,
                        summary: "Self-healing: rejected a non-finalization action "
                            + "(\(rejectedAction)) during the bounded run's closure window "
                            + "for ./\(path)."
                    ))
                    // A phase-invalid action is not a route failure. Give the selected model the
                    // exact-path corrective prompt before promoting a fallback; switching after the
                    // first miss discards the route that already owns the evidence and gives a cold
                    // fallback the shortest, most context-heavy turn in the run.
                    if let fallback = actionRunner.fallbackLLM,
                       !hasPromotedFallbackRoute,
                       correctiveTurnBudget.consecutiveTurns
                            >= AgentCorrectiveTurnBudget.limit - 1 {
                        let displacedLLM = actionRunner.llm
                        actionRunner.llm = fallback
                        actionRunner.fallbackLLM = displacedLLM
                        hasPromotedFallbackRoute = true
                        correctiveTurnBudget.recordRoutePromotion()
                        next.events.append(.init(
                            kind: .notice,
                            summary: Self.boundedFinalizationFallbackSwitchNotice
                        ))
                    }
                    next.updatedAt = Date()
                    await onProgress?(next)
                    continue actionLoop
                }
                if let path = boundedRunFinalizationPath,
                   runLoop.boundedRunFinalizationPhase(at: path) == .audit,
                   !isControlledBoundedRunFinalizationAction,
                   case .tool(let proposedCall) = resolvedAction {
                    let isValidatorProposal = AgentBoundedRunFinalizationGate
                        .validatorHelperExecutionCall(
                            after: proposedCall,
                            deliverablePath: path
                        ) != nil
                        || !AgentArtifactContractAuditGate.auditedPaths(
                            for: proposedCall,
                            among: [AgentArtifactVerificationGate.normalizedPath(path)]
                        ).isEmpty
                    if isValidatorProposal,
                       let issue = runLoop.authoritativeEvidenceContradiction(at: path) {
                        if sourceContradictionCorrectionCounts[path, default: 0]
                            >= AgentArtifactContractAuditGate
                                .sourceContradictionCorrectionLimitPerPath {
                            let reason = AgentArtifactContractAuditGate
                                .sourceContradictionExhaustionReason(path: path, issue: issue)
                            appendAssistantMessage(reason, to: &next)
                            next.events.append(.init(
                                kind: .notice,
                                summary: "Self-healing: \(reason)"
                            ))
                            next.updatedAt = Date()
                            await onProgress?(next)
                            return AgentRunResult(
                                thread: next,
                                toolResults: runLoop.toolResults,
                                stopReason: .flailDetected(reason: reason)
                            )
                        }
                        let correctionAttempt = sourceContradictionCorrectionCounts[
                            path,
                            default: 0
                        ]
                        sourceContradictionCorrectionCounts[path, default: 0] += 1
                        pendingRepeatNudge = AgentBoundedRunFinalizationGate
                            .evidenceContradictionCorrectionPrompt(
                                path: path,
                                issue: issue,
                                userMessage: userMessage,
                                evidenceReceipt: runLoop.latestAuthoritativeEvidenceReceipt,
                                attempt: correctionAttempt,
                                limit: AgentArtifactContractAuditGate
                                    .sourceContradictionCorrectionLimitPerPath
                            )
                        next.events.append(.init(
                            kind: .notice,
                            summary: "Self-healing: rejected validation of source-contradictory "
                                + "artifact ./\(path): \(issue)"
                        ))
                        next.updatedAt = Date()
                        await onProgress?(next)
                        continue actionLoop
                    }
                    let missingInputs = AgentBoundedRunFinalizationGate
                        .missingRequiredStructuredInputBindings(
                            in: proposedCall,
                            deliverablePath: path,
                            requiredInputPaths: runLoop.requiredStructuredInputWorkspacePaths
                        )
                    if !missingInputs.isEmpty {
                        pendingRepeatNudge = AgentBoundedRunFinalizationGate
                            .validatorInputBindingCorrectionPrompt(
                                path: path,
                                missingInputPaths: missingInputs,
                                evidenceReceipt: runLoop.latestAuthoritativeEvidenceReceipt,
                                proposedCall: proposedCall
                            )
                        pendingRepeatCorrectionID = AgentBoundedRunFinalizationGate
                            .validatorInputBindingCorrectionID(
                                path: path,
                                missingInputPaths: missingInputs
                            )
                        next.events.append(.init(
                            kind: .notice,
                            summary: "Self-healing: rejected a validator helper that did not "
                                + "parse required structured input "
                                + missingInputs.joined(separator: ", ") + "."
                        ))
                        next.updatedAt = Date()
                        await onProgress?(next)
                        continue actionLoop
                    }
                }
                if case .tool(let proposedCall) = resolvedAction,
                   proposedCall.name == ToolDefinition.subagentsRun.name,
                   runLoop.successfulDelegatedResearchBatchCount > 0,
                   let path = runLoop.writtenNamedTextDeliverablePath() {
                    runLoop.requireResearchRefresh(at: path)
                    if repeatedDelegationNudgedPaths.insert(path).inserted {
                        let correction = AgentResearchCheckpointGate
                            .repeatedDelegationCorrection(path: path)
                        pendingRepeatNudge = correction.prompt
                        next.events.append(.init(
                            kind: .notice,
                            summary: "Self-healing: redirected repeated delegated research into "
                                + "final synthesis at ./\(path)."
                        ))
                        next.updatedAt = Date()
                        await onProgress?(next)
                        continue actionLoop
                    }
                    resolvedAction = .say(
                        "The existing delegated evidence must be synthesized into ./\(path)."
                    )
                }
                if case .tool(let proposedCall) = resolvedAction,
                   let path = runLoop.exhaustedResearchBudgetPath(
                    maximumResearchWeight: AgentResearchCheckpointGate.maximumPostDraftResearchWeight
                   ), AgentResearchCheckpointGate.isResearchCollectionCall(proposedCall) {
                    runLoop.requireResearchRefresh(at: path)
                    if let correction = AgentResearchCheckpointGate.exhaustionCorrection(
                        path: path,
                        proposedToolName: proposedCall.name,
                        proposedCall: proposedCall,
                        canWriteFiles: tools.contains(where: {
                            $0.name == ToolDefinition.fileWrite.name
                        }),
                        userMessage: userMessage,
                        correctionCounts: researchBudgetExhaustionCorrectionCounts
                    ) {
                        researchBudgetExhaustionCorrectionCounts[
                            correction.path,
                            default: 0
                        ] += 1
                        pendingRepeatNudge = correction.prompt
                        next.events.append(.init(
                            kind: .notice,
                            summary: "Self-healing: closed the bounded research phase and requested "
                                + "final synthesis at ./\(correction.path)."
                        ))
                        next.updatedAt = Date()
                        await onProgress?(next)
                        continue actionLoop
                    }
                    resolvedAction = .say(
                        "The bounded research phase is complete; finalize and verify ./\(path)."
                    )
                }
                if case .say = resolvedAction,
                   let correction = AgentResearchCheckpointGate.finalizationCorrection(
                    path: runLoop.pendingResearchFinalizationPath(
                        minimumResearchSteps:
                            AgentResearchCheckpointGate.minimumPostCheckpointResearchSteps
                    ),
                    proposedToolName: nil,
                    proposedToolRisk: .read,
                    canWriteFiles: tools.contains(where: {
                        $0.name == ToolDefinition.fileWrite.name
                    }),
                    userMessage: userMessage,
                    correctionCounts: researchCheckpointFinalizationCorrectionCounts
                   ) {
                    researchCheckpointFinalizationCorrectionCounts[
                        correction.path,
                        default: 0
                    ] += 1
                    pendingRepeatNudge = correction.prompt
                    next.events.append(.init(
                        kind: .notice,
                        summary: "Self-healing: synthesized bounded research into "
                            + "./\(correction.path) before completion."
                    ))
                    next.updatedAt = Date()
                    await onProgress?(next)
                    continue actionLoop
                }
                if case .say = resolvedAction,
                   let correction = AgentArtifactTextQualityGate.correction(
                    userMessage: userMessage,
                    malformedPaths: runLoop.malformedWrittenTextPaths
                   ) {
                    if artifactTextQualityNudgedPaths.insert(correction.path).inserted {
                        controlledSourceGroundingFinalization = nil
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
                        controlledSourceGroundingFinalization = nil
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
                        controlledSourceGroundingFinalization = nil
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
                   let correction = AgentArtifactTextQualityGate.markdownCompletenessCorrection(
                    userMessage: userMessage,
                    incompletePaths: runLoop.incompleteMarkdownWrittenTextPaths
                   ) {
                    if artifactCompletenessNudgedPaths.insert(correction.path).inserted {
                        controlledSourceGroundingFinalization = nil
                        pendingRepeatNudge = correction.prompt
                        next.events.append(.init(
                            kind: .notice,
                            summary: "Self-healing: requested complete Markdown sections for "
                                + "./\(correction.path) before completion."
                        ))
                        next.updatedAt = Date()
                        await onProgress?(next)
                        continue actionLoop
                    }
                    if artifactCompletenessRepairedPaths.insert(correction.path).inserted,
                       let repairCall = Self.incompleteMarkdownRepairCall(
                        path: correction.path,
                        contentsByPath: runLoop.incompleteMarkdownWrittenTextContents
                       ) {
                        resolvedAction = .tool(repairCall)
                        next.events.append(.init(
                            kind: .notice,
                            summary: "Self-healing: removed empty Markdown headings from "
                                + "./\(correction.path) before completion."
                        ))
                        next.updatedAt = Date()
                        await onProgress?(next)
                    }
                }
                if case .say = resolvedAction,
                   let correction = AgentTabularSourceGroundingGate.correction(
                    userMessage: userMessage,
                    issuesByPath: runLoop.tabularSourceIssuesByPath,
                    auditCounts: tabularSourceAuditCounts
                   ) {
                    controlledSourceGroundingFinalization = nil
                    tabularSourceAuditCounts[correction.path, default: 0] += 1
                    pendingRepeatNudge = correction.prompt
                    next.events.append(.init(
                        kind: .notice,
                        summary: "Self-healing: requested tabular source reconciliation for "
                            + "./\(correction.path) before completion."
                    ))
                    next.updatedAt = Date()
                    await onProgress?(next)
                    continue actionLoop
                }
                if case .say = resolvedAction,
                   let checkpointPath = runLoop.pendingResearchContinuationPath(),
                   let correction = AgentResearchCheckpointGate.continuationCorrection(
                    path: checkpointPath,
                    didResumeResearch: runLoop.didResumeResearch(
                        afterCheckpointAt: checkpointPath
                    ),
                    correctionCounts: researchCheckpointContinuationCorrectionCounts
                   ) {
                    researchCheckpointContinuationCorrectionCounts[
                        correction.path,
                        default: 0
                    ] += 1
                    controlledSourceGroundingFinalization = nil
                    pendingRepeatNudge = correction.prompt
                    next.events.append(.init(
                        kind: .notice,
                        summary: "Self-healing: continued research after the checkpoint at "
                            + "./\(correction.path)."
                    ))
                    next.updatedAt = Date()
                    await onProgress?(next)
                    continue actionLoop
                }
                if case .say = resolvedAction,
                   let correction = AgentSourceGroundingGate.correction(
                    userMessage: userMessage,
                    writtenPaths: runLoop.writtenWorkspacePaths,
                    auditCounts: sourceGroundingAuditCounts
                   ) {
                    controlledSourceGroundingFinalization = nil
                    sourceGroundingAuditCounts[correction.path, default: 0] += 1
                    pendingSourceGroundingAuditPath = correction.path
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
                if case .say = resolvedAction,
                   let correction = AgentResearchRefreshGate.correction(
                    stalePaths: runLoop.researchStaleWorkspacePaths,
                    correctionCounts: researchRefreshCorrectionCounts
                   ) {
                    researchRefreshCorrectionCounts[correction.path, default: 0] += 1
                    controlledSourceGroundingFinalization = nil
                    pendingRepeatNudge = correction.prompt
                    next.events.append(.init(
                        kind: .notice,
                        summary: "Self-healing: requested a post-research refresh of "
                            + "./\(correction.path) before completion."
                    ))
                    next.updatedAt = Date()
                    await onProgress?(next)
                    continue actionLoop
                }
                if case .say = resolvedAction,
                   !runLoop.hadDeniedStep,
                   let path = runLoop.pendingArtifactContractAuditPath(),
                   let correction = AgentArtifactContractAuditGate.correction(
                    path: path,
                    tools: tools,
                    correctionCount: artifactContractAuditCorrectionCounts[path, default: 0],
                    userMessage: userMessage,
                    evidenceReceipt: runLoop.latestAuthoritativeEvidenceReceipt,
                    failedAuditReceipt: runLoop.failedContractAuditReceipt(at: path)
                   ) {
                    controlledSourceGroundingFinalization = nil
                    artifactContractAuditCorrectionCounts[path, default: 0] += 1
                    pendingRepeatNudge = correction.prompt
                    next.events.append(.init(
                        kind: .notice,
                        summary: "Self-healing: required a deterministic contract audit for "
                            + "./\(correction.path) before completion."
                    ))
                    next.updatedAt = Date()
                    await onProgress?(next)
                    continue actionLoop
                }
                if case .say = resolvedAction,
                   !runLoop.hadDeniedStep,
                   let path = runLoop.pendingArtifactContractAuditPath(),
                   artifactContractAuditCorrectionCounts[path, default: 0]
                    >= AgentArtifactContractAuditGate.correctionLimitPerPath {
                    let reason = AgentArtifactContractAuditGate.exhaustionReason(path: path)
                    appendAssistantMessage(reason, to: &next)
                    next.events.append(.init(kind: .notice, summary: "Self-healing: \(reason)"))
                    next.updatedAt = Date()
                    await onProgress?(next)
                    return AgentRunResult(
                        thread: next,
                        toolResults: runLoop.toolResults,
                        stopReason: .flailDetected(reason: reason)
                    )
                }
                // F23: a terminal say may not end the run while a task-named created file is
                // missing on disk. A corrective re-sample that returns a tool action flows into
                // the tool arm below and the loop continues; the gate re-checks at the next say.
                // Skipped when any tool action was denied this run — a blocked write is a
                // legitimate reason for the file to be missing, not a model failure.
                if !runLoop.hadDeniedStep {
                    resolvedAction = try await actionRunner.actionByRequiringNamedDeliverables(
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
                    resolvedAction = try await actionRunner.actionByRequiringCitationIntegrity(
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
                    resolvedAction = try await actionRunner.actionByRequiringWordBudget(
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
                        unverifiedPaths: runLoop.pendingArtifactReadbackWorkspacePaths
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
                    if let path = boundedRunFinalizationPath,
                       runLoop.boundedRunFinalizationPhase(at: path) == .audit,
                       runLoop.isUnchangedFailedContractAuditReplay(activeCall, at: path) {
                        pendingRepeatNudge = AgentBoundedRunFinalizationGate
                            .failedAuditReplayCorrectionPrompt(
                                path: path,
                                failedAuditReceipt: runLoop.failedContractAuditReceipt(at: path),
                                evidenceReceipt: runLoop.latestAuthoritativeEvidenceReceipt
                            )
                        next.events.append(.init(
                            kind: .notice,
                            summary: "Self-healing: rejected an unchanged failed validator for "
                                + "./\(path) and required a deliverable or validator repair."
                        ))
                        next.updatedAt = Date()
                        await onProgress?(next)
                        continue actionLoop
                    }
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
                        if let requiredRead = AgentExplicitSourceReadRecovery.nextAction(
                            userMessage: userMessage,
                            workspaceRoot: workspaceRoot,
                            tools: tools,
                            successfullyReadPaths: runLoop.successfullyReadWorkspacePaths
                        ) {
                            finalized = requiredRead
                            next.events.append(.init(
                                kind: .notice,
                                summary: "Self-healing: completed an explicitly required source read "
                                    + "before accepting the final answer."
                            ))
                            next.updatedAt = Date()
                            await onProgress?(next)
                        }
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
                        if case .say = finalized,
                           let correction = AgentArtifactTextQualityGate.markdownCompletenessCorrection(
                            userMessage: userMessage,
                            incompletePaths: runLoop.incompleteMarkdownWrittenTextPaths
                           ) {
                            if artifactCompletenessNudgedPaths.insert(correction.path).inserted {
                                pendingRepeatNudge = correction.prompt
                                next.events.append(.init(
                                    kind: .notice,
                                    summary: "Self-healing: requested complete Markdown sections for "
                                        + "./\(correction.path) before completion."
                                ))
                                next.updatedAt = Date()
                                await onProgress?(next)
                                continue actionLoop
                            }
                            if artifactCompletenessRepairedPaths.insert(correction.path).inserted,
                               let repairCall = Self.incompleteMarkdownRepairCall(
                                path: correction.path,
                                contentsByPath: runLoop.incompleteMarkdownWrittenTextContents
                               ) {
                                finalized = .tool(repairCall)
                                next.events.append(.init(
                                    kind: .notice,
                                    summary: "Self-healing: removed empty Markdown headings from "
                                        + "./\(correction.path) before completion."
                                ))
                                next.updatedAt = Date()
                                await onProgress?(next)
                            }
                        }
                        if let correction = AgentTabularSourceGroundingGate.correction(
                            userMessage: userMessage,
                            issuesByPath: runLoop.tabularSourceIssuesByPath,
                            auditCounts: tabularSourceAuditCounts
                        ) {
                            tabularSourceAuditCounts[correction.path, default: 0] += 1
                            pendingRepeatNudge = correction.prompt
                            next.events.append(.init(
                                kind: .notice,
                                summary: "Self-healing: requested tabular source reconciliation for "
                                    + "./\(correction.path) before completion."
                            ))
                            next.updatedAt = Date()
                            await onProgress?(next)
                            continue actionLoop
                        }
                        if let checkpointPath = runLoop.pendingResearchContinuationPath(),
                           let correction = AgentResearchCheckpointGate.continuationCorrection(
                            path: checkpointPath,
                            didResumeResearch: runLoop.didResumeResearch(
                                afterCheckpointAt: checkpointPath
                            ),
                            correctionCounts: researchCheckpointContinuationCorrectionCounts
                           ) {
                            researchCheckpointContinuationCorrectionCounts[
                                correction.path,
                                default: 0
                            ] += 1
                            pendingRepeatNudge = correction.prompt
                            next.events.append(.init(
                                kind: .notice,
                                summary: "Self-healing: continued research after the checkpoint at "
                                    + "./\(correction.path)."
                            ))
                            next.updatedAt = Date()
                            await onProgress?(next)
                            continue actionLoop
                        }
                        if let correction = AgentSourceGroundingGate.correction(
                            userMessage: userMessage,
                            writtenPaths: runLoop.writtenWorkspacePaths,
                            auditCounts: sourceGroundingAuditCounts
                        ) {
                            sourceGroundingAuditCounts[correction.path, default: 0] += 1
                            pendingSourceGroundingAuditPath = correction.path
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
                        if let correction = AgentResearchRefreshGate.correction(
                            stalePaths: runLoop.researchStaleWorkspacePaths,
                            correctionCounts: researchRefreshCorrectionCounts
                        ) {
                            researchRefreshCorrectionCounts[correction.path, default: 0] += 1
                            pendingRepeatNudge = correction.prompt
                            next.events.append(.init(
                                kind: .notice,
                                summary: "Self-healing: requested a post-research refresh of "
                                    + "./\(correction.path) before completion."
                            ))
                            next.updatedAt = Date()
                            await onProgress?(next)
                            continue actionLoop
                        }
                        if case .say = finalized,
                           !runLoop.hadDeniedStep,
                           let path = runLoop.pendingArtifactContractAuditPath(),
                           let correction = AgentArtifactContractAuditGate.correction(
                            path: path,
                            tools: tools,
                            correctionCount:
                                artifactContractAuditCorrectionCounts[path, default: 0],
                            userMessage: userMessage,
                            evidenceReceipt: runLoop.latestAuthoritativeEvidenceReceipt,
                            failedAuditReceipt: runLoop.failedContractAuditReceipt(at: path)
                           ) {
                            artifactContractAuditCorrectionCounts[path, default: 0] += 1
                            pendingRepeatNudge = correction.prompt
                            next.events.append(.init(
                                kind: .notice,
                                summary: "Self-healing: required a deterministic contract audit for "
                                    + "./\(correction.path) before completion."
                            ))
                            next.updatedAt = Date()
                            await onProgress?(next)
                            continue actionLoop
                        }
                        if case .say = finalized,
                           !runLoop.hadDeniedStep,
                           let path = runLoop.pendingArtifactContractAuditPath(),
                           artifactContractAuditCorrectionCounts[path, default: 0]
                            >= AgentArtifactContractAuditGate.correctionLimitPerPath {
                            let reason = AgentArtifactContractAuditGate.exhaustionReason(path: path)
                            appendAssistantMessage(reason, to: &next)
                            next.events.append(.init(
                                kind: .notice,
                                summary: "Self-healing: \(reason)"
                            ))
                            next.updatedAt = Date()
                            await onProgress?(next)
                            return AgentRunResult(
                                thread: next,
                                toolResults: runLoop.toolResults,
                                stopReason: .flailDetected(reason: reason)
                            )
                        }
                        if !runLoop.hadDeniedStep {
                            finalized = try await actionRunner.actionByRequiringNamedDeliverables(
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
                            finalized = try await actionRunner.actionByRequiringCitationIntegrity(
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
                            finalized = try await actionRunner.actionByRequiringWordBudget(
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
                                unverifiedPaths: runLoop.pendingArtifactReadbackWorkspacePaths
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

                    let patchFingerprint = ToolCallFingerprint.make(
                        name: activeCall.name,
                        argumentsJSON: activeCall.argumentsJSON
                    )
                    if let correction = AgentInvalidPatchProposalPreflight.correction(for: activeCall),
                       preflightCorrectedInvalidPatchCalls.insert(patchFingerprint).inserted {
                        pendingRepeatNudge = correction.prompt
                        next.events.append(.init(kind: .notice, summary: correction.summary))
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

                    if let correction = AgentResearchCheckpointGate.earlyDelegationCorrection(
                        path: runLoop.pendingResearchCheckpointPath(
                            minimumResearchWeight:
                                AgentResearchCheckpointGate.minimumDirectResearchBeforeDelegation
                        ),
                        proposedToolName: activeCall.name,
                        proposedCall: activeCall,
                        canDelegate: tools.contains(where: {
                            $0.name == ToolDefinition.subagentsRun.name
                        }),
                        canWriteFiles: tools.contains(where: {
                            $0.name == ToolDefinition.fileWrite.name
                        }),
                        hasDelegatedResearch: runLoop.successfulDelegatedResearchBatchCount > 0,
                        hasSubstantialStructuredDirectEvidence:
                            runLoop.hasSubstantialStructuredDirectResearchEvidence,
                        correctionCounts: earlyDelegationCorrectionCounts
                    ) {
                        earlyDelegationCorrectionCounts[correction.path, default: 0] += 1
                        pendingRepeatNudge = correction.prompt
                        next.events.append(.init(
                            kind: .notice,
                            summary: "Self-healing: redirected serial pre-draft research into "
                                + "early parallel delegation for ./\(correction.path)."
                        ))
                        next.updatedAt = Date()
                        await onProgress?(next)
                        continue
                    }

                    // A completed checkpoint research phase needs the stronger original-request
                    // synthesis prompt. Run it before the generic stale-artifact refresh so a
                    // delegated batch cannot be reconciled as another provisional status update.
                    if let correction = AgentResearchCheckpointGate.finalizationCorrection(
                        path: runLoop.pendingResearchFinalizationPath(
                            minimumResearchSteps:
                                AgentResearchCheckpointGate.minimumPostCheckpointResearchSteps
                        ),
                        proposedToolName: activeCall.name,
                        proposedCall: activeCall,
                        proposedToolRisk: tools.first(where: {
                            $0.name == activeCall.name
                        })?.risk,
                        canWriteFiles: tools.contains(where: {
                            $0.name == ToolDefinition.fileWrite.name
                        }),
                        userMessage: userMessage,
                        correctionCounts: researchCheckpointFinalizationCorrectionCounts
                    ) {
                        researchCheckpointFinalizationCorrectionCounts[
                            correction.path,
                            default: 0
                        ] += 1
                        pendingRepeatNudge = correction.prompt
                        next.events.append(.init(
                            kind: .notice,
                            summary: "Self-healing: synthesized post-checkpoint research into "
                                + "./\(correction.path) before further browsing."
                        ))
                        next.updatedAt = Date()
                        await onProgress?(next)
                        continue
                    }

                    if let correction = AgentResearchRefreshGate.correctionBeforeNonResearchRead(
                        stalePaths: runLoop.researchStaleWorkspacePaths,
                        proposedToolName: activeCall.name,
                        proposedToolRisk: tools.first(where: {
                            $0.name == activeCall.name
                        })?.risk,
                        canWriteFiles: tools.contains(where: {
                            $0.name == ToolDefinition.fileWrite.name
                        }),
                        correctionCounts: researchRefreshCorrectionCounts
                    ) {
                        researchRefreshCorrectionCounts[correction.path, default: 0] += 1
                        pendingRepeatNudge = correction.prompt
                        next.events.append(.init(
                            kind: .notice,
                            summary: "Self-healing: required an immediate post-research refresh of "
                                + "./\(correction.path) before local inspection."
                        ))
                        next.updatedAt = Date()
                        await onProgress?(next)
                        continue
                    }

                    if let correction = AgentResearchCheckpointGate.correction(
                        path: runLoop.pendingResearchCheckpointPath(
                            minimumResearchWeight:
                                AgentResearchCheckpointGate.minimumPreDraftResearchWeight
                        ),
                        proposedToolName: activeCall.name,
                        proposedCall: activeCall,
                        proposedToolRisk: tools.first(where: {
                            $0.name == activeCall.name
                        })?.risk,
                        canWriteFiles: tools.contains(where: {
                            $0.name == ToolDefinition.fileWrite.name
                        }),
                        correctionCounts: researchCheckpointCorrectionCounts
                    ) {
                        researchCheckpointCorrectionCounts[correction.path, default: 0] += 1
                        runLoop.expectResearchCheckpoint(at: correction.path)
                        pendingRepeatNudge = correction.prompt
                        next.events.append(.init(
                            kind: .notice,
                            summary: "Self-healing: required a durable research checkpoint at "
                                + "./\(correction.path) before more read-only work."
                        ))
                        next.updatedAt = Date()
                        await onProgress?(next)
                        continue
                    }

                    if tools.first(where: { $0.name == activeCall.name })?.risk != .read,
                       let requiredRead = AgentExplicitSourceReadRecovery.nextAction(
                        userMessage: userMessage,
                        workspaceRoot: workspaceRoot,
                        tools: tools,
                        successfullyReadPaths: runLoop.successfullyReadWorkspacePaths
                       ), case .tool(let requiredReadCall) = requiredRead {
                        activeCall = requiredReadCall
                        next.events.append(.init(
                            kind: .notice,
                            summary: "Self-healing: completed an explicitly required source read "
                                + "before the first pending mutation."
                        ))
                        next.updatedAt = Date()
                        await onProgress?(next)
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
                        // The model emitted and executed a new concrete action. Recovery for the next
                        // turn starts fresh even when this tool reports a failure: its feedback is new
                        // information the model must be allowed to act on.
                        correctiveTurnBudget.recordExecutedTool()
                        exhaustedActionContinuationAttempts = 0
                        if let auditPath = pendingSourceGroundingAuditPath {
                            if completion.result.ok,
                               (completion.call.name == ToolDefinition.fileWrite.name
                                || completion.call.name == ToolDefinition.fileRead.name),
                               let completedPath = AgentArtifactVerificationGate.pathArgument(
                                from: completion.call
                               ),
                               AgentArtifactVerificationGate.pathsMatch(auditPath, completedPath) {
                                controlledSourceGroundingFinalization = .say(
                                    "Completed and verified `\(auditPath)`."
                                )
                            }
                            pendingSourceGroundingAuditPath = nil
                        }
                        if let repairPath = pendingSourceGroundingRepairPath {
                            if completion.result.ok,
                               completion.call.name == ToolDefinition.fileWrite.name,
                               let writtenPath = AgentArtifactVerificationGate.pathArgument(
                                from: completion.call
                               ), AgentArtifactVerificationGate.pathsMatch(repairPath, writtenPath) {
                                controlledSourceGroundingFinalization =
                                    controlledSourceGroundingFinalization
                                    ?? .say(Self.finalAnswer(
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
                        if boundedRunFinalizationAfterSeconds.map({
                            $0.isFinite && $0 >= 0
                           }) == true,
                           completion.result.ok,
                           let auditPath = runLoop.pendingArtifactContractAuditPath(),
                           AgentBoundedRunFinalizationGate.isDeliverableMutation(
                            completion.call,
                            deliverablePath: auditPath
                           ) {
                            let justEnteredFinalization = !hasEnteredBoundedRunFinalization
                            if justEnteredFinalization {
                                hasEnteredBoundedRunFinalization = true
                                boundedRunFinalizationPath = auditPath
                                actionRunner.turnDeadlineSeconds = min(
                                    actionRunner.turnDeadlineSeconds
                                        ?? Self.boundedRunFinalizationTurnDeadlineSeconds,
                                    Self.boundedRunFinalizationTurnDeadlineSeconds
                                )
                            }
                            if let issue = runLoop.authoritativeEvidenceContradiction(at: auditPath) {
                                if sourceContradictionCorrectionCounts[auditPath, default: 0]
                                    >= AgentArtifactContractAuditGate
                                        .sourceContradictionCorrectionLimitPerPath {
                                    let reason = AgentArtifactContractAuditGate
                                        .sourceContradictionExhaustionReason(
                                            path: auditPath,
                                            issue: issue
                                        )
                                    appendAssistantMessage(reason, to: &next)
                                    next.events.append(.init(
                                        kind: .notice,
                                        summary: "Self-healing: \(reason)"
                                    ))
                                    next.updatedAt = Date()
                                    await onProgress?(next)
                                    return AgentRunResult(
                                        thread: next,
                                        toolResults: runLoop.toolResults,
                                        stopReason: .flailDetected(reason: reason)
                                    )
                                }
                                let correctionAttempt = sourceContradictionCorrectionCounts[
                                    auditPath,
                                    default: 0
                                ]
                                sourceContradictionCorrectionCounts[auditPath, default: 0] += 1
                                pendingRepeatNudge = AgentBoundedRunFinalizationGate
                                    .evidenceContradictionCorrectionPrompt(
                                        path: auditPath,
                                        issue: issue,
                                        userMessage: userMessage,
                                        evidenceReceipt: runLoop.latestAuthoritativeEvidenceReceipt,
                                        attempt: correctionAttempt,
                                        limit: AgentArtifactContractAuditGate
                                            .sourceContradictionCorrectionLimitPerPath
                                    )
                                next.events.append(.init(
                                    kind: .notice,
                                    summary: "Self-healing: rejected source-contradictory artifact "
                                        + "immediately after updating ./\(auditPath): \(issue)"
                                ))
                                next.updatedAt = Date()
                                await onProgress?(next)
                            } else if justEnteredFinalization {
                                pendingRepeatNudge = AgentBoundedRunFinalizationGate.correctionPrompt(
                                    path: auditPath,
                                    userMessage: userMessage,
                                    phase: .audit,
                                    evidenceReceipt: runLoop.latestAuthoritativeEvidenceReceipt
                                )
                                next.events.append(.init(
                                    kind: .notice,
                                    summary: "Self-healing: entered deterministic contract audit "
                                        + "immediately after writing ./\(auditPath)."
                                ))
                                next.updatedAt = Date()
                                await onProgress?(next)
                            }
                        }
                        if !completion.result.ok,
                           let path = runLoop.pendingArtifactContractAuditPath(),
                           runLoop.needsContractAuditRepairReadback(at: path),
                           tools.contains(where: { $0.name == ToolDefinition.fileRead.name }) {
                            pendingBoundedRunFinalizationAction = .tool(ToolCall(
                                name: ToolDefinition.fileRead.name,
                                argumentsJSON: ToolArguments.json(["path": path])
                            ))
                            next.events.append(.init(
                                kind: .notice,
                                summary: "Self-healing: the failed validator left ./\(path) on "
                                    + "disk; advanced one exact repair read before allowing a "
                                    + "rewrite."
                            ))
                            next.updatedAt = Date()
                            await onProgress?(next)
                        }
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
                            if !hasRecoveredConfirmedFlailIntoFinalization,
                               !hasEnteredBoundedRunFinalization,
                               completion.result.ok,
                               tools.contains(where: { $0.name == ToolDefinition.fileWrite.name }),
                               let path = runLoop.boundedRunFinalizationTargetPath() {
                                hasRecoveredConfirmedFlailIntoFinalization = true
                                hasEnteredBoundedRunFinalization = true
                                boundedRunFinalizationPath = path
                                actionRunner.turnDeadlineSeconds = min(
                                    actionRunner.turnDeadlineSeconds
                                        ?? Self.boundedRunFinalizationTurnDeadlineSeconds,
                                    Self.boundedRunFinalizationTurnDeadlineSeconds
                                )
                                runLoop.resetFlailDetectorAfterRecovery()
                                pendingRepeatNudge = AgentBoundedRunFinalizationGate
                                    .correctionPrompt(
                                        path: path,
                                        userMessage: userMessage,
                                        phase: runLoop.boundedRunFinalizationPhase(at: path),
                                        evidenceReceipt: runLoop.latestAuthoritativeEvidenceReceipt
                                    )
                                next.events.append(.init(
                                    kind: .notice,
                                    summary: "Self-healing: stopped repeated research and moved "
                                        + "early into bounded finalization for ./\(path) using "
                                        + "the retained evidence."
                                ))
                                next.updatedAt = Date()
                                await onProgress?(next)
                                continue actionLoop
                            }
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
                        if let path = boundedRunFinalizationPath,
                           completion.result.ok,
                           let validatorCall = AgentBoundedRunFinalizationGate
                            .validatorHelperExecutionCall(
                                after: completion.call,
                                deliverablePath: path
                            ), runLoop.boundedRunFinalizationPhase(at: path) == .audit {
                            pendingBoundedRunFinalizationAction = .tool(validatorCall)
                            next.events.append(.init(
                                kind: .notice,
                                summary: "Self-healing: executed the authored validator helper "
                                    + "without spending another model turn."
                            ))
                            next.updatedAt = Date()
                            await onProgress?(next)
                        } else if let path = boundedRunFinalizationPath,
                                  completion.result.ok,
                                  !AgentArtifactContractAuditGate.auditedPaths(
                                    for: completion.call,
                                    among: [AgentArtifactVerificationGate.normalizedPath(path)]
                                  ).isEmpty {
                            switch runLoop.boundedRunFinalizationPhase(at: path) {
                            case .readback:
                                autoReadbackAfterContractAuditPath = path
                                pendingBoundedRunFinalizationAction = .say(
                                    "Completed and verified `\(path)`."
                                )
                                next.events.append(.init(
                                    kind: .notice,
                                    summary: "Self-healing: the deterministic audit passed; "
                                        + "advanced through terminal quality gates without "
                                        + "spending another model turn."
                                ))
                                next.updatedAt = Date()
                                await onProgress?(next)
                            case .complete:
                                pendingBoundedRunFinalizationAction = .say(
                                    "Completed and verified `\(path)`."
                                )
                            case .synthesize, .audit:
                                break
                            }
                        } else if let path = autoReadbackAfterContractAuditPath,
                                  completion.result.ok,
                                  AgentBoundedRunFinalizationGate.allows(
                                    .tool(completion.call),
                                    deliverablePath: path,
                                    phase: .readback
                                  ), runLoop.boundedRunFinalizationPhase(at: path) == .complete {
                            autoReadbackAfterContractAuditPath = nil
                            pendingBoundedRunFinalizationAction = .say(
                                "Completed and verified `\(path)`."
                            )
                            next.events.append(.init(
                                kind: .notice,
                                summary: "Self-healing: the audited artifact readback succeeded; "
                                    + "completed the bounded run without another model turn."
                            ))
                            next.updatedAt = Date()
                            await onProgress?(next)
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

    static func exhaustedActionContinuationPrompt(
        after call: ToolCall,
        failure: String,
        attempt: Int
    ) -> String {
        """
        [QuillCode continuation \(attempt) of \(exhaustedActionContinuationLimit)] The \(call.name) \
        result, including any reported failure, is already in the conversation, but your next turn \
        ended with \(failure). \
        Do not plan, narrate, or announce what you will do. Emit exactly one QuillCode JSON object now. \
        Unless every requested deliverable already exists and has been verified, that object MUST be a \
        concrete next {"type":"tool",...} action with complete arguments. Do not repeat the completed \
        call, ask for confirmation, or return an empty response. Only when all work is actually complete \
        may you return a concise {"type":"say",...} final answer.
        """
    }

    static func startupActionContinuationPrompt(attempt: Int) -> String {
        """
        [QuillCode startup recovery \(attempt) of \(startupActionContinuationLimit)] Your previous \
        attempts produced no actionable QuillCode response. Do not plan, narrate, explain, or announce \
        what you will do. Emit exactly one QuillCode JSON object now. Start the requested work with a \
        concrete {"type":"tool",...} action using complete arguments. If a required source is \
        unavailable, emit a concise {"type":"say",...} response naming the exact blocker. Never \
        return only reasoning or an empty response.
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

    private static func incompleteMarkdownRepairCall(
        path: String,
        contentsByPath: [String: String]
    ) -> ToolCall? {
        guard let content = contentsByPath[path],
              let repaired = AgentArtifactTextQualityGate.removingEmptyMarkdownSections(
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
