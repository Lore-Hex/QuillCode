import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeSafety
import QuillCodeTools

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum QuillCodeRuntimeMode: String, Codable, Sendable, Hashable {
    case mock
    case trustedRouter
}

public struct QuillCodeRuntime: Sendable {
    public var runner: AgentRunner
    public var contextSummaryGenerator: any WorkspaceContextSummaryGenerating
    public var mode: QuillCodeRuntimeMode
    public var statusLabel: String
    public var trustedRouterAPIKeyConfigured: Bool
    /// The retry decorator records here when it self-heals a transient blip; the model drains it into
    /// a "Self-healing" thread notice. nil for the mock runtime (which never retries).
    public var retryChannel: RetryEventChannel?

    public init(
        runner: AgentRunner,
        contextSummaryGenerator: any WorkspaceContextSummaryGenerating =
            DeterministicWorkspaceContextSummaryGenerator(),
        mode: QuillCodeRuntimeMode,
        statusLabel: String,
        trustedRouterAPIKeyConfigured: Bool = false,
        retryChannel: RetryEventChannel? = nil
    ) {
        self.runner = runner
        self.contextSummaryGenerator = contextSummaryGenerator
        self.mode = mode
        self.statusLabel = statusLabel
        self.trustedRouterAPIKeyConfigured = trustedRouterAPIKeyConfigured
        self.retryChannel = retryChannel
    }
}

public struct QuillCodeRuntimeFactory: Sendable {
    public var paths: QuillCodePaths
    public var distribution: QuillCodeDistribution
    public var environment: [String: String]
    public var modelCatalogURLSession: URLSession
    public var accountCreditsURLSession: URLSession
    private var secretStore: (any QuillSecretStore)?

    public init(
        paths: QuillCodePaths = QuillCodePaths(),
        distribution: QuillCodeDistribution = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        modelCatalogURLSession: URLSession = .shared,
        accountCreditsURLSession: URLSession? = nil,
        secretStore: (any QuillSecretStore)? = nil
    ) {
        self.paths = paths
        self.distribution = distribution
        self.environment = environment
        self.modelCatalogURLSession = modelCatalogURLSession
        self.accountCreditsURLSession = accountCreditsURLSession ?? modelCatalogURLSession
        self.secretStore = secretStore
    }

