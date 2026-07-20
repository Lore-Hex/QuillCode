import Foundation
import QuillCodeCore

struct ShellToolCallDispatcher: Sendable {
    let workspaceRoot: URL
    let shell: ShellToolExecutor
    let accessScope: HostToolAccessScope

    static let definitions: [ToolDefinition] = [
        .shellRun
    ]

    private static let toolNames = Set(definitions.map(\.name))
    private static let minTimeoutSeconds = 1
    private static let maxTimeoutSeconds = 1_800
    private static let maxStandardInputBytes = 1_048_576

    static func handles(_ toolName: String) -> Bool {
        toolNames.contains(toolName)
    }

    func execute(name: String, arguments args: ToolArguments) throws -> ToolResult {
        switch try request(name: name, arguments: args) {
        case .allowed(let request):
            shell.run(request)
        case .denied(let error):
            ToolResult(ok: false, error: error)
        }
    }

    func executeCancellable(name: String, arguments args: ToolArguments) async throws -> ToolResult {
        switch try request(name: name, arguments: args) {
        case .allowed(let request):
            await shell.runCancellable(request)
        case .denied(let error):
            ToolResult(ok: false, error: error)
        }
    }

    private func request(name: String, arguments args: ToolArguments) throws -> RequestResolution {
        guard name == ToolDefinition.shellRun.name else {
            return .denied("Unknown tool: \(name)")
        }
        let command = try args.requiredString("cmd")
        switch workingDirectory(args.string("cwd")) {
        case let .allowed(cwd):
            switch timeoutSeconds(args) {
            case let .allowed(timeoutSeconds):
                switch environment(args) {
                case let .allowed(environment):
                    switch standardInput(args) {
                    case let .allowed(standardInput):
                        var request = ShellExecutionRequest(command: command, cwd: cwd)
                        if let timeoutSeconds {
                            request.timeoutSeconds = timeoutSeconds
                        }
                        request.environment = environment
                        request.standardInput = standardInput
                        return .allowed(request)
                    case let .denied(error):
                        return .denied(error)
                    }
                case let .denied(error):
                    return .denied(error)
                }
            case let .denied(error):
                return .denied(error)
            }
        case let .denied(error):
            return .denied(error)
        }
    }

    private func workingDirectory(_ rawValue: String?) -> WorkingDirectoryResolution {
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
        guard accessScope.allowsPathsOutsideWorkspace
                || Self.isPath(resolved.path, inside: root.path)
        else {
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

    private func timeoutSeconds(_ args: ToolArguments) -> TimeoutResolution {
        guard let rawValue = args.string("timeoutSeconds") ?? args.string("timeout_seconds") else {
            return .allowed(nil)
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed),
              (Self.minTimeoutSeconds...Self.maxTimeoutSeconds).contains(value)
        else {
            return .denied(
                "Shell timeoutSeconds must be between \(Self.minTimeoutSeconds) and \(Self.maxTimeoutSeconds)."
            )
        }
        return .allowed(TimeInterval(value))
    }

    private func environment(_ args: ToolArguments) -> EnvironmentResolution {
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

    private func standardInput(_ args: ToolArguments) -> StandardInputResolution {
        guard let standardInput = args.string("stdin") else {
            return .allowed(nil)
        }
        guard standardInput.utf8.count <= Self.maxStandardInputBytes else {
            return .denied("Shell stdin must be at most \(Self.maxStandardInputBytes) UTF-8 bytes.")
        }
        return .allowed(standardInput)
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

    private enum StandardInputResolution {
        case allowed(String?)
        case denied(String)
    }

    private enum RequestResolution {
        case allowed(ShellExecutionRequest)
        case denied(String)
    }
}
