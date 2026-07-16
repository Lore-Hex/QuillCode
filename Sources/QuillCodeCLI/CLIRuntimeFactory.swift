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
            let webSearch = TrustedRouterWebSearchClient(
                sessionStore: sessionStore,
                apiKeyOverride: key,
                model: model,
                baseURL: baseURL
            )
            runner = AgentRunner(
                llm: llm,
                safety: AutoSafetyReviewer(client: safety),
                webSearch: webSearch,
                maxToolSteps: appConfig.maxToolSteps,
                enablesImmediateActionPreflight: true,
                compaction: AgentCompactionPolicy(compactor: ThreadCompactor.llmBacked(
                    llm: llm,
                    catalog: [],
                    sessionModelID: model
                ))
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

        guard !request.ignoresPermissionRules else { return runner }
        var gated = runner
        gated.safety = PermissionRuleGatedSafetyReviewer(
            base: runner.safety,
            rules: PermissionRuleFileStore(directory: configuration.paths.permissionsDirectory)
        )
        return gated
    }
}
