import Foundation

public enum ProjectHookTrustDecision: String, Codable, Sendable, Hashable {
    case trusted
    case disabled
}

public enum ProjectHookTrustStatus: String, Codable, Sendable, Hashable {
    case reviewRequired = "review_required"
    case trusted
    case disabled
}

public enum ProjectHookSupportStatus: String, Codable, Sendable, Hashable {
    case supported
    case unsupportedEvent = "unsupported_event"
    case unsupportedMatcher = "unsupported_matcher"
    case unsupportedHandler = "unsupported_handler"
    case asynchronousHandler = "asynchronous_handler"
    case missingCommand = "missing_command"

    public var isSupported: Bool { self == .supported }
}

/// A bounded, data-only standard hook contributed by a config layer or plugin package.
///
/// Discovery never executes the command. `definitionHash` covers the exact normalized hook
/// definition, so changing any executable field moves a previously trusted hook back to review.
/// The `pluginID` and `pluginName` wire keys are retained for persisted-state compatibility; for
/// config-layer hooks they identify the source layer rather than an installed plugin.
public struct ProjectPluginHook: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var pluginID: String
    public var pluginName: String
    public var event: String
    public var matcher: String?
    public var handlerType: String
    public var command: String?
    public var commandWindows: String?
    public var statusMessage: String?
    public var timeoutSeconds: Int
    public var isAsync: Bool
    public var relativePath: String
    public var pluginRootRelativePath: String?
    public var definitionHash: String
    public var trustStatus: ProjectHookTrustStatus
    public var supportStatus: ProjectHookSupportStatus

    public init(
        id: String,
        pluginID: String,
        pluginName: String,
        event: String,
        matcher: String? = nil,
        handlerType: String,
        command: String? = nil,
        commandWindows: String? = nil,
        statusMessage: String? = nil,
        timeoutSeconds: Int = 600,
        isAsync: Bool = false,
        relativePath: String,
        pluginRootRelativePath: String? = nil,
        definitionHash: String,
        trustStatus: ProjectHookTrustStatus = .reviewRequired,
        supportStatus: ProjectHookSupportStatus
    ) {
        self.id = id
        self.pluginID = pluginID
        self.pluginName = pluginName
        self.event = event
        self.matcher = matcher
        self.handlerType = handlerType
        self.command = command
        self.commandWindows = commandWindows
        self.statusMessage = statusMessage
        self.timeoutSeconds = timeoutSeconds
        self.isAsync = isAsync
        self.relativePath = relativePath
        self.pluginRootRelativePath = pluginRootRelativePath
        self.definitionHash = definitionHash
        self.trustStatus = trustStatus
        self.supportStatus = supportStatus
    }

    public var isExecutable: Bool {
        trustStatus == .trusted && supportStatus.isSupported && command != nil
    }
}
