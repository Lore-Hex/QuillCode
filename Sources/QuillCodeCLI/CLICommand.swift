import Foundation
import QuillCodeCore

public enum CLIInvocationStyle: Sendable, Equatable {
    case legacy
    case exec
}

public enum CLISandboxMode: String, Codable, Sendable, Equatable, CaseIterable {
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

public struct CLIDoctorRequest: Sendable, Equatable {
    public var home: URL?
    public var emitsJSON: Bool
    public var summaryOnly: Bool
    public var expandsLongLists: Bool
    public var disablesColor: Bool
    public var usesASCII: Bool
    public var showsHelp: Bool

    public init(
        home: URL? = nil,
        emitsJSON: Bool = false,
        summaryOnly: Bool = false,
        expandsLongLists: Bool = false,
        disablesColor: Bool = false,
        usesASCII: Bool = false,
        showsHelp: Bool = false
    ) {
        self.home = home
        self.emitsJSON = emitsJSON
        self.summaryOnly = summaryOnly
        self.expandsLongLists = expandsLongLists
        self.disablesColor = disablesColor
        self.usesASCII = usesASCII
        self.showsHelp = showsHelp
    }
}

public enum CLIAppServerTransport: Sendable, Equatable {
    case stdio
    case unix(path: String?)
    case webSocket(host: String, port: UInt16)
    case off

    public init?(rawValue: String) {
        if rawValue == "stdio://" {
            self = .stdio
            return
        }
        if rawValue == "off" {
            self = .off
            return
        }
        if rawValue.hasPrefix("ws://"),
           let components = URLComponents(string: rawValue),
           components.scheme?.lowercased() == "ws",
           let parsedHost = components.host,
           let port = components.port,
           (0...Int(UInt16.max)).contains(port),
           components.user == nil,
           components.password == nil,
           components.query == nil,
           components.fragment == nil,
           components.percentEncodedPath.isEmpty
        {
            let host = parsedHost.hasPrefix("[") && parsedHost.hasSuffix("]")
                ? String(parsedHost.dropFirst().dropLast())
                : parsedHost
            guard Self.isNumericIP(host) else { return nil }
            self = .webSocket(host: host, port: UInt16(port))
            return
        }
        guard rawValue.hasPrefix("unix://") else { return nil }
        let suffix = String(rawValue.dropFirst("unix://".count))
        if suffix.isEmpty {
            self = .unix(path: nil)
        } else if suffix.hasPrefix("/"),
                  suffix != "/",
                  !suffix.contains("\0"),
                  !suffix.contains("?"),
                  !suffix.contains("#") {
            self = .unix(path: suffix)
        } else {
            return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .stdio: "stdio://"
        case .unix(nil): "unix://"
        case .unix(let path?): "unix://\(path)"
        case .webSocket(let host, let port):
            host.contains(":") ? "ws://[\(host)]:\(port)" : "ws://\(host):\(port)"
        case .off: "off"
        }
    }

    private static func isNumericIP(_ host: String) -> Bool {
        guard !host.isEmpty, !host.contains("\0") else { return false }
        if host.contains(":") {
            return host.allSatisfy {
                $0.isHexDigit || $0 == ":" || $0 == "."
            }
        }
        let components = host.split(separator: ".", omittingEmptySubsequences: false)
        return components.count == 4 && components.allSatisfy {
            !$0.isEmpty && UInt8($0) != nil
        }
    }
}

public enum CLIAppServerWebSocketAuthMode: String, Sendable, Equatable {
    case capabilityToken = "capability-token"
    case signedBearerToken = "signed-bearer-token"
}

public struct CLIAppServerWebSocketAuth: Sendable, Equatable {
    public var mode: CLIAppServerWebSocketAuthMode?
    public var tokenFile: String?
    public var tokenSHA256: String?
    public var sharedSecretFile: String?
    public var issuer: String?
    public var audience: String?
    public var maxClockSkewSeconds: UInt64?

