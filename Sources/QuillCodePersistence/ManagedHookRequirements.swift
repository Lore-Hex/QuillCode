public struct ManagedComputerUseRequirements: Sendable, Equatable {
    public var allowLockedComputerUse: Bool?

    public init(allowLockedComputerUse: Bool? = nil) {
        self.allowLockedComputerUse = allowLockedComputerUse
    }
}

public struct ManagedHookRequirements: Sendable, Equatable {
    public static let eventNames = [
        "PreToolUse",
        "PermissionRequest",
        "PostToolUse",
        "PreCompact",
        "PostCompact",
        "SessionStart",
        "UserPromptSubmit",
        "SubagentStart",
        "SubagentStop",
        "Stop"
    ]

    public var managedDirectory: String?
    public var windowsManagedDirectory: String?
    public var events: [String: [ManagedHookMatcherGroup]]

    public init(
        managedDirectory: String? = nil,
        windowsManagedDirectory: String? = nil,
        events: [String: [ManagedHookMatcherGroup]] = [:]
    ) {
        self.managedDirectory = managedDirectory
        self.windowsManagedDirectory = windowsManagedDirectory
        self.events = events
    }
}

public struct ManagedHookMatcherGroup: Sendable, Equatable {
    public var matcher: String?
    public var hooks: [ManagedHookHandler]

    public init(matcher: String? = nil, hooks: [ManagedHookHandler]) {
        self.matcher = matcher
        self.hooks = hooks
    }
}

public enum ManagedHookHandler: Sendable, Equatable {
    case command(ManagedCommandHook)
    case prompt
    case agent
}

public struct ManagedCommandHook: Sendable, Equatable {
    public var command: String
    public var commandWindows: String?
    public var timeoutSeconds: UInt64?
    public var isAsync: Bool
    public var statusMessage: String?

    public init(
        command: String,
        commandWindows: String? = nil,
        timeoutSeconds: UInt64? = nil,
        isAsync: Bool = false,
        statusMessage: String? = nil
    ) {
        self.command = command
        self.commandWindows = commandWindows
        self.timeoutSeconds = timeoutSeconds
        self.isAsync = isAsync
        self.statusMessage = statusMessage
    }
}
