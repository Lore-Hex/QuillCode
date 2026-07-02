import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeSafety

public enum QuillCodeRuntimeMode: String, Codable, Sendable, Hashable {
    case mock
    case trustedRouter
}

public struct QuillCodeRuntime: Sendable {
    public var runner: AgentRunner
    public var contextSummaryGenerator: any WorkspaceContextSummaryGenerating
    public var mode: QuillCodeRuntimeMode
    public var statusLabel: String
    /// The retry decorator records here when it self-heals a transient blip; the model drains it into
    /// a "Self-healing" thread notice. nil for the mock runtime (which never retries).
    public var retryChannel: RetryEventChannel?

    public init(
        runner: AgentRunner,
        contextSummaryGenerator: any WorkspaceContextSummaryGenerating =
            DeterministicWorkspaceContextSummaryGenerator(),
        mode: QuillCodeRuntimeMode,
        statusLabel: String,
        retryChannel: RetryEventChannel? = nil
    ) {
        self.runner = runner
        self.contextSummaryGenerator = contextSummaryGenerator
        self.mode = mode
        self.statusLabel = statusLabel
        self.retryChannel = retryChannel
    }
}

public struct QuillCodeRuntimeFactory: Sendable {
    public var paths: QuillCodePaths
    public var environment: [String: String]

    public init(
        paths: QuillCodePaths = QuillCodePaths(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.paths = paths
        self.environment = environment
    }

    public func makeRuntime(config: AppConfig) -> QuillCodeRuntime {
        if forcedMock {
            return mockRuntime(status: QuillCodeRuntimeStatusLabel.mockLLM)
        }

        let sessionStore = sessionStore()
        let apiKey = configuredAPIKey()
        guard apiKey != nil || sessionStore.hasAPIKey else {
            switch config.authMode {
            case .oauth:
                return mockRuntime(status: QuillCodeRuntimeStatusLabel.signInWithTrustedRouter)
            case .developerOverride:
                return mockRuntime(status: QuillCodeRuntimeStatusLabel.developerKeyNeeded)
            }
        }

        // Wrap the model client so a momentary TrustedRouter 429/5xx or a dropped connection on a
        // single call is retried with backoff instead of killing the whole unattended run. Retry is
        // safe here (the HTTP status error throws before any token is streamed) and covers both the
        // agent run loop and context-summary calls, since both go through this client.
        let baseClient = TrustedRouterLLMClient(
            sessionStore: sessionStore,
            apiKeyOverride: apiKey,
            model: config.defaultModel,
            baseURL: config.apiBaseURL
        )
        // The agent run's client records each self-heal so the model can surface a "Self-healing"
        // thread notice — the run quietly survived a blip and says so.
        let retryChannel = RetryEventChannel()
        let llm = RetryingLLMClient(
            base: baseClient,
            onRetry: { attempt, kind, _ in retryChannel.record(attempt: attempt, kind: kind) }
        )
        // Context-summary/compaction calls are one-shot auxiliary housekeeping: each prompt is
        // unique and never re-sent, so a prompt-cache breakpoint on it could only ever be a cache
        // WRITE (billed at 1.25x) with no possible read. The auxiliary-model selector can pick an
        // Anthropic model (it bonus-scores haiku), so we must explicitly opt this path OUT of
        // caching — the run loop keeps it on. Its own retry wrapper carries no onRetry: SILENTLY,
        // because a background summary self-heal is not a run event and must not record to the run
        // channel (that would misattribute it onto the next run's thread).
        let summaryBaseClient = baseClient.disablingPromptCaching()
        let summaryLLM = RetryingLLMClient(base: summaryBaseClient)
        let safetyClient = TrustedRouterSafetyModelClient(
            sessionStore: sessionStore,
            apiKeyOverride: apiKey,
            baseURL: config.apiBaseURL
        )
        // host.web.search routes through the same TrustedRouter credentials as the run loop, so the
        // gateway selects the search provider (issue #861).
        let webSearch = TrustedRouterWebSearchClient(
            sessionStore: sessionStore,
            apiKeyOverride: apiKey,
            model: config.defaultModel,
            baseURL: config.apiBaseURL
        )
        return QuillCodeRuntime(
            runner: AgentRunner(
                llm: llm,
                safety: AutoSafetyReviewer(client: safetyClient),
                webSearch: webSearch,
                enablesImmediateActionPreflight: true
            ),
            contextSummaryGenerator: LLMWorkspaceContextSummaryGenerator(llm: summaryLLM),
            mode: .trustedRouter,
            statusLabel: config.authMode == .oauth
                ? QuillCodeRuntimeStatusLabel.trustedRouterSignedIn
                : QuillCodeRuntimeStatusLabel.trustedRouterReady,
            retryChannel: retryChannel
        )
    }

    public func fetchModelCatalog(config: AppConfig) async -> TrustedRouterModelCatalog {
        guard !forcedMock else {
            return TrustedRouterModelCatalog()
        }
        let key = configuredAPIKey() ?? (try? sessionStore().apiKey())
        guard key?.isEmpty == false else {
            return TrustedRouterModelCatalog()
        }
        do {
            return try await TrustedRouterModelCatalogClient(
                apiKey: key,
                baseURL: config.apiBaseURL
            ).fetch()
        } catch {
            return TrustedRouterModelCatalog(status: .fallbackAfterFailure(String(describing: error)))
        }
    }

    public func hasTrustedRouterAPIKey() -> Bool {
        guard !forcedMock else { return false }
        if configuredAPIKey() != nil { return true }
        return sessionStore().hasAPIKey
    }

    private var forcedMock: Bool {
        let value = environment["QUILLCODE_USE_MOCK_LLM"]?.lowercased()
        return value == "1" || value == "true" || value == "yes"
    }

    private func configuredAPIKey() -> String? {
        let key = environment["QUILLCODE_API_KEY"] ?? environment["TRUSTEDROUTER_API_KEY"]
        if let key, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return key
        }
        return nil
    }

    private func sessionStore() -> SecretTrustedRouterSessionStore {
        SecretTrustedRouterSessionStore(
            secretStore: FileSecretStore(directory: paths.secretsDirectory),
            key: QuillSecretKeys.trustedRouterAPIKey
        )
    }

    private func mockRuntime(status: String) -> QuillCodeRuntime {
        QuillCodeRuntime(
            runner: AgentRunner(),
            contextSummaryGenerator: DeterministicWorkspaceContextSummaryGenerator(),
            mode: .mock,
            statusLabel: status
        )
    }
}
