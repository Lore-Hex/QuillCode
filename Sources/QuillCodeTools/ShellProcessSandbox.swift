import Foundation

public enum ShellProcessSandboxMode: Sendable, Hashable {
    case readOnly
    case workspaceWrite
    case unrestricted
}

public struct ShellProcessSandboxPolicy: Sendable, Hashable {
    public var mode: ShellProcessSandboxMode
    public var networkAccess: Bool
    public var writableRoots: [URL]
    public var includesSlashTemporaryDirectory: Bool
    public var includesEnvironmentTemporaryDirectory: Bool

    public init(
        mode: ShellProcessSandboxMode,
        networkAccess: Bool = false,
        writableRoots: [URL] = [],
        includesSlashTemporaryDirectory: Bool = true,
        includesEnvironmentTemporaryDirectory: Bool = true
    ) {
        self.mode = mode
        self.networkAccess = networkAccess
        self.writableRoots = writableRoots
        self.includesSlashTemporaryDirectory = includesSlashTemporaryDirectory
        self.includesEnvironmentTemporaryDirectory = includesEnvironmentTemporaryDirectory
    }
}

public struct ShellProcessLaunch: Sendable, Equatable {
    public var executable: URL
    public var arguments: [String]
    public var isSandboxed: Bool

    public init(executable: URL, arguments: [String], isSandboxed: Bool) {
        self.executable = executable
        self.arguments = arguments
        self.isSandboxed = isSandboxed
    }
}

public enum ShellProcessSandboxError: LocalizedError {
    case runtimeUnavailable

    public var errorDescription: String? {
        switch self {
        case .runtimeUnavailable:
            "No supported process sandbox is available on this host."
        }
    }
}

public enum ShellProcessSandbox {
    public static func launch(
        executable: URL,
        arguments: [String],
        cwd: URL,
        environment: [String: String],
        policy: ShellProcessSandboxPolicy?
    ) throws -> ShellProcessLaunch {
        guard let policy, policy.mode != .unrestricted else {
            return ShellProcessLaunch(
                executable: executable,
                arguments: arguments,
                isSandboxed: false
            )
        }
        let writablePaths = writablePaths(policy: policy, environment: environment)

        if FileManager.default.isExecutableFile(atPath: "/usr/bin/sandbox-exec") {
            return ShellProcessLaunch(
                executable: URL(fileURLWithPath: "/usr/bin/sandbox-exec"),
                arguments: [
                    "-p",
                    seatbeltProfile(policy: policy, writablePaths: writablePaths),
                    "--",
                    executable.path
                ] + arguments,
                isSandboxed: true
            )
        }
        if let bubblewrap = resolveExecutable("bwrap", cwd: cwd, environment: environment) {
            return ShellProcessLaunch(
                executable: bubblewrap,
                arguments: bubblewrapArguments(
                    policy: policy,
                    cwd: cwd,
                    writablePaths: writablePaths,
                    executable: executable,
                    arguments: arguments
                ),
                isSandboxed: true
            )
        }
        throw ShellProcessSandboxError.runtimeUnavailable
    }

    public static func isLikelyDenial(
        launch: ShellProcessLaunch,
        exitCode: Int32,
        stdout: String,
        stderr: String
    ) -> Bool {
        guard launch.isSandboxed, exitCode != 0, exitCode != 126, exitCode != 127 else {
            return false
        }
        let output = "\(stdout)\n\(stderr)".lowercased()
        return [
            "operation not permitted",
            "permission denied",
            "read-only file system",
            "sandbox violation",
            "sandbox-exec:"
        ].contains { output.contains($0) }
    }

    public static func filesystemAliases(for path: String) -> [String] {
        if path == "/var" || path.hasPrefix("/var/") || path == "/tmp" || path.hasPrefix("/tmp/") {
            let privateAlias = "/private\(path)"
            if FileManager.default.fileExists(atPath: privateAlias) {
                return [path, privateAlias]
            }
        }
        return [path]
    }

    private static func writablePaths(
        policy: ShellProcessSandboxPolicy,
        environment: [String: String]
    ) -> [String] {
        var urls = policy.mode == .workspaceWrite ? policy.writableRoots : []
        if policy.includesSlashTemporaryDirectory {
            urls.append(URL(fileURLWithPath: "/tmp", isDirectory: true))
        }
        if policy.includesEnvironmentTemporaryDirectory,
           let temporaryDirectory = environment["TMPDIR"] {
            urls.append(URL(fileURLWithPath: temporaryDirectory, isDirectory: true))
        }
        let aliases = urls.flatMap { url -> [String] in
            let standardized = url.standardizedFileURL
            guard FileManager.default.fileExists(atPath: standardized.path) else { return [] }
            let resolved = standardized.resolvingSymlinksInPath()
            return filesystemAliases(for: standardized.path) + filesystemAliases(for: resolved.path)
        }
        return Array(Set(aliases)).sorted()
    }

    private static func resolveExecutable(
        _ program: String,
        cwd: URL,
        environment: [String: String]
    ) -> URL? {
        let path = environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        for directory in path.split(separator: ":", omittingEmptySubsequences: false) {
            let root = directory.isEmpty
                ? cwd
                : URL(fileURLWithPath: String(directory), isDirectory: true)
            let candidate = root.appendingPathComponent(program).standardizedFileURL
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private static func seatbeltProfile(
        policy: ShellProcessSandboxPolicy,
        writablePaths: [String]
    ) -> String {
        var rules = [
            ShellProcessMacOSSeatbeltPolicy.base,
            "(allow file-read*)",
            "(allow file-read* file-write* (literal \"/dev/tty\"))",
            "(allow file-write* (regex #\"^/dev/fd/[012]$\"))"
        ]
        for path in writablePaths {
            let escaped = seatbeltEscaped(path)
            rules.append("(allow file-write* (literal \"\(escaped)\") (subpath \"\(escaped)\"))")
        }
        if policy.networkAccess { rules.append("(allow network*)") }
        return rules.joined(separator: "\n")
    }

    private static func bubblewrapArguments(
        policy: ShellProcessSandboxPolicy,
        cwd: URL,
        writablePaths: [String],
        executable: URL,
        arguments: [String]
    ) -> [String] {
        var result = [
            "--die-with-parent", "--new-session", "--ro-bind", "/", "/",
            "--proc", "/proc", "--dev", "/dev", "--chdir", cwd.path
        ]
        if !policy.networkAccess { result.append("--unshare-net") }
        for path in writablePaths {
            result.append(contentsOf: ["--bind", path, path])
        }
        result.append("--")
        result.append(executable.path)
        result.append(contentsOf: arguments)
        return result
    }

    private static func seatbeltEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
