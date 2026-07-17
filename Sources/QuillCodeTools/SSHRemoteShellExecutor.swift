import Foundation
import QuillCodeCore

struct SSHRemoteInvocation: Sendable, Hashable {
    var executable: String
    var arguments: [String]

    init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }

    var shellCommand: String {
        ([executable] + arguments)
            .map(Self.shellSingleQuoted)
            .joined(separator: " ")
    }

    static func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

public struct SSHRemoteShellExecutor: Sendable {
    public var sshExecutable: String
    public var connectTimeoutSeconds: Int

    public init(
        sshExecutable: String = "ssh",
        connectTimeoutSeconds: Int = 10
    ) {
        self.sshExecutable = sshExecutable
        self.connectTimeoutSeconds = connectTimeoutSeconds
    }

    public func request(
        command: String,
        connection: ProjectConnection,
        timeoutSeconds: TimeInterval = 60,
        environment: [String: String]? = nil
    ) -> ShellExecutionRequest? {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty,
              let invocation = projectInvocation(
                  command: trimmedCommand,
                  connection: connection
              )
        else {
            return nil
        }

        return ShellExecutionRequest(
            command: invocation.shellCommand,
            cwd: FileManager.default.homeDirectoryForCurrentUser,
            timeoutSeconds: timeoutSeconds,
            environment: environment
        )
    }

    func projectInvocation(
        command: String,
        connection: ProjectConnection
    ) -> SSHRemoteInvocation? {
        let command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return nil }
        return invocation(
            remoteCommand: "cd \(Self.remotePathExpression(connection.path)) && \(command)",
            connection: connection
        )
    }

    func invocation(
        remoteCommand: String,
        connection: ProjectConnection
    ) -> SSHRemoteInvocation? {
        let remoteCommand = remoteCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remoteCommand.isEmpty,
              connection.kind == .ssh,
              let host = connection.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty,
              Self.isValidDestinationComponent(host),
              connection.user.map(Self.isValidDestinationComponent) != false,
              connection.port.map(Self.isValidPort) != false else {
            return nil
        }

        var arguments = [
            "-T",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=\(connectTimeoutSeconds)"
        ]
        if let port = connection.port {
            arguments.append(contentsOf: ["-p", "\(port)"])
        }
        // `--` ends ssh option parsing so the destination can never be mistaken for an option (e.g. a
        // host like `-oProxyCommand=…` injecting a local command). Belt-and-suspenders with the
        // leading-`-` rejection in isValidDestinationComponent.
        arguments.append("--")
        arguments.append(Self.destination(host: host, user: connection.user))
        arguments.append(remoteCommand)
        return SSHRemoteInvocation(executable: sshExecutable, arguments: arguments)
    }

    private static func destination(host: String, user: String?) -> String {
        guard let user, !user.isEmpty else { return host }
        return "\(user)@\(host)"
    }

    private static func isValidDestinationComponent(_ value: String) -> Bool {
        // Reject a leading `-` so a host/user can never be parsed by ssh as an option flag
        // (`-oProxyCommand=…` would run a local command). Whitespace/NUL are rejected too.
        !value.isEmpty
            && !value.hasPrefix("-")
            && !value.contains { $0.isWhitespace || $0 == "\u{0}" }
    }

    private static func isValidPort(_ port: Int) -> Bool {
        (1...65_535).contains(port)
    }

    private static func remotePathExpression(_ path: String) -> String {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return "~" }
        if trimmedPath == "~" {
            return "~"
        }
        if trimmedPath.hasPrefix("~/") {
            let relativePath = String(trimmedPath.dropFirst(2))
            return relativePath.isEmpty ? "~" : "~/\(SSHRemoteInvocation.shellSingleQuoted(relativePath))"
        }
        return SSHRemoteInvocation.shellSingleQuoted(trimmedPath)
    }
}
