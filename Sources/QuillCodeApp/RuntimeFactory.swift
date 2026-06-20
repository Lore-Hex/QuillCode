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
    public var mode: QuillCodeRuntimeMode
    public var statusLabel: String

    public init(runner: AgentRunner, mode: QuillCodeRuntimeMode, statusLabel: String) {
        self.runner = runner
        self.mode = mode
        self.statusLabel = statusLabel
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
            return mockRuntime(status: "Mock LLM")
        }

        let secretStore = FileSecretStore(directory: paths.secretsDirectory)
        let sessionStore = SecretTrustedRouterSessionStore(
            secretStore: secretStore,
            key: QuillSecretKeys.trustedRouterAPIKey
        )
        let apiKey = configuredAPIKey()
        guard apiKey != nil || sessionStore.hasAPIKey else {
            return mockRuntime(status: "Mock LLM")
        }

        let llm = TrustedRouterLLMClient(
            sessionStore: sessionStore,
            apiKeyOverride: apiKey,
            model: config.defaultModel,
            baseURL: config.apiBaseURL
        )
        let safetyClient = TrustedRouterSafetyModelClient(
            sessionStore: sessionStore,
            apiKeyOverride: apiKey,
            baseURL: config.apiBaseURL
        )
        return QuillCodeRuntime(
            runner: AgentRunner(
                llm: llm,
                safety: AutoSafetyReviewer(client: safetyClient)
            ),
            mode: .trustedRouter,
            statusLabel: "TrustedRouter ready"
        )
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

    private func mockRuntime(status: String) -> QuillCodeRuntime {
        QuillCodeRuntime(
            runner: AgentRunner(),
            mode: .mock,
            statusLabel: status
        )
    }
}
