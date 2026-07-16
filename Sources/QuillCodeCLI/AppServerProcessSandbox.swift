import Foundation

struct AppServerProcessLaunch: Sendable, Equatable {
    var executable: URL
    var arguments: [String]
}

enum AppServerProcessSandbox {
    static func launch(for request: AppServerProcessSpawnRequest) throws -> AppServerProcessLaunch {
        let target = try AppServerProcessSupport.resolveExecutable(
            request.command[0],
            cwd: request.cwd,
            environment: request.environment
        )
        let targetArguments = Array(request.command.dropFirst())
        guard let policy = request.sandboxPolicy, policy.mode != .dangerFullAccess else {
            return AppServerProcessLaunch(executable: target, arguments: targetArguments)
        }
        let writablePaths = writablePaths(policy: policy, request: request)

        if FileManager.default.isExecutableFile(atPath: "/usr/bin/sandbox-exec") {
            let profile = seatbeltProfile(policy: policy, writablePaths: writablePaths)
            return AppServerProcessLaunch(
                executable: URL(fileURLWithPath: "/usr/bin/sandbox-exec"),
                arguments: [
                    "-p",
                    profile,
                    "--",
                    target.path
                ] + targetArguments
            )
        }
        if let bubblewrap = try? AppServerProcessSupport.resolveExecutable(
            "bwrap",
            cwd: request.cwd,
            environment: request.environment
        ) {
            return AppServerProcessLaunch(
                executable: bubblewrap,
                arguments: bubblewrapArguments(
                    policy: policy,
                    request: request,
                    writablePaths: writablePaths,
                    target: target,
                    targetArguments: targetArguments
                )
            )
        }
        throw AppServerRPCError.internalError(
            "failed to configure command sandbox: no supported sandbox runtime is available"
        )
    }

    private static func seatbeltProfile(
        policy: AppServerSandboxPolicy,
        writablePaths: [String]
    ) -> String {
        var rules = [
            AppServerMacOSSeatbeltPolicy.base,
            "(allow file-read*)",
            "(allow file-read* file-write* (literal \"/dev/tty\"))",
            "(allow file-write* (regex #\"^/dev/fd/[012]$\"))"
        ]
        for path in writablePaths {
            let escaped = seatbeltEscaped(path)
            rules.append(
                "(allow file-write* (literal \"\(escaped)\") (subpath \"\(escaped)\"))"
            )
        }
        if policy.networkAccess { rules.append("(allow network*)") }
        return rules.joined(separator: "\n")
    }

    private static func bubblewrapArguments(
        policy: AppServerSandboxPolicy,
        request: AppServerProcessSpawnRequest,
        writablePaths: [String],
        target: URL,
        targetArguments: [String]
    ) -> [String] {
        var arguments = [
            "--die-with-parent", "--new-session", "--ro-bind", "/", "/",
            "--proc", "/proc", "--dev", "/dev", "--chdir", request.cwd.path
        ]
        if !policy.networkAccess { arguments.append("--unshare-net") }
        for path in writablePaths {
            arguments.append(contentsOf: ["--bind", path, path])
        }
        arguments.append("--")
        arguments.append(target.path)
        arguments.append(contentsOf: targetArguments)
        return arguments
    }

    private static func writablePaths(
        policy: AppServerSandboxPolicy,
        request: AppServerProcessSpawnRequest
    ) -> [String] {
        var paths: [String] = []
        let temporaryDirectory = request.environment["TMPDIR"]
        switch policy.mode {
        case .readOnly:
            paths.append("/tmp")
            if let temporaryDirectory { paths.append(temporaryDirectory) }
        case .workspaceWrite:
            paths.append(contentsOf: policy.writableRoots)
            if !policy.excludeSlashTemporaryDirectory { paths.append("/tmp") }
            if !policy.excludeTemporaryDirectoryEnvironmentVariable,
               let temporaryDirectory {
                paths.append(temporaryDirectory)
            }
        case .dangerFullAccess:
            break
        }
        let aliases = paths.flatMap { path -> [String] in
            let standardized = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
            guard FileManager.default.fileExists(atPath: standardized.path) else { return [] }
            let resolved = standardized.resolvingSymlinksInPath()
            return filesystemAliases(for: standardized.path) + filesystemAliases(for: resolved.path)
        }
        return Array(Set(aliases)).sorted()
    }

    static func filesystemAliases(for path: String) -> [String] {
        if path == "/var" || path.hasPrefix("/var/") || path == "/tmp" || path.hasPrefix("/tmp/") {
            let privateAlias = "/private\(path)"
            if FileManager.default.fileExists(atPath: privateAlias) {
                return [path, privateAlias]
            }
        }
        return [path]
    }

    private static func seatbeltEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
