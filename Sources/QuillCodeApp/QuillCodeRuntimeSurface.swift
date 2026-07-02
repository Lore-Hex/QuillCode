import QuillCodeCore

public enum RuntimeIssueSeverity: String, Codable, Sendable, Hashable {
    case info
    case warning
    case error
}

public enum RuntimeRecoveryRoute: String, Codable, Sendable, Hashable {
    case settings
    case retryLastTurn = "retry-last-turn"
    case modelPicker = "model-picker"
}

public enum RuntimeRecoveryReason: String, Codable, Sendable, Hashable {
    case trustedRouterSignInRequired = "trustedrouter-sign-in-required"
    case developerKeyMissing = "developer-key-missing"
    case trustedRouterKeyRejected = "trustedrouter-key-rejected"
    case rateLimited = "rate-limited"
    case providerUnavailable = "provider-unavailable"
    case networkUnreachable = "network-unreachable"
    case emptyResponse = "empty-response"
    case malformedModelAction = "malformed-model-action"
    case runFailed = "run-failed"
}

public struct RuntimeRecoveryTelemetry: Codable, Sendable, Hashable {
    public var route: RuntimeRecoveryRoute
    public var reason: RuntimeRecoveryReason
    public var commandID: String?

    public init(
        route: RuntimeRecoveryRoute,
        reason: RuntimeRecoveryReason,
        commandID: String? = nil
    ) {
        self.route = route
        self.reason = reason
        self.commandID = commandID
    }
}

public enum ExecutionContextKind: String, Codable, Sendable, Hashable {
    case local
    case sshRemote = "ssh-remote"
}

public struct ExecutionContextSurface: Codable, Sendable, Hashable {
    public var kind: ExecutionContextKind
    public var label: String
    public var detail: String

    public init(kind: ExecutionContextKind, label: String, detail: String) {
        self.kind = kind
        self.label = label
        self.detail = detail
    }

    public static func local(path: String?) -> ExecutionContextSurface {
        let detail: String
        if let path, !path.isEmpty {
            detail = path
        } else {
            detail = "No project"
        }
        return ExecutionContextSurface(
            kind: .local,
            label: "Local",
            detail: detail
        )
    }

    public static func project(_ project: ProjectRef) -> ExecutionContextSurface {
        switch project.connection.kind {
        case .local:
            return .local(path: project.displayPath)
        case .ssh:
            let host = project.connection.host ?? "ssh"
            return ExecutionContextSurface(
                kind: .sshRemote,
                label: "SSH Remote",
                detail: host
            )
        }
    }
}

public struct RuntimeIssueSurface: Codable, Sendable, Hashable {
    public var severity: RuntimeIssueSeverity
    public var title: String
    public var message: String
    public var actionLabel: String?
    public var recovery: RuntimeRecoveryTelemetry?
    public var diagnostics: [RuntimeDiagnosticSurface]

    public init(
        severity: RuntimeIssueSeverity,
        title: String,
        message: String,
        actionLabel: String? = nil,
        recovery: RuntimeRecoveryTelemetry? = nil,
        diagnostics: [RuntimeDiagnosticSurface] = []
    ) {
        self.severity = severity
        self.title = title
        self.message = message
        self.actionLabel = actionLabel
        self.recovery = recovery
        self.diagnostics = diagnostics
    }

    private enum CodingKeys: String, CodingKey {
        case severity
        case title
        case message
        case actionLabel
        case recovery
        case diagnostics
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.severity = try container.decode(RuntimeIssueSeverity.self, forKey: .severity)
        self.title = try container.decode(String.self, forKey: .title)
        self.message = try container.decode(String.self, forKey: .message)
        self.actionLabel = try container.decodeIfPresent(String.self, forKey: .actionLabel)
        self.recovery = try container.decodeIfPresent(RuntimeRecoveryTelemetry.self, forKey: .recovery)
        self.diagnostics = try container.decodeIfPresent([RuntimeDiagnosticSurface].self, forKey: .diagnostics) ?? []
    }

    func withDiagnostics(_ diagnostics: [RuntimeDiagnosticSurface]) -> RuntimeIssueSurface {
        var copy = self
        copy.diagnostics = diagnostics
        return copy
    }

    var allDiagnostics: [RuntimeDiagnosticSurface] {
        diagnostics + recoveryDiagnostics
    }

    private var recoveryDiagnostics: [RuntimeDiagnosticSurface] {
        guard let recovery else { return [] }
        var diagnostics = [
            RuntimeDiagnosticSurface(label: "Recovery route", value: recovery.route.rawValue),
            RuntimeDiagnosticSurface(label: "Recovery reason", value: recovery.reason.rawValue)
        ]
        if let commandID = recovery.commandID {
            diagnostics.append(RuntimeDiagnosticSurface(label: "Recovery command", value: commandID))
        }
        return diagnostics
    }
}

public struct RuntimeDiagnosticSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String { label }
    public var label: String
    public var value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}
