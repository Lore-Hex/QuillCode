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
        .gitRestoreHunk,
        .gitCommit,
        .gitPush,
        .gitPullRequestCreate,
        .gitWorktreeList,
        .gitWorktreeCreate,
        .gitWorktreeRemove
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
                switch shellWorkingDirectory(args.string("cwd")) {
                case let .allowed(cwd):
                    return shell.run(.init(command: command, cwd: cwd))
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
            case ToolDefinition.gitCommit.name:
                return git.commit(cwd: workspaceRoot, message: try args.requiredString("message"))
            case ToolDefinition.gitPush.name:
                return git.push(
                    cwd: workspaceRoot,
                    remote: args.string("remote"),
                    branch: args.string("branch"),
                    setUpstream: args.bool("setUpstream") ?? false
                )
            case ToolDefinition.gitPullRequestCreate.name:
                return git.createPullRequest(
                    cwd: workspaceRoot,
                    title: args.string("title"),
                    body: args.string("body"),
                    base: args.string("base"),
                    head: args.string("head"),
                    draft: args.bool("draft") ?? false,
                    fill: args.bool("fill") ?? false
                )
            case ToolDefinition.gitWorktreeList.name:
                return git.listWorktrees(cwd: workspaceRoot)
            case ToolDefinition.gitWorktreeCreate.name:
                return git.createWorktree(
                    cwd: workspaceRoot,
                    path: try args.requiredString("path"),
                    branch: args.string("branch"),
                    base: args.string("base")
                )
            case ToolDefinition.gitWorktreeRemove.name:
                return git.removeWorktree(
                    cwd: workspaceRoot,
                    path: try args.requiredString("path"),
                    force: args.bool("force") ?? false
                )
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

    private static func isPath(_ path: String, inside rootPath: String) -> Bool {
        path == rootPath || path.hasPrefix(rootPath + "/")
    }

    private enum WorkingDirectoryResolution {
        case allowed(URL)
        case denied(String)
    }
}
