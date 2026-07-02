import Foundation
import QuillCodeCore
import QuillCodeTools

public struct WorkspaceWorktreePrunePreview: Sendable, Hashable {
    public var records: [String]
    public var output: String
    public var errorMessage: String?

    public init(records: [String] = [], output: String = "", errorMessage: String? = nil) {
        self.records = records
        self.output = output
        self.errorMessage = errorMessage
    }
}

public struct WorkspaceWorktreePrunePreviewLoadRequest: Sendable {
    public var workspaceRoot: URL
    public var selectedProject: ProjectRef?
    public var sshRemoteShellExecutor: SSHRemoteShellExecutor

    public init(
        workspaceRoot: URL,
        selectedProject: ProjectRef?,
        sshRemoteShellExecutor: SSHRemoteShellExecutor = SSHRemoteShellExecutor()
    ) {
        self.workspaceRoot = workspaceRoot
        self.selectedProject = selectedProject
        self.sshRemoteShellExecutor = sshRemoteShellExecutor
    }

    public func load() -> WorkspaceWorktreePrunePreview {
        let call = WorkspaceWorktreeToolCallPlanner.prune(.init(dryRun: true, verbose: true))
        let result: ToolResult
        if let selectedProject, selectedProject.isRemote {
            result = WorkspaceRemoteProjectToolExecutor.execute(
                call,
                project: selectedProject,
                executor: sshRemoteShellExecutor
            )
        } else {
            // Detached edit session: this loader only runs read-only git worktree tools,
            // so nothing here may mark or consult any model session's read-set.
            result = ToolRouter(workspaceRoot: workspaceRoot, editGuard: FileEditSessionGuard()).execute(call)
        }

        guard result.ok else {
            return WorkspaceWorktreePrunePreview(errorMessage: Self.errorMessage(from: result))
        }
        let output = WorkspaceWorktreePrunePreviewSurfaceBuilder.combinedOutput(from: result)
        return WorkspaceWorktreePrunePreview(
            records: WorkspaceWorktreePrunePreviewSurfaceBuilder.records(from: output),
            output: output
        )
    }

    private static func errorMessage(from result: ToolResult) -> String {
        let candidates = [result.error, result.stderr, result.stdout]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let message = candidates.first else {
            return "Could not preview stale worktree records."
        }
        return String(message.prefix(240))
    }
}

enum WorkspaceWorktreePrunePreviewSurfaceBuilder {
    static func combinedOutput(from result: ToolResult) -> String {
        [result.stdout, result.stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    static func records(from output: String) -> [String] {
        Array(output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
            .prefix(20)
            .map { String($0) }
    }
}
