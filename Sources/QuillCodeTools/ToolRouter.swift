import Foundation
import QuillCodeCore

public struct ToolRouter: Sendable {
    public var workspaceRoot: URL
    public var shell: ShellToolExecutor
    public var files: FileToolExecutor
    public var git: GitToolExecutor
    public var patch: PatchToolExecutor

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
        .applyPatch,
        .gitStatus,
        .gitDiff,
        .gitStage,
        .gitRestore,
        .gitStageHunk,
        .gitRestoreHunk
    ]

    public func definition(named name: String) -> ToolDefinition? {
        Self.definitions.first { $0.name == name }
    }

    public func execute(_ call: ToolCall) -> ToolResult {
        do {
            let args = try ToolArguments(call.argumentsJSON)
            switch call.name {
            case ToolDefinition.shellRun.name:
                let command = try args.requiredString("cmd")
                let cwd = args.string("cwd").map { URL(fileURLWithPath: $0) } ?? workspaceRoot
                return shell.run(.init(command: command, cwd: cwd))
            case ToolDefinition.fileRead.name:
                return files.read(path: try args.requiredString("path"))
            case ToolDefinition.fileWrite.name:
                return files.write(
                    path: try args.requiredString("path"),
                    content: try args.requiredString("content")
                )
            case ToolDefinition.applyPatch.name:
                return patch.apply(unifiedDiff: try args.requiredString("patch"))
            case ToolDefinition.gitStatus.name:
                return git.status(cwd: workspaceRoot)
            case ToolDefinition.gitDiff.name:
                return git.diff(cwd: workspaceRoot, staged: args.bool("staged") ?? false)
            case ToolDefinition.gitStage.name:
                return git.stage(cwd: workspaceRoot, path: try args.requiredString("path"))
            case ToolDefinition.gitRestore.name:
                return git.restore(
                    cwd: workspaceRoot,
                    path: try args.requiredString("path"),
                    staged: args.bool("staged") ?? false
                )
            case ToolDefinition.gitStageHunk.name:
                return git.stageHunk(
                    cwd: workspaceRoot,
                    path: try args.requiredString("path"),
                    patch: try args.requiredString("patch")
                )
            case ToolDefinition.gitRestoreHunk.name:
                return git.restoreHunk(
                    cwd: workspaceRoot,
                    path: try args.requiredString("path"),
                    patch: try args.requiredString("patch")
                )
            default:
                return ToolResult(ok: false, error: "Unknown tool: \(call.name)")
            }
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }
}
