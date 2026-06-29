import Foundation
import QuillCodeCore
import QuillCodeTools

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
        case .editMemory(let id):
            return prepareEditMemory(id: id)
        case .deleteMemory(let id):
            return deleteMemory(id: id)
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
        case .readMCPResource(let serverID, let index):
            return readMCPResource(serverID: serverID, index: index)
        case .getMCPPrompt(let serverID, let index):
            return getMCPPrompt(serverID: serverID, index: index)
        case .installExtension(let id):
            return runProjectExtensionInstall(id: id, workspaceRoot: workspaceRoot)
        case .updateExtension(let id):
            return runProjectExtensionUpdate(id: id, workspaceRoot: workspaceRoot)
        case .toggleThreadSelection(let id):
            toggleSidebarThreadSelection(id)
            return true
        case .setSidebarFilter(let filter):
            setSidebarFilter(filter)
            return true
        case .setSidebarSavedSearch(let id):
            return setSidebarSavedSearch(id)
        case .deleteSidebarSavedSearch(let id):
            return deleteSidebarSavedSearch(id)
        case .newBrowserTab:
            _ = newBrowserTab()
            return true
        case .selectBrowserTab(let id):
            return selectBrowserTab(id: id)
        case .closeBrowserTab(let id):
            return closeBrowserTab(id: id)
        case .toggleActivitySection(let section):
            toggleActivitySection(section)
            return true
        case .openActivitySource(let path):
            runToolCall(
                ToolCall(
                    name: ToolDefinition.fileRead.name,
                    argumentsJSON: ToolArguments.json(["path": path])
                ),
                workspaceRoot: workspaceRoot
            )
            return true
        case .editActivitySource(let path):
            setDraft("Edit instruction source \(path): ")
            return true
        case .resolveInstructionDiagnostic(let id):
            return prepareResolveInstructionDiagnostic(id: id)
        case .dismissInstructionDiagnostic(let id):
            return dismissInstructionDiagnostic(id: id)
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

    private func prepareResolveInstructionDiagnostic(id: String) -> Bool {
        guard let diagnostic = selectedInstructionDiagnostics.first(where: { $0.id == id }) else {
            return false
        }
        setDraft("Resolve instruction issue \"\(diagnostic.title)\" (\(diagnostic.detail)). Update the relevant instruction files so the guidance is consistent: ")
        return true
    }

    private var selectedInstructionDiagnostics: [ProjectInstructionDiagnostic] {
        guard let thread = selectedThread else { return [] }
        return ProjectInstructionDiagnosticsBuilder.diagnostics(for: thread.instructions)
    }
}
