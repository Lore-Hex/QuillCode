import Foundation

public enum ProjectConnectionKind: String, Codable, Sendable, Hashable, CaseIterable {
    case local
    case ssh
}

public struct ProjectConnection: Codable, Sendable, Hashable {
    public var kind: ProjectConnectionKind
    public var path: String
    public var host: String?
    public var user: String?
    public var port: Int?

    public init(
        kind: ProjectConnectionKind,
        path: String,
        host: String? = nil,
        user: String? = nil,
        port: Int? = nil
    ) {
        self.kind = kind
        self.path = path
        self.host = host
        self.user = user
        self.port = port
    }

    public static func local(path: String) -> ProjectConnection {
        ProjectConnection(kind: .local, path: path)
    }

    public static func ssh(
        path: String,
        host: String,
        user: String? = nil,
        port: Int? = nil
    ) -> ProjectConnection {
        ProjectConnection(kind: .ssh, path: path, host: host, user: user, port: port)
    }

    public static func parseSSH(_ value: String) -> ProjectConnection? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains("://") {
            guard let components = URLComponents(string: trimmed),
                  components.scheme?.lowercased() == "ssh",
                  let host = components.host,
                  isValidSSHDestinationComponent(host),
                  components.password == nil,
                  components.query == nil,
                  components.fragment == nil,
                  components.user.map(isValidSSHDestinationComponent) != false,
                  components.port.map(isValidSSHPort) != false
            else { return nil }
            let path = components.path.isEmpty ? "/" : components.path
            return .ssh(path: path, host: host, user: components.user, port: components.port)
        }

        guard let separatorIndex = trimmed.firstIndex(of: ":") else { return nil }
        let left = String(trimmed[..<separatorIndex])
        let path = String(trimmed[trimmed.index(after: separatorIndex)...])
        guard !left.isEmpty, path.hasPrefix("/") || path.hasPrefix("~") else { return nil }

        let userAndHost = left.split(separator: "@", maxSplits: 1).map(String.init)
        let user = userAndHost.count == 2 ? userAndHost[0] : nil
        let host = userAndHost.count == 2 ? userAndHost[1] : userAndHost[0]
        guard isValidSSHDestinationComponent(host),
              user.map(isValidSSHDestinationComponent) != false
        else { return nil }
        return .ssh(path: path, host: host, user: user)
    }

    /// Parses an SSH destination without requiring a remote path in the entered value.
    ///
    /// This is the form used by connection dialogs where the destination and project folder are
    /// separate fields. URL paths are rejected so the folder has one unambiguous source of truth.
    public static func parseSSHDestination(_ value: String, path: String) -> ProjectConnection? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.lowercased().hasPrefix("ssh://") ? trimmed : "ssh://\(trimmed)"
        guard let components = URLComponents(string: normalized),
              components.scheme?.lowercased() == "ssh",
              let host = components.host,
              isValidSSHDestinationComponent(host),
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.isEmpty || components.path == "/",
              components.user.map(isValidSSHDestinationComponent) != false,
              components.port.map(isValidSSHPort) != false
        else { return nil }
        return .ssh(path: path, host: host, user: components.user, port: components.port)
    }

    public func replacingPath(with path: String) -> ProjectConnection {
        var connection = self
        connection.path = path
        return connection
    }

    public var isRemote: Bool {
        kind != .local
    }

    public var displayLabel: String {
        switch kind {
        case .local:
            return path
        case .ssh:
            let userPrefix = user.map { "\($0)@" } ?? ""
            let hostLabel = host ?? "ssh"
            let portSuffix = port.map { ":\($0)" } ?? ""
            let pathSeparator = path.hasPrefix("/") ? "" : "/"
            return "ssh://\(userPrefix)\(hostLabel)\(portSuffix)\(pathSeparator)\(path)"
        }
    }

    public var kindLabel: String {
        switch kind {
        case .local:
            return "Local"
        case .ssh:
            return "SSH Remote"
        }
    }

    private static func isValidSSHDestinationComponent(_ value: String) -> Bool {
        !value.isEmpty
            && !value.hasPrefix("-")
            && !value.contains("/")
            && !value.contains("\\")
            && !value.contains { $0.isWhitespace || $0.isNewline || $0 == "\u{0}" }
    }

    private static func isValidSSHPort(_ value: Int) -> Bool {
        (1...65_535).contains(value)
    }
}
