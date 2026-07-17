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
        case .retryAutoReviewDenial(let requestID):
            Task { await retryAutoReviewDenial(requestID: requestID, workspaceRoot: workspaceRoot) }
            return true
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
        case .setHookTrust(let id, let decision):
            return setProjectHookTrust(id: id, decision: decision)
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
        case .moveSidebarSavedSearch(let id, let direction):
            return moveSidebarSavedSearch(id, direction: direction)
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
        case .openActivitySource(let path, let lineNumber):
            runToolCall(
                ToolCall(
                    name: ToolDefinition.fileRead.name,
                    argumentsJSON: Self.activitySourceReadArguments(path: path, lineNumber: lineNumber)
                ),
                workspaceRoot: workspaceRoot
            )
            return true
        case .editActivitySource(let path, let lineNumber):
            setDraft(Self.activitySourceEditDraft(path: path, lineNumber: lineNumber))
            return true
        case .applyInstructionDiagnostic(let id, let selectedReferenceIndex):
            return applyInstructionDiagnostic(
                id: id,
                selectedReferenceIndex: selectedReferenceIndex,
                workspaceRoot: workspaceRoot
            )
        case .resolveInstructionDiagnostic(let id):
            return prepareResolveInstructionDiagnostic(id: id)
        case .dismissInstructionDiagnostic(let id):
            return dismissInstructionDiagnostic(id: id)
        case .resolveSubagentApproval(let command):
            Task { await resolveSubagentApproval(command, workspaceRoot: workspaceRoot) }
            return true
        case .setDraft(let draft):
            setDraft(draft)
            return true
        case .runTool(let toolName):
            if toolName == ToolDefinition.gitDiff.name {
                chrome.reviewPresentation = .visible
            }
            runToolCall(
                ToolCall(name: toolName, argumentsJSON: "{}"),
                workspaceRoot: workspaceRoot
            )
            return true
        case .runToolCall(let call):
            runToolCall(call, workspaceRoot: workspaceRoot)
            return true
        case .action(let action):
            return runWorkspaceCommandAction(action, workspaceRoot: workspaceRoot)
        }
    }

    private static func activitySourceReadArguments(path: String, lineNumber: Int?) -> String {
        guard let lineNumber else {
            return ToolArguments.json(["path": path])
        }
        return ToolArguments.json([
            "limit": 120,
            "offset": lineNumber,
            "path": path
        ])
    }

    private static func activitySourceEditDraft(path: String, lineNumber: Int?) -> String {
        guard let lineNumber else {
            return "Edit instruction source \(path): "
        }
        return "Edit instruction source \(path):\(lineNumber): "
    }

    private func prepareResolveInstructionDiagnostic(id: String) -> Bool {
        guard let diagnostic = activeInstructionDiagnostics.first(where: { $0.id == id }) else {
            return false
        }
        setDraft(Self.instructionResolutionDraft(for: diagnostic))
        return true
    }

    private func applyInstructionDiagnostic(
        id: String,
        selectedReferenceIndex: Int,
        workspaceRoot: URL
    ) -> Bool {
        guard let diagnostic = activeInstructionDiagnostics.first(where: { $0.id == id }),
              let plan = ProjectInstructionDiagnosticApplyPlanner.plan(
                for: diagnostic,
                selectedReferenceIndex: selectedReferenceIndex,
                instructions: activeInstructionSources
              )
        else {
            return false
        }

        // The tool run below edits instruction files whose loaded content produced this plan, so
        // the UI session legitimately knows them. Mark ONLY the files the plan actually edits —
        // and only those whose content was genuinely loaded — never the untouched (kept) ones.
        let loadedPaths = Set(activeInstructionSources.map(\.path))
        let resolver = FileWorkspacePathResolver(workspaceRoot: workspaceRoot)
        for path in Self.plannedInstructionEditPaths(of: plan.toolCall) where loadedPaths.contains(path) {
            if let url = try? resolver.resolve(path) {
                uiEditSessionGuard.markRead(url)
            }
        }

        let result = runToolCall(
            plan.toolCall,
            workspaceRoot: workspaceRoot
        )
        if result.ok, let projectID = selectedThread?.projectID ?? root.selectedProjectID {
            _ = refreshProjectContext(projectID)
        }
        return true
    }

    /// The workspace-relative files a planned instruction-diagnostic edit will actually touch.
    static func plannedInstructionEditPaths(of call: ToolCall) -> [String] {
        guard let arguments = try? ToolArguments(call.argumentsJSON) else { return [] }
        if call.name == ToolDefinition.fileWrite.name {
            return (try? arguments.requiredString("path")).map { [$0] } ?? []
        }
        if call.name == ToolDefinition.applyPatch.name {
            return (try? arguments.requiredString("patch")).map(PatchToolExecutor.targetPaths(in:)) ?? []
        }
        return []
    }

    static func instructionResolutionDraft(for diagnostic: ProjectInstructionDiagnostic) -> String {
        let references = diagnostic.sourceReferences.map { reference in
            [
                "- \(reference.locationLabel) [\(reference.role)]",
                "  Current: \(reference.excerpt)",
                reference.suggestedAction.isEmpty ? nil : "  Suggested: \(reference.suggestedAction)"
            ]
            .compactMap(\.self)
            .joined(separator: "\n")
        }
        .joined(separator: "\n")
        let targets = references.isEmpty
            ? "- \(diagnostic.detail)"
            : references
        let hint = diagnostic.resolutionHint.isEmpty
            ? "Update the relevant instruction files so the guidance is consistent."
            : diagnostic.resolutionHint

        return """
        Resolve instruction issue "\(diagnostic.title)".
        Issue: \(diagnostic.detail)
        Targets:
        \(targets)
        Suggested fix: \(hint)
        Apply the smallest instruction-file edit needed:
        """
    }
}