    public func makeRuntime(config: AppConfig) -> QuillCodeRuntime {
        let config = distribution.enforcing(config)
        if forcedMock {
            return mockRuntime(
                status: QuillCodeRuntimeStatusLabel.mockLLM,
                trustedRouterAPIKeyConfigured: hasTrustedRouterAPIKey()
            )
        }

        let sessionStore = sessionStore()
        let apiKey = configuredAPIKey()
        guard apiKey != nil || sessionStore.hasAPIKey else {
            switch config.authMode {
            case .oauth:
                return mockRuntime(
                    status: QuillCodeRuntimeStatusLabel.signInWithTrustedRouter,
                    trustedRouterAPIKeyConfigured: false
                )
            case .developerOverride:
                return mockRuntime(
                    status: QuillCodeRuntimeStatusLabel.developerKeyNeeded,
                    trustedRouterAPIKeyConfigured: false
                )
            }
        }

        // Wrap the model client so a momentary TrustedRouter 429/5xx or a dropped connection on a
        // single call is retried with backoff instead of killing the whole unattended run. Retry is
        // safe here (the HTTP status error throws before any token is streamed) and covers both the
        // agent run loop and context-summary calls, since both go through this client.
        let requestPrivacy: TrustedRouterRequestPrivacy = distribution.requiresConfidentialRouting
            ? .confidential(jurisdiction: config.confidentialJurisdiction)
            : .standard
        let baseClient = TrustedRouterLLMClient(
            promptBuilder: TrustedRouterPromptBuilder(
                imageAttachmentStore: ImageAttachmentStore(directory: paths.attachmentsDirectory)
            ),
            sessionStore: sessionStore,
            apiKeyOverride: apiKey,
            model: config.defaultModel,
            baseURL: config.apiBaseURL,
            requestPrivacy: requestPrivacy
        )
        // The agent run's client records each self-heal so the model can surface a "Self-healing"
        // thread notice — the run quietly survived a blip and says so.
        let retryChannel = RetryEventChannel()
        let llm = RetryingLLMClient(
            base: baseClient,
            onRetry: { attempt, kind, _ in retryChannel.record(attempt: attempt, kind: kind) }
        )
        // Keep native desktop runs alive when the selected route repeatedly returns clean-but-empty
        // action streams. The agent only consults this client after exhausting the primary route's
        // bounded empty-response recovery, and the per-send context builder removes it entirely for
        // confidential/E2E traffic.
        let fallbackLLM = RetryingLLMClient(
            base: baseClient.overridingModel(
                distribution.requiresConfidentialRouting
                    ? TrustedRouterDefaults.confidentialModel
                    : TrustedRouterDefaults.safetyPrimaryCatalogModel
            ),
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
            baseURL: config.apiBaseURL,
            requestPrivacy: requestPrivacy
        )
        // host.web.search: grounded engines over the SSRF-safe fetch transport first. Brave's
        // server-rendered results are primary; DuckDuckGo is secondary because its HTML endpoint
        // can return a bot challenge. The model-based client remains a last resort, and the
        // downstream liveness filter vets every result.
        let trustedRouterWebSearch = TrustedRouterWebSearchClient(
            sessionStore: sessionStore,
            apiKeyOverride: apiKey,
            model: config.defaultModel,
            baseURL: config.apiBaseURL,
            requestPrivacy: requestPrivacy
        )
        let webSearch: any WebSearchClient = distribution.requiresConfidentialRouting
            ? trustedRouterWebSearch
            : FallbackWebSearchClient(
                primary: BraveWebSearchClient(),
                fallback: FallbackWebSearchClient(
                    primary: DuckDuckGoWebSearchClient(),
                    fallback: trustedRouterWebSearch
                )
            )
        // Compaction (issue #862): when a model call overflows the context window, the run loop folds
        // the thread's older turns into a summary and resumes instead of failing. It reuses the same
        // caching-disabled auxiliary client as context summaries; the aux MODEL is chosen per-compaction
        // from the live catalog inside the runner. The runner is built once and long before the catalog
        // is fetched, so it is seeded with the session model as the fallback and picks a cheaper catalog
        // model whenever one is available at compaction time. Reactive-only by default here (no
        // proactive threshold) so a healthy run pays nothing until the wall is actually hit.
        let compactor = ThreadCompactor.llmBacked(
            llm: summaryLLM,
            catalog: [],
            sessionModelID: config.defaultModel
        )
        return QuillCodeRuntime(
            runner: AgentRunner(
                llm: llm,
                // Auto mode is the DAILY-DRIVER mode: the human picked "just do it". The static
                // policy still falls through to `.clarify` whenever a tool's effect is not
                // lexically implied by the user's own words, which in office work means a plain
                // `python3 --version`, a `pdftotext` probe, or any setup step stops the task dead
                // behind an approval whose stated reason ("does not clearly match the latest user
                // message") means nothing to the person reading it. Observed live in the desktop
                // on the very first coworker task.
                //
                // Headless runs already resolve this with AutonomousApprovalSafetyReviewer;
                // applying it here gives the desktop the same permissiveness. What it does NOT
                // relax: `.deny` verdicts pass through untouched (the hard floors — destructive
                // commands, credential exfiltration — still block), and shell commands touching
                // paths OUTSIDE the workspace are still denied (F24). Containment stays with the
                // hard-deny floors and the filesystem sandbox, not with lexical intent-matching.
                safety: AutonomousApprovalSafetyReviewer(
                    base: AutoSafetyReviewer(
                        client: safetyClient,
                        primaryModel: distribution.requiresConfidentialRouting
                            ? TrustedRouterDefaults.confidentialModel
                            : TrustedRouterDefaults.safetyPrimaryModel,
                        fallbackModel: distribution.requiresConfidentialRouting
                            ? TrustedRouterDefaults.confidentialModel
                            : TrustedRouterDefaults.safetyFallbackModel
                    )
                ),
                webSearch: webSearch,
                webSearchLivenessChecker: WebFetchURLLivenessChecker(),
                maxToolSteps: config.maxToolSteps,
                enablesImmediateActionPreflight: true,
                compaction: AgentCompactionPolicy(compactor: compactor),
                fallbackLLM: fallbackLLM
            ),
            contextSummaryGenerator: LLMWorkspaceContextSummaryGenerator(llm: summaryLLM),
            mode: .trustedRouter,
            statusLabel: config.authMode == .oauth
                ? QuillCodeRuntimeStatusLabel.trustedRouterSignedIn
                : QuillCodeRuntimeStatusLabel.trustedRouterReady,
            trustedRouterAPIKeyConfigured: true,
            retryChannel: retryChannel
        )
    }

