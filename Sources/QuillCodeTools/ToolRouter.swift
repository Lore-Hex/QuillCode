import Foundation
import QuillCodeCore

public struct ToolRouter: Sendable {
    public var workspaceRoot: URL
    public var shell: ShellToolExecutor
    public var files: FileToolExecutor
    public var git: GitToolExecutor
    public var patch: PatchToolExecutor
    public var web: WebFetchToolExecutor
    public var skill: SkillLoadToolExecutor
    /// LSP integration. `nil` (the default) disables every LSP behavior: diagnostics-after-write and
    /// format-on-save are skipped and `host.lsp.*` reports "not available". Injecting a coordinator
    /// (e.g. from the desktop/CLI runtime) turns the features on without changing any existing tool.
    public var lsp: LSPCoordinator?

    public init(
        workspaceRoot: URL,
        shell: ShellToolExecutor = ShellToolExecutor(),
        git: GitToolExecutor? = nil,
        managedWorktreeRoot: URL? = nil,
        editGuard: FileEditSessionGuard = .shared,
        web: WebFetchToolExecutor = WebFetchToolExecutor(),
        skill: SkillLoadToolExecutor? = nil,
        lsp: LSPCoordinator? = nil
    ) {
        self.workspaceRoot = workspaceRoot
        self.shell = shell
        self.files = FileToolExecutor(workspaceRoot: workspaceRoot, editGuard: editGuard)
        self.git = git ?? GitToolExecutor(managedWorktreeRoot: managedWorktreeRoot)
        self.patch = PatchToolExecutor(workspaceRoot: workspaceRoot, shell: shell, editGuard: editGuard)
        self.web = web
        self.skill = skill ?? SkillLoadToolExecutor.default(workspaceRoot: workspaceRoot)
        self.lsp = lsp
    }

    public static let definitions: [ToolDefinition] = ShellToolCallDispatcher.definitions + [
        .fileRead,
        .fileList,
        .fileSearch,
        .fileWrite,
        .applyPatch,
        .webFetch,
        .webSearch,
        .skillLoad
    ] + GitToolCallDispatcher.definitions + LSPToolCallDispatcher.definitions

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
            if LSPToolCallDispatcher.handles(call.name) {
                return try LSPToolCallDispatcher(workspaceRoot: workspaceRoot, coordinator: lsp)
                    .execute(name: call.name, arguments: args)
            }
            switch call.name {
            case ToolDefinition.fileRead.name:
                return files.read(
                    path: try args.requiredString("path"),
                    offset: args.int("offset"),
                    limit: args.int("limit")
                )
            case ToolDefinition.fileList.name:
                return files.list(
                    path: args.string("path") ?? ".",
                    includeHidden: args.bool("includeHidden") ?? false,
                    maxEntries: args.int("maxEntries")
                )
            case ToolDefinition.fileSearch.name:
                return files.search(
                    query: try args.requiredString("query"),
                    path: args.string("path") ?? ".",
                    maxResults: args.int("maxResults")
                )
            case ToolDefinition.fileWrite.name:
                let path = try args.requiredString("path")
                let result = files.write(
                    path: path,
                    content: try args.requiredString("content", allowingEmpty: true)
                )
                return withLSPFeedback(result, writtenPaths: [path])
            case ToolDefinition.applyPatch.name:
                let patchText = try args.requiredString("patch")
                let result = patch.apply(unifiedDiff: patchText)
                let touched = PatchToolExecutor.targetPaths(in: patchText)
                return withLSPFeedback(result, writtenPaths: touched)
            case ToolDefinition.webFetch.name:
                return web.fetch(urlString: try args.requiredString("url"))
            case ToolDefinition.webSearch.name:
                // `host.web.search` is async and routes through TrustedRouter, so the live agent
                // loop dispatches it directly to a `WebSearchToolExecutor` (see AgentToolStepRunner)
                // rather than through this synchronous router. Reaching here means no search client
                // was wired (mock runtime, or a direct router call), so report it plainly instead of
                // as an "unknown tool".
                return ToolResult(
                    ok: false,
                    error: "Web search is not available in this workspace. Sign in to TrustedRouter or configure an API key."
                )
            case ToolDefinition.skillLoad.name:
                return skill.load(name: try args.requiredString("name"))
            default:
                return ToolResult(ok: false, error: "Unknown tool: \(call.name)")
            }
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    /// After a successful write/patch, run the LSP post-write pass (format-on-save + project-wide
    /// diagnostics) and append its notice to the result's `stdout`. A no-op when no coordinator is
    /// wired or the result already failed — the write's own behavior is never altered on failure.
    private func withLSPFeedback(_ result: ToolResult, writtenPaths: [String]) -> ToolResult {
        guard let lsp, result.ok, !writtenPaths.isEmpty else { return result }
        // Resolve to absolute URLs inside the workspace; silently drop anything that fails the
        // boundary check (a hostile path never reaches the LSP layer).
        let resolver = FileWorkspacePathResolver(workspaceRoot: workspaceRoot)
        let urls = writtenPaths.compactMap { try? resolver.resolve($0) }
        guard !urls.isEmpty else { return result }

        let feedback = lsp.afterWrite(paths: urls)
        guard let notice = feedback.notice, !notice.isEmpty else { return result }
        var updated = result
        let separator = updated.stdout.isEmpty || updated.stdout.hasSuffix("\n") ? "" : "\n"
        updated.stdout += "\(separator)\n\(notice)\n"
        return updated
    }
}
