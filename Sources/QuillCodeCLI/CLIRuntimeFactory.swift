import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeSafety
import QuillCodeTools

public struct CLIRuntimeConfiguration: Sendable {
    public var request: CLIRunRequest
    public var appConfig: AppConfig
    public var paths: QuillCodePaths
    public var imageAttachmentStore: ImageAttachmentStore
    public var environment: [String: String]

    public init(
        request: CLIRunRequest,
        appConfig: AppConfig,
        paths: QuillCodePaths,
        imageAttachmentStore: ImageAttachmentStore,
        environment: [String: String]
    ) {
        self.request = request
        self.appConfig = appConfig
        self.paths = paths
        self.imageAttachmentStore = imageAttachmentStore
        self.environment = environment
    }

    /// Apply invocation-owned policy after an injected factory creates the runner. Keeping this at
    /// the composition seam ensures production and test factories cannot accidentally disagree.
    public func applyingInvocationPolicy(to runner: AgentRunner) -> AgentRunner {
        var configured = runner
        configured.hostToolAccessScope = request.sandbox == .dangerFullAccess
            ? .unrestricted
            : .workspaceOnly
        return configured
    }
}

public typealias CLIAgentRunnerFactory = @Sendable (CLIRuntimeConfiguration) throws -> AgentRunner

public enum CLIRuntimeFactory {
    public static func make(_ configuration: CLIRuntimeConfiguration) throws -> AgentRunner {
        let request = configuration.request
        let appConfig = configuration.appConfig
        var runner: AgentRunner
        if request.live {
            let sessionStore = SecretTrustedRouterSessionStore(
                secretStore: FileSecretStore(directory: configuration.paths.secretsDirectory),
                key: QuillSecretKeys.trustedRouterAPIKey
            )
            let key = try CLITrustedRouterCredentials.resolve(
                explicit: request.apiKey,
                environment: configuration.environment,
                sessionStore: sessionStore
            )
            let baseURL = request.baseURL ?? appConfig.apiBaseURL
            let model = request.model ?? appConfig.defaultModel
            let llm = TrustedRouterLLMClient(
                promptBuilder: TrustedRouterPromptBuilder(
                    imageAttachmentStore: configuration.imageAttachmentStore
                ),
                sessionStore: sessionStore,
                apiKeyOverride: key,
                model: model,
                baseURL: baseURL
            )
            let safety = TrustedRouterSafetyModelClient(
                sessionStore: sessionStore,
                apiKeyOverride: key,
                baseURL: baseURL
            )
            // Grounded engines first over the SSRF-safe fetch transport. Brave is primary;
            // DuckDuckGo is secondary because its HTML endpoint can return a bot challenge. The
            // model-based client is the final fallback and still passes through liveness checks.
            let webSearch = FallbackWebSearchClient(
                primary: BraveWebSearchClient(),
                fallback: FallbackWebSearchClient(
                    primary: DuckDuckGoWebSearchClient(),
                    fallback: TrustedRouterWebSearchClient(
                        sessionStore: sessionStore,
                        apiKeyOverride: key,
                        model: model,
                        baseURL: baseURL
                    )
                )
            )
            // F22: when the session model exhausts the empty-response budget on a step (a
            // route-quality death observed ~1-in-6 runs on one provider), retry that step once on
            // a different model instead of killing the run. The alternate flips so the fallback is
            // never the same route that just failed.
            //
            // F26 (privacy boundary): NO fallback when the session model is a pinned privacy
            // route — trustedrouter/e2e (confidential enclave) or trustedrouter/zdr (zero data
            // retention). Falling back would silently move the user's sensitive content onto an
            // ordinary route; observed live on an E2E-pinned pulse-survey run before this guard.
            // A privacy-pinned run that cannot proceed fails honestly instead of downgrading.
            let privacyPinnedRoutes: Set<String> = ["trustedrouter/e2e", "trustedrouter/zdr"]
            let fallbackLLM: TrustedRouterLLMClient?
            if privacyPinnedRoutes.contains(model) {
                fallbackLLM = nil
            } else {
                let fallbackModel = model == "google/gemini-3.5-flash"
                    ? "deepseek/deepseek-v4-pro"
                    : "google/gemini-3.5-flash"
                fallbackLLM = TrustedRouterLLMClient(
                    promptBuilder: TrustedRouterPromptBuilder(
                        imageAttachmentStore: configuration.imageAttachmentStore
                    ),
                    sessionStore: sessionStore,
                    apiKeyOverride: key,
                    model: fallbackModel,
                    baseURL: baseURL
                )
            }
            runner = AgentRunner(
                llm: llm,
                safety: AutoSafetyReviewer(client: safety),
                webSearch: webSearch,
                webSearchLivenessChecker: WebFetchURLLivenessChecker(),
                maxToolSteps: appConfig.maxToolSteps,
                enablesImmediateActionPreflight: true,
                compaction: AgentCompactionPolicy(compactor: ThreadCompactor.llmBacked(
                    llm: llm,
                    catalog: [],
                    sessionModelID: model
                )),
                fallbackLLM: fallbackLLM
            )
        } else {
            runner = AgentRunner(
                maxToolSteps: appConfig.maxToolSteps,
                enablesImmediateActionPreflight: true,
                compaction: AgentCompactionPolicy(compactor: ThreadCompactor())
            )
        }
        let skillLocations = request.home == nil
            ? SkillRootLocations.live(quillCodeHome: configuration.paths.home)
            : SkillRootLocations.isolated(quillCodeHome: configuration.paths.home)
        runner.skillResolver = SkillResolver(
            roots: SkillResolver.roots(
                workspaceRoot: request.cwd,
                locations: skillLocations
            ),
            configuration: appConfig.skillConfiguration
        )

        if !request.ignoresPermissionRules {
            runner.safety = PermissionRuleGatedSafetyReviewer(
                base: runner.safety,
                rules: PermissionRuleFileStore(directory: configuration.paths.permissionsDirectory)
            )
        }

        // A headless exec run whose sandbox permits writes is autonomous — it is what --full-auto
        // became. There is no human to answer an approval prompt, so a `.clarify` verdict must not
        // dead-end the whole run at the first unrecognized-but-safe command (a plain `git clone` /
        // `uv venv` during setup). This converts `.clarify` -> `.approve` while leaving hard-deny
        // floors and the filesystem sandbox fully in force. Interactive runs are untouched: the
        // human at the keyboard still gets the approval prompt.
        //
        // F24 exception: under workspace-write, a shell command referencing paths outside the
        // workspace root is honestly DENIED instead of waived (the sandbox does not clamp
        // host.shell.run reads, and the live incident grepped the real ~/Documents). Only
        // --sandbox danger-full-access — an explicit opt-in to full filesystem reach — keeps the
        // waive for out-of-workspace paths.
        if request.style == .exec,
           request.sandbox == .workspaceWrite || request.sandbox == .dangerFullAccess {
            runner.safety = AutonomousApprovalSafetyReviewer(
                base: runner.safety,
                waivesOutsideWorkspacePaths: request.sandbox == .dangerFullAccess
            )
        }
        return runner
    }
}
