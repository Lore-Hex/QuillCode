import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

struct WorkspaceRemoteProjectToolExecutor: Sendable, Hashable {
    static let toolDefinitions = WorkspaceRemoteProjectToolCatalog.toolDefinitions
    static let gitToolNames = WorkspaceRemoteProjectToolCatalog.gitToolNames

    static func executionOverride(
        project: ProjectRef?,
        executor: SSHRemoteShellExecutor,
        appServer: (any SSHRemoteAppServerExecuting)? = nil
    ) -> AgentToolExecutionOverride? {
        guard let project, project.isRemote else { return nil }
        return { call, _ in
            let context = WorkspaceRemoteProjectToolExecutionContext(
                connection: project.connection,
                executor: executor
            )
            guard let appServer else {
                return executeIfSupported(call, context: context)
            }
            return await executeIfSupported(call, context: context, appServer: appServer)
        }
    }

    static func execute(
        _ call: ToolCall,
        project: ProjectRef,
        executor: SSHRemoteShellExecutor
    ) -> ToolResult {
        guard project.isRemote else {
            return unavailableToolResult(call.name)
        }
        return execute(call, connection: project.connection, executor: executor)
    }

    static func execute(
        _ call: ToolCall,
        connection: ProjectConnection,
        executor: SSHRemoteShellExecutor
    ) -> ToolResult {
        executeIfSupported(
            call,
            context: .init(connection: connection, executor: executor)
        )
            ?? unavailableToolResult(call.name)
    }

    static func executeIfSupported(
        _ call: ToolCall,
        connection: ProjectConnection,
        executor: SSHRemoteShellExecutor
    ) -> ToolResult? {
        executeIfSupported(
            call,
            context: .init(connection: connection, executor: executor)
        )
    }

