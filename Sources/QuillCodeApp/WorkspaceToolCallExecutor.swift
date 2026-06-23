import Foundation
import QuillCodeCore
import QuillCodeTools

struct WorkspaceRecordedToolResult: Sendable, Hashable {
    let call: ToolCall
    let result: ToolResult
}

struct WorkspaceToolCallExecution: Sendable, Hashable {
    let primary: WorkspaceRecordedToolResult
    let followUps: [WorkspaceRecordedToolResult]

    var ok: Bool {
        primary.result.ok && followUps.allSatisfy(\.result.ok)
    }
}

struct WorkspaceToolCallExecutor: Sendable {
    let selectedProject: ProjectRef?
    let browser: BrowserState
    let router: ToolRouter
    let sshRemoteShellExecutor: SSHRemoteShellExecutor

    func execute(_ call: ToolCall) -> WorkspaceToolCallExecution {
        let primary = WorkspaceRecordedToolResult(call: call, result: executePrimary(call))
        return WorkspaceToolCallExecution(
            primary: primary,
            followUps: followUps(after: primary)
        )
    }

    func executePrimary(_ call: ToolCall) -> ToolResult {
        if call.name == ToolDefinition.browserInspect.name {
            return BrowserInspector.toolResult(from: browser)
        }
        if call.name == ToolDefinition.planUpdate.name {
            return PlanUpdateToolExecutor.execute(call)
        }
        if let project = selectedProject, project.isRemote {
            return WorkspaceRemoteProjectToolExecutor.execute(
                call,
                project: project,
                executor: sshRemoteShellExecutor
            )
        }
        return router.execute(call)
    }

    private func followUps(after primary: WorkspaceRecordedToolResult) -> [WorkspaceRecordedToolResult] {
        guard primary.call.name == ToolDefinition.applyPatch.name,
              primary.result.ok
        else {
            return []
        }
        let diffCall = ToolCall(name: ToolDefinition.gitDiff.name, argumentsJSON: "{}")
        return [WorkspaceRecordedToolResult(call: diffCall, result: executePrimary(diffCall))]
    }
}
