import Foundation
import QuillCodeCore

public enum CLIInvocationStyle: Sendable, Equatable {
    case legacy
    case exec
}

public enum CLISandboxMode: String, Sendable, Equatable, CaseIterable {
    case readOnly = "read-only"
    case workspaceWrite = "workspace-write"
    case dangerFullAccess = "danger-full-access"

    var agentMode: AgentMode {
        switch self {
        case .readOnly:
            .readOnly
        case .workspaceWrite, .dangerFullAccess:
            .auto
        }
    }
}

public enum CLIResumeTarget: Sendable, Equatable {
    case last
    case id(UUID)
}

public struct CLIRunRequest: Sendable, Equatable {
    public var style: CLIInvocationStyle
    public var prompt: String
    public var resumeTarget: CLIResumeTarget?
    public var live: Bool
    public var apiKey: String?
    public var model: String?
    public var baseURL: String?
    public var cwd: URL
    public var home: URL?
    public var imageURLs: [URL]
    public var ephemeral: Bool
    public var emitsJSONLines: Bool
    public var outputLastMessageURL: URL?
    public var outputSchemaURL: URL?
    public var sandbox: CLISandboxMode?
    public var explicitMode: AgentMode?
    public var ignoresUserConfig: Bool
    public var ignoresPermissionRules: Bool
    public var skipsGitRepositoryCheck: Bool
    public var usedDeprecatedFullAuto: Bool

    public init(
        style: CLIInvocationStyle,
        prompt: String,
        resumeTarget: CLIResumeTarget? = nil,
        live: Bool,
        apiKey: String? = nil,
        model: String? = nil,
        baseURL: String? = nil,
        cwd: URL,
        home: URL? = nil,
        imageURLs: [URL] = [],
        ephemeral: Bool = false,
        emitsJSONLines: Bool = false,
        outputLastMessageURL: URL? = nil,
        outputSchemaURL: URL? = nil,
        sandbox: CLISandboxMode? = nil,
        explicitMode: AgentMode? = nil,
        ignoresUserConfig: Bool = false,
        ignoresPermissionRules: Bool = false,
        skipsGitRepositoryCheck: Bool = false,
        usedDeprecatedFullAuto: Bool = false
    ) {
        self.style = style
        self.prompt = prompt
        self.resumeTarget = resumeTarget
        self.live = live
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.cwd = cwd
        self.home = home
        self.imageURLs = imageURLs
        self.ephemeral = ephemeral
        self.emitsJSONLines = emitsJSONLines
        self.outputLastMessageURL = outputLastMessageURL
        self.outputSchemaURL = outputSchemaURL
        self.sandbox = sandbox
        self.explicitMode = explicitMode
        self.ignoresUserConfig = ignoresUserConfig
        self.ignoresPermissionRules = ignoresPermissionRules
        self.skipsGitRepositoryCheck = skipsGitRepositoryCheck
        self.usedDeprecatedFullAuto = usedDeprecatedFullAuto
    }
}

public enum CLIAuthCommand: Sendable, Equatable {
    case status
    case setKey(String)
    case clear
}

public enum CLICommand: Sendable, Equatable {
    case run(CLIRunRequest)
    case auth(CLIAuthCommand, home: URL?)
    case help
    case version
}

public enum CLIError: Error, LocalizedError, Sendable, Equatable {
    case missingOptionValue(String)
    case unknownOption(String)
    case invalidOptionValue(option: String, value: String)
    case missingPrompt
    case invalidResumeTarget(String)
    case stdinTooLarge(limit: Int)
    case invalidUTF8Stdin
    case notGitRepository(String)
    case unsupportedSandbox(String)
    case noSavedThreads
    case threadNotFound(UUID)
    case noFinalMessage
    case outputSchemaTooLarge(limit: Int)
    case invalidOutputSchema(String)
    case structuredOutputMismatch(String)

    public var errorDescription: String? {
        switch self {
        case .missingOptionValue(let option):
            "\(option) requires a value."
        case .unknownOption(let option):
            "Unknown option: \(option)"
        case .invalidOptionValue(let option, let value):
            "Invalid value for \(option): \(value)"
        case .missingPrompt:
            "Provide a prompt argument or pipe a prompt on stdin."
        case .invalidResumeTarget(let value):
            "Resume target must be --last or a saved thread UUID, not \(value)."
        case .stdinTooLarge(let limit):
            "Piped stdin exceeds the \(limit)-byte limit."
        case .invalidUTF8Stdin:
            "Piped stdin must be valid UTF-8 text."
        case .notGitRepository(let path):
            "\(path) is not inside a Git repository. Use --skip-git-repo-check only in a controlled workspace."
        case .unsupportedSandbox(let value):
            "Sandbox \(value) is not available yet. QuillCode refused to claim broader access than it can enforce."
        case .noSavedThreads:
            "No saved thread is available to resume."
        case .threadNotFound(let id):
            "Saved thread \(id.uuidString) was not found."
        case .noFinalMessage:
            "The run ended without a final assistant message."
        case .outputSchemaTooLarge(let limit):
            "The output schema exceeds the \(limit)-byte limit."
        case .invalidOutputSchema(let reason):
            "Invalid output schema: \(reason)"
        case .structuredOutputMismatch(let reason):
            "The final response does not match --output-schema: \(reason)"
        }
    }
}

extension String {
    var cliExpandingTildeInPath: String {
        NSString(string: self).expandingTildeInPath
    }
}
