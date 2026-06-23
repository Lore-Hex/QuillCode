import Foundation
import QuillCodeCore

struct WorkspaceWorktreeOpenContext: Sendable, Hashable {
    var request: WorkspaceWorktreeCreateRequest
    var projectID: UUID
    var mode: AgentMode
    var model: String
    var instructions: [ProjectInstruction]
    var memories: [MemoryNote]

    init(
        request: WorkspaceWorktreeCreateRequest,
        projectID: UUID,
        mode: AgentMode,
        model: String,
        instructions: [ProjectInstruction] = [],
        memories: [MemoryNote] = []
    ) {
        self.request = request
        self.projectID = projectID
        self.mode = mode
        self.model = model
        self.instructions = instructions
        self.memories = memories
    }
}

struct WorkspaceOpenedWorktree: Sendable, Hashable {
    var thread: ChatThread
    var displayName: String
    var noticePayload: String
}

struct WorkspaceWorktreeOpenEngine {
    static func localThread(
        worktreeURL: URL,
        context: WorkspaceWorktreeOpenContext
    ) -> WorkspaceOpenedWorktree {
        let displayName = worktreeURL.lastPathComponent
        let messageText = "Opened worktree `\(displayName)` at `\(worktreeURL.path)`."
        let thread = makeThread(
            titleLabel: label(request: context.request, url: worktreeURL),
            projectID: context.projectID,
            mode: context.mode,
            model: context.model,
            instructions: context.instructions,
            memories: context.memories,
            messageText: messageText,
            noticeSummary: "Opened worktree \(displayName)",
            noticePayload: worktreeURL.path
        )
        return WorkspaceOpenedWorktree(
            thread: thread,
            displayName: displayName,
            noticePayload: worktreeURL.path
        )
    }

    static func remoteThread(
        connection: ProjectConnection,
        context: WorkspaceWorktreeOpenContext
    ) -> WorkspaceOpenedWorktree {
        let displayName = displayName(forRemotePath: connection.path, fallback: connection.displayLabel)
        let messageText = "Opened remote worktree `\(displayName)` at `\(connection.displayLabel)`."
        let thread = makeThread(
            titleLabel: label(request: context.request, path: connection.path),
            projectID: context.projectID,
            mode: context.mode,
            model: context.model,
            instructions: context.instructions,
            memories: context.memories,
            messageText: messageText,
            noticeSummary: "Opened remote worktree \(displayName)",
            noticePayload: connection.displayLabel
        )
        return WorkspaceOpenedWorktree(
            thread: thread,
            displayName: displayName,
            noticePayload: connection.displayLabel
        )
    }

    static func label(request: WorkspaceWorktreeCreateRequest, url: URL) -> String {
        let branch = request.branch.trimmingCharacters(in: .whitespacesAndNewlines)
        if !branch.isEmpty {
            return branch
        }
        return WorkspaceProjectEngine.defaultProjectName(for: url)
    }

    static func label(request: WorkspaceWorktreeCreateRequest, path: String) -> String {
        let branch = request.branch.trimmingCharacters(in: .whitespacesAndNewlines)
        if !branch.isEmpty {
            return branch
        }
        let lastPathComponent = URL(fileURLWithPath: path).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return lastPathComponent.isEmpty ? path : lastPathComponent
    }

    static func displayName(forRemotePath path: String, fallback: String) -> String {
        let pathName = URL(fileURLWithPath: path).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return pathName.isEmpty ? fallback : pathName
    }

    private static func makeThread(
        titleLabel: String,
        projectID: UUID,
        mode: AgentMode,
        model: String,
        instructions: [ProjectInstruction],
        memories: [MemoryNote],
        messageText: String,
        noticeSummary: String,
        noticePayload: String
    ) -> ChatThread {
        ChatThread(
            title: "Worktree: \(titleLabel)",
            projectID: projectID,
            mode: mode,
            model: model,
            messages: [ChatMessage(role: .assistant, content: messageText)],
            events: [
                ThreadEvent(
                    kind: .notice,
                    summary: noticeSummary,
                    payloadJSON: noticePayload
                ),
                ThreadEvent(kind: .message, summary: messageText)
            ],
            instructions: instructions,
            memories: memories
        )
    }
}
