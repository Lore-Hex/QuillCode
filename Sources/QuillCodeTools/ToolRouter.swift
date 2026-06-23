import Foundation
import QuillCodeCore

public struct ToolRouter: Sendable {
    public var workspaceRoot: URL
    public var shell: ShellToolExecutor
    public var files: FileToolExecutor
    public var git: GitToolExecutor
    public var patch: PatchToolExecutor
    private static let minShellTimeoutSeconds = 1
    private static let maxShellTimeoutSeconds = 1_800

    public init(
        workspaceRoot: URL,
        shell: ShellToolExecutor = ShellToolExecutor(),
        git: GitToolExecutor = GitToolExecutor()
    ) {
        self.workspaceRoot = workspaceRoot
        self.shell = shell
        self.files = FileToolExecutor(workspaceRoot: workspaceRoot)
        self.git = git
        self.patch = PatchToolExecutor(workspaceRoot: workspaceRoot, shell: shell)
    }

    public static let definitions: [ToolDefinition] = [
        .shellRun,
        .fileRead,
        .fileWrite,
        .applyPatch
    ] + GitToolCallDispatcher.definitions

    public func definition(named name: String) -> ToolDefinition? {
        Self.definitions.first { $0.name == name }
    }

    public func execute(_ call: ToolCall) -> ToolResult {
        do {
            let args = try ToolArguments(call.argumentsJSON)
            if GitToolCallDispatcher.handles(call.name) {
                return try GitToolCallDispatcher(workspaceRoot: workspaceRoot, git: git)
                    .execute(name: call.name, arguments: args)
            }
            switch call.name {
            case ToolDefinition.shellRun.name:
                let command = try args.requiredString("cmd")
                switch shellWorkingDirectory(args.string("cwd")) {
                case let .allowed(cwd):
                    switch shellTimeoutSeconds(args) {
                    case let .allowed(timeoutSeconds):
                        switch shellEnvironment(args) {
                        case let .allowed(environment):
                            var request = ShellExecutionRequest(command: command, cwd: cwd)
                            if let timeoutSeconds {
                                request.timeoutSeconds = timeoutSeconds
                            }
                            request.environment = environment
                            return shell.run(request)
                        case let .denied(error):
                            return ToolResult(ok: false, error: error)
                        }
                    case let .denied(error):
                        return ToolResult(ok: false, error: error)
                    }
                case let .denied(error):
                    return ToolResult(ok: false, error: error)
                }
            case ToolDefinition.fileRead.name:
                return files.read(path: try args.requiredString("path"))
            case ToolDefinition.fileWrite.name:
                return files.write(
                    path: try args.requiredString("path"),
                    content: try args.requiredString("content")
                )
            case ToolDefinition.applyPatch.name:
                return patch.apply(unifiedDiff: try args.requiredString("patch"))
            default:
                return ToolResult(ok: false, error: "Unknown tool: \(call.name)")
            }
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    private func shellWorkingDirectory(_ rawValue: String?) -> WorkingDirectoryResolution {
        let root = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
        guard let rawValue else {
            return .allowed(root)
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .allowed(root)
        }
        guard !trimmed.contains("\0"),
              trimmed.rangeOfCharacter(from: .newlines) == nil
        else {
            return .denied("Shell cwd must be a single project-relative or in-project path.")
        }

        let candidate = trimmed.hasPrefix("/")
            ? URL(fileURLWithPath: trimmed)
            : root.appendingPathComponent(trimmed)
        let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
        guard Self.isPath(resolved.path, inside: root.path) else {
            return .denied("Shell cwd must stay inside the current workspace.")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return .denied("Shell cwd does not exist or is not a directory.")
        }
        return .allowed(resolved)
    }

    private func shellTimeoutSeconds(_ args: ToolArguments) -> TimeoutResolution {
        guard let rawValue = args.string("timeoutSeconds") ?? args.string("timeout_seconds") else {
            return .allowed(nil)
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed),
              (Self.minShellTimeoutSeconds...Self.maxShellTimeoutSeconds).contains(value)
        else {
            return .denied(
                "Shell timeoutSeconds must be between \(Self.minShellTimeoutSeconds) and \(Self.maxShellTimeoutSeconds)."
            )
        }
        return .allowed(TimeInterval(value))
    }

    private func shellEnvironment(_ args: ToolArguments) -> EnvironmentResolution {
        let rawEnvironment = args.stringDictionary("environment") ?? args.stringDictionary("env")
        switch EnvironmentOverridePolicy.validateOverrides(rawEnvironment) {
        case let .allowed(overrides):
            guard !overrides.isEmpty else {
                return .allowed(nil)
            }
            var environment = ProcessInfo.processInfo.environment
            for (key, value) in overrides {
                environment[key] = value
            }
            return .allowed(environment)
        case let .denied(error):
            return .denied(error)
        }
    }

    private static func isPath(_ path: String, inside rootPath: String) -> Bool {
        path == rootPath || path.hasPrefix(rootPath + "/")
    }

    private enum WorkingDirectoryResolution {
        case allowed(URL)
        case denied(String)
    }

    private enum TimeoutResolution {
        case allowed(TimeInterval?)
        case denied(String)
    }

    private enum EnvironmentResolution {
        case allowed([String: String]?)
        case denied(String)
    }
}
