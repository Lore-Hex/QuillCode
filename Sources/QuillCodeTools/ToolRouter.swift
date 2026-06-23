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

    public static let definitions: [ToolDefinition] = ShellToolCallDispatcher.definitions + [
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
            if ShellToolCallDispatcher.handles(call.name) {
                return try ShellToolCallDispatcher(workspaceRoot: workspaceRoot, shell: shell)
                    .execute(name: call.name, arguments: args)
            }
            if GitToolCallDispatcher.handles(call.name) {
                return try GitToolCallDispatcher(workspaceRoot: workspaceRoot, git: git)
                    .execute(name: call.name, arguments: args)
            }
            switch call.name {
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
}
