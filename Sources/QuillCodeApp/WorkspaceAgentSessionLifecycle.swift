import Foundation
import QuillCodeCore
import QuillCodePersistence

enum WorkspaceAgentSessionLifecycle: Sendable {
    case primary(WorkspaceSessionStartHookCoordinator)
    case subagent(ProjectPluginSubagentHookContext, runsStartHook: Bool)
}

extension WorkspaceAgentSessionLifecycle {
    static func subagent(
        parentThread: ChatThread,
        job: WorkspaceSubagentJob,
        threadStore: SubagentThreadStore?,
        runsStartHook: Bool
    ) -> WorkspaceAgentSessionLifecycle {
        let transcriptPath = threadStore?.directory
            .appendingPathComponent("\(job.childThreadID.uuidString).json")
            .path
        return .subagent(
            ProjectPluginSubagentHookContext(
                parentThread: parentThread,
                agentID: job.id,
                agentType: job.name,
                transcriptPath: transcriptPath
            ),
            runsStartHook: runsStartHook
        )
    }
}