    private static func executeIfSupported(
        _ call: ToolCall,
        context: WorkspaceRemoteProjectToolExecutionContext
    ) -> ToolResult? {
        do {
            guard let plan = try plan(call, context: context) else { return nil }
            return context.run(plan)
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    private static func executeIfSupported(
        _ call: ToolCall,
        context: WorkspaceRemoteProjectToolExecutionContext,
        appServer: any SSHRemoteAppServerExecuting
    ) async -> ToolResult? {
        do {
            guard let plan = try plan(call, context: context) else { return nil }
            let outcome = await appServer.execute(
                command: plan.command,
                connection: plan.connection,
                timeoutSeconds: plan.timeoutSeconds
            )
            switch outcome {
            case .completed(let result):
                return plan.finalize(result)
            case .unavailableBeforeExecution:
                return context.run(plan)
            case .executionStateUnknown(let detail):
                return ToolResult(
                    ok: false,
                    error: "The SSH Remote command may have run before the app-server connection was lost. QuillCode did not retry it to avoid duplicate changes. Verify the remote project before trying again. \(detail)"
                )
            }
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    private static func plan(
        _ call: ToolCall,
        context: WorkspaceRemoteProjectToolExecutionContext
    ) throws -> WorkspaceRemoteProjectCommandPlan? {
        switch call.name {
        case ToolDefinition.shellRun.name:
            return try remoteShellPlan(call, context: context)
        case ToolDefinition.fileRead.name, ToolDefinition.fileList.name, ToolDefinition.fileWrite.name:
            return try WorkspaceRemoteProjectFileToolExecutor.plan(call, context: context)
        case ToolDefinition.applyPatch.name:
            return try remotePatchPlan(call, context: context)
        case let name where Self.gitToolNames.contains(name):
            return try remoteGitPlan(call, context: context)
        default:
            return nil
        }
    }

    private static func unavailableToolResult(_ toolName: String) -> ToolResult {
        ToolResult(ok: false, error: "Tool is not available for SSH Remote projects: \(toolName)")
    }

    private static func remoteGitPlan(
        _ call: ToolCall,
        context: WorkspaceRemoteProjectToolExecutionContext
    ) throws -> WorkspaceRemoteProjectCommandPlan {
        let plannedRequest = try WorkspaceRemoteGitToolRequestPlanner.request(
            for: call,
            connection: context.connection
        )
        return WorkspaceRemoteProjectCommandPlan(
            command: plannedRequest.command,
            connection: context.connection
        ) { result in
            var result = result
            if plannedRequest.extractsPullRequestURLs, result.ok {
                result.artifacts = GitHubPullRequestOutputParser.extractURLs(from: result.stdout)
            } else if result.ok, !plannedRequest.artifacts.isEmpty {
                result.artifacts = plannedRequest.artifacts
            }
            return result
        }
    }

    private static func remotePatchPlan(
        _ call: ToolCall,
        context: WorkspaceRemoteProjectToolExecutionContext
    ) throws -> WorkspaceRemoteProjectCommandPlan {
        let args = try ToolArguments(call.argumentsJSON)
        var patch = try args.requiredString("patch")
        let trimmedPatch = patch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPatch.isEmpty else { throw PatchToolError.emptyPatch }
        if let unsafePath = PatchToolExecutor.unsafePath(in: patch) {
            throw PatchToolError.unsafePath(unsafePath)
        }
        if !patch.hasSuffix("\n") {
            patch.append("\n")
        }

        let encoded = Data(patch.utf8).base64EncodedString()
        let command = [
            "patch_file=\"${TMPDIR:-/tmp}/quillcode.$$.patch\"",
            "trap 'rm -f \"$patch_file\"' EXIT",
            "printf %s \(shellSingleQuoted(encoded)) | base64 --decode > \"$patch_file\"",
            "git apply --check \"$patch_file\"",
            "git apply \"$patch_file\"",
            "printf 'Patch applied.\\n'"
        ].joined(separator: " && ")

        return WorkspaceRemoteProjectCommandPlan(command: command, connection: context.connection)
    }

    private static func remoteShellPlan(
        _ call: ToolCall,
        context: WorkspaceRemoteProjectToolExecutionContext
    ) throws -> WorkspaceRemoteProjectCommandPlan {
        let args = try ToolArguments(call.argumentsJSON)
        let command = try remoteShellCommand(
            try args.requiredString("cmd"),
            arguments: args
        )
        let requestConnection = WorkspaceRemoteProjectPath.shellConnection(
            context.connection,
            cwd: args.string("cwd")
        )
        let timeoutSeconds = try remoteShellTimeout(arguments: args)
        return WorkspaceRemoteProjectCommandPlan(
            command: command,
            connection: requestConnection,
            timeoutSeconds: timeoutSeconds
        )
    }

    private static func remoteShellCommand(
        _ command: String,
        arguments: ToolArguments
    ) throws -> String {
        let rawEnvironment = arguments.stringDictionary("environment")
            ?? arguments.stringDictionary("env")
        let environment: [String: String]
        switch EnvironmentOverridePolicy.validateOverrides(rawEnvironment) {
        case .allowed(let overrides):
            environment = overrides
        case .denied(let error):
            throw WorkspaceRemoteProjectShellPlanError.invalidArguments(error)
        }

        let standardInput = arguments.string("stdin")
        if let standardInput, standardInput.utf8.count > 1_048_576 {
            throw WorkspaceRemoteProjectShellPlanError.invalidArguments(
                "Shell stdin must be at most 1048576 UTF-8 bytes."
            )
        }
        guard !environment.isEmpty || standardInput != nil else { return command }

        let environmentArguments = environment.keys.sorted().map {
            shellSingleQuoted("\($0)=\(environment[$0] ?? "")")
        }
        let shellCommand = (["env"] + environmentArguments + [
            "/bin/sh",
            "-c",
            shellSingleQuoted(command)
        ]).joined(separator: " ")
        guard let standardInput else { return shellCommand }
        let encodedInput = Data(standardInput.utf8).base64EncodedString()
        return "printf %s \(shellSingleQuoted(encodedInput)) | base64 --decode | \(shellCommand)"
    }

    private static func remoteShellTimeout(arguments: ToolArguments) throws -> TimeInterval {
        guard let rawValue = arguments.string("timeoutSeconds")
            ?? arguments.string("timeout_seconds") else {
            return 60
        }
        guard let value = Int(rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...1_800).contains(value) else {
            throw WorkspaceRemoteProjectShellPlanError.invalidArguments(
                "Shell timeoutSeconds must be between 1 and 1800."
            )
        }
        return TimeInterval(value)
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        WorkspaceTerminalSessionAdapter.shellSingleQuoted(value)
    }
}

private enum WorkspaceRemoteProjectShellPlanError: Error, CustomStringConvertible {
    case invalidArguments(String)

    var description: String {
        switch self {
        case .invalidArguments(let detail): detail
        }
    }
}