    public init(
        mode: CLIAppServerWebSocketAuthMode? = nil,
        tokenFile: String? = nil,
        tokenSHA256: String? = nil,
        sharedSecretFile: String? = nil,
        issuer: String? = nil,
        audience: String? = nil,
        maxClockSkewSeconds: UInt64? = nil
    ) {
        self.mode = mode
        self.tokenFile = tokenFile
        self.tokenSHA256 = tokenSHA256
        self.sharedSecretFile = sharedSecretFile
        self.issuer = issuer
        self.audience = audience
        self.maxClockSkewSeconds = maxClockSkewSeconds
    }

    public var isConfigured: Bool {
        mode != nil || tokenFile != nil || tokenSHA256 != nil || sharedSecretFile != nil
            || issuer != nil || audience != nil || maxClockSkewSeconds != nil
    }
}

public struct CLIAppServerRequest: Sendable, Equatable {
    public var transport: CLIAppServerTransport
    public var live: Bool
    public var apiKey: String?
    public var model: String?
    public var baseURL: String?
    public var home: URL?
    public var webSocketAuth: CLIAppServerWebSocketAuth

    public init(
        transport: CLIAppServerTransport = .stdio,
        live: Bool = true,
        apiKey: String? = nil,
        model: String? = nil,
        baseURL: String? = nil,
        home: URL? = nil,
        webSocketAuth: CLIAppServerWebSocketAuth = CLIAppServerWebSocketAuth()
    ) {
        self.transport = transport
        self.live = live
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.home = home
        self.webSocketAuth = webSocketAuth
    }
}

public struct CLIMCPServerRequest: Sendable, Equatable {
    public var live: Bool
    public var apiKey: String?
    public var model: String?
    public var baseURL: String?
    public var home: URL?

    public init(
        live: Bool = true,
        apiKey: String? = nil,
        model: String? = nil,
        baseURL: String? = nil,
        home: URL? = nil
    ) {
        self.live = live
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.home = home
    }
}

public enum CLICommand: Sendable, Equatable {
    case run(CLIRunRequest)
    case review(CLIReviewRequest)
    case appServer(CLIAppServerRequest)
    case mcpServer(CLIMCPServerRequest)
    case auth(CLIAuthCommand, home: URL?)
    case doctor(CLIDoctorRequest)
    case help
    case version
}

public enum CLIError: Error, LocalizedError, Sendable, Equatable {
    case missingOptionValue(String)
    case unknownOption(String)
    case invalidOptionValue(option: String, value: String)
    case missingPrompt
    case invalidResumeTarget(String)
    case missingReviewTarget
    case conflictingReviewTargets
    case reviewTitleRequiresCommit
    case invalidReviewRequest(String)
    case stdinTooLarge(limit: Int)
    case invalidUTF8Stdin
    case notGitRepository(String)
    case noSavedThreads
    case threadNotFound(UUID)
    case noFinalMessage
    case outputSchemaTooLarge(limit: Int)
    case invalidOutputSchema(String)
    case structuredOutputMismatch(String)
    case unsupportedAppServerTransport(String)
    case appServerMessageTooLarge(limit: Int)
    case invalidAppServerAuth(String)

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
        case .missingReviewTarget:
            "Choose exactly one review target: --uncommitted, --base BRANCH, --commit SHA, or a custom prompt."
        case .conflictingReviewTargets:
            "Review targets conflict. Choose only one of --uncommitted, --base, --commit, or a custom prompt."
        case .reviewTitleRequiresCommit:
            "--title requires --commit."
        case .invalidReviewRequest(let message):
            message
        case .stdinTooLarge(let limit):
            "Piped stdin exceeds the \(limit)-byte limit."
        case .invalidUTF8Stdin:
            "Piped stdin must be valid UTF-8 text."
        case .notGitRepository(let path):
            "\(path) is not inside a Git repository. Use --skip-git-repo-check only in a controlled workspace."
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
        case .unsupportedAppServerTransport(let value):
            "App-server transport \(value) is not supported. Use stdio://, unix://, unix:///absolute/path, ws://IP:PORT, or off."
        case .appServerMessageTooLarge(let limit):
            "App-server message exceeds the \(limit)-byte limit."
        case .invalidAppServerAuth(let reason):
            "Invalid app-server WebSocket authentication: \(reason)"
        }
    }
}

extension String {
    var cliExpandingTildeInPath: String {
        NSString(string: self).expandingTildeInPath
    }
}
