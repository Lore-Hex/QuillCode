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
        var browser = browser
        var lastError: String?
        return execute(call, browser: &browser, lastError: &lastError)
    }

    func execute(
        _ call: ToolCall,
        browser: inout BrowserState,
        lastError: inout String?
    ) -> WorkspaceToolCallExecution {
        let primary = WorkspaceRecordedToolResult(
            call: call,
            result: executePrimary(call, browser: &browser, lastError: &lastError)
        )
        return WorkspaceToolCallExecution(
            primary: primary,
            followUps: followUps(after: primary, browser: &browser, lastError: &lastError)
        )
    }

    func executePrimary(_ call: ToolCall) -> ToolResult {
        var browser = browser
        var lastError: String?
        return executePrimary(call, browser: &browser, lastError: &lastError)
    }

    func executePrimary(
        _ call: ToolCall,
        browser: inout BrowserState,
        lastError: inout String?
    ) -> ToolResult {
        if let result = WorkspaceBrowserToolExecutor.execute(
            call,
            workspaceRoot: router.workspaceRoot,
            browser: &browser,
            lastError: &lastError
        ) {
            return result
        }
        if call.name == ToolDefinition.planUpdate.name {
            return PlanUpdateToolExecutor.execute(call)
        }
        if call.name == ToolDefinition.handoffUpdate.name {
            return HandoffUpdateToolExecutor.execute(call)
        }
        if call.name == ToolDefinition.subagentsUpdate.name {
            return SubagentProgressToolExecutor.execute(call)
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

    private func followUps(
        after primary: WorkspaceRecordedToolResult,
        browser: inout BrowserState,
        lastError: inout String?
    ) -> [WorkspaceRecordedToolResult] {
        guard primary.call.name == ToolDefinition.applyPatch.name,
              primary.result.ok
        else {
            return []
        }
        let diffCall = ToolCall(name: ToolDefinition.gitDiff.name, argumentsJSON: "{}")
        return [WorkspaceRecordedToolResult(
            call: diffCall,
            result: executePrimary(diffCall, browser: &browser, lastError: &lastError)
        )]
    }
}
