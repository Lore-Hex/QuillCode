import QuillCodeCore

public enum RuntimeIssueSeverity: String, Codable, Sendable, Hashable {
    case info
    case warning
    case error
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
    public var diagnostics: [RuntimeDiagnosticSurface]

    public init(
        severity: RuntimeIssueSeverity,
        title: String,
        message: String,
        actionLabel: String? = nil,
        diagnostics: [RuntimeDiagnosticSurface] = []
    ) {
        self.severity = severity
        self.title = title
        self.message = message
        self.actionLabel = actionLabel
        self.diagnostics = diagnostics
    }

    private enum CodingKeys: String, CodingKey {
        case severity
        case title
        case message
        case actionLabel
        case diagnostics
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.severity = try container.decode(RuntimeIssueSeverity.self, forKey: .severity)
        self.title = try container.decode(String.self, forKey: .title)
        self.message = try container.decode(String.self, forKey: .message)
        self.actionLabel = try container.decodeIfPresent(String.self, forKey: .actionLabel)
        self.diagnostics = try container.decodeIfPresent([RuntimeDiagnosticSurface].self, forKey: .diagnostics) ?? []
    }

    func withDiagnostics(_ diagnostics: [RuntimeDiagnosticSurface]) -> RuntimeIssueSurface {
        var copy = self
        copy.diagnostics = diagnostics
        return copy
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