    public func fetchModelCatalog(config: AppConfig) async -> TrustedRouterModelCatalog {
        guard !forcedMock else {
            return TrustedRouterModelCatalog()
        }
        let config = distribution.enforcing(config)
        let key = configuredAPIKey() ?? (try? sessionStore().apiKey())
        do {
            return try await TrustedRouterModelCatalogClient(
                apiKey: key,
                baseURL: config.apiBaseURL,
                urlSession: modelCatalogURLSession
            ).fetch()
        } catch {
            return TrustedRouterModelCatalog(status: .fallbackAfterFailure(String(describing: error)))
        }
    }

    public func hasTrustedRouterAPIKey() -> Bool {
        if configuredAPIKey() != nil { return true }
        return sessionStore().hasAPIKey
    }

    public func fetchTrustedRouterCredits(config: AppConfig) async -> TrustedRouterCreditsRefreshResult {
        guard !forcedMock else { return .unavailable }
        let config = distribution.enforcing(config)
        guard let key = configuredAPIKey() ?? (try? sessionStore().apiKey()) else {
            return .unavailable
        }
        let attemptedAt = Date()
        do {
            let snapshot = try await TrustedRouterCreditsClient(
                apiKey: key,
                baseURL: config.apiBaseURL,
                urlSession: accountCreditsURLSession
            ).fetch(fetchedAt: attemptedAt)
            return .success(snapshot)
        } catch {
            return .failure(
                attemptedAt: attemptedAt,
                message: TrustedRouterCreditsClient.userFacingFailure(for: error)
            )
        }
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
        if let key = configuredAPIKeyFileContents() {
            return key
        }
        return nil
    }

    private func configuredAPIKeyFileContents() -> String? {
        let explicitPath = environment["QUILLCODE_API_KEY_FILE"] ?? environment["QUILLCODE_LIVE_KEY_FILE"]
        let fileURL: URL
        if let explicitPath, !explicitPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fileURL = URL(fileURLWithPath: explicitPath.expandingTildeInPath)
        } else {
            fileURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".quill.code.keyfile")
        }
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        let key = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    private func sessionStore() -> SecretTrustedRouterSessionStore {
        SecretTrustedRouterSessionStore(
            secretStore: secretStore ?? QuillSecretStoreFactory.make(for: paths),
            key: QuillSecretKeys.trustedRouterAPIKey
        )
    }

    private func mockRuntime(
        status: String,
        trustedRouterAPIKeyConfigured: Bool
    ) -> QuillCodeRuntime {
        QuillCodeRuntime(
            runner: AgentRunner(),
            contextSummaryGenerator: DeterministicWorkspaceContextSummaryGenerator(),
            mode: .mock,
            statusLabel: status,
            trustedRouterAPIKeyConfigured: trustedRouterAPIKeyConfigured
        )
    }
}

private extension String {
    var expandingTildeInPath: String {
        NSString(string: self).expandingTildeInPath
    }
}
