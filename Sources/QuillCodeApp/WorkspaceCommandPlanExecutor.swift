import Foundation
import QuillCodeCore

extension QuillCodeWorkspaceModel {
    @discardableResult
    public func runWorkspaceCommand(_ commandID: String, workspaceRoot: URL) -> Bool {
        guard let plan = WorkspaceCommandPlan(commandID: commandID) else { return false }
        return runWorkspaceCommandPlan(plan, workspaceRoot: workspaceRoot)
    }

    @discardableResult
    func runWorkspaceCommandPlan(_ plan: WorkspaceCommandPlan, workspaceRoot: URL) -> Bool {
        switch plan {
        case .localEnvironmentAction(let actionID):
            return runLocalEnvironmentAction(actionID, workspaceRoot: workspaceRoot)
        case .deleteMemory(let id):
            return deleteGlobalMemory(id: id)
        case .updateAutomationStatus(let id, let status):
            return updateAutomationStatus(id: id, status: status)
        case .runAutomation(let id):
            return runAutomation(id: id) != nil
        case .deleteAutomation(let id):
            return deleteAutomation(id: id)
        case .createThreadFollowUpAfter(let seconds):
            return createThreadFollowUpAutomation(after: seconds) != nil
        case .createWorkspaceScheduleAfter(let seconds):
            return createWorkspaceScheduleAutomation(after: seconds) != nil
        case .createThreadFollowUpEvery(let recurrence):
            return createThreadFollowUpAutomation(every: recurrence) != nil
        case .createWorkspaceScheduleEvery(let recurrence):
            return createWorkspaceScheduleAutomation(every: recurrence) != nil
        case .startMCPServer(let id):
            return startMCPServer(id: id, workspaceRoot: workspaceRoot)
        case .stopMCPServer(let id):
            return stopMCPServer(id: id)
        case .updateExtension(let id):
            return runProjectExtensionUpdate(id: id, workspaceRoot: workspaceRoot)
        case .toggleThreadSelection(let id):
            toggleSidebarThreadSelection(id)
            return true
        case .toggleActivitySection(let section):
            toggleActivitySection(section)
            return true
        case .setDraft(let draft):
            setDraft(draft)
            return true
        case .runTool(let toolName):
            runToolCall(
                ToolCall(name: toolName, argumentsJSON: "{}"),
                workspaceRoot: workspaceRoot
            )
            return true
        case .runToolCall(let call):
            runToolCall(call, workspaceRoot: workspaceRoot)
            return true
        case .action(let action):
            return runWorkspaceCommandAction(action)
        }
    }
}
