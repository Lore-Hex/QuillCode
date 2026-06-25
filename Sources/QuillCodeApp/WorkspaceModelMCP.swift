import Foundation
import QuillCodeCore
import QuillCodeTools

@MainActor
extension QuillCodeWorkspaceModel {
    @discardableResult
    func startMCPServer(id: String, workspaceRoot: URL) -> Bool {
        guard let manifest = selectedMCPServerManifest(id: id) else {
            setLastError("MCP server manifest not found.")
            return false
        }
        let result = mcpRuntime.startServer(
            manifest: manifest,
            workspaceRoot: workspaceRoot,
            extensions: &extensions
        ) { [weak self] id, terminationStatus in
            self?.finishMCPServerProcess(id: id, terminationStatus: terminationStatus)
        }
        applyMCPRuntimeResult(result)
        return result.ok
    }

    @discardableResult
    func stopMCPServer(id: String) -> Bool {
        guard let manifest = selectedMCPServerManifest(id: id) else {
            setLastError("MCP server manifest not found.")
            return false
        }

        let result = mcpRuntime.stopServer(manifest: manifest, extensions: &extensions)
        applyMCPRuntimeResult(result)
        return result.ok
    }

    @discardableResult
    func readMCPResource(serverID: String, index: Int) -> Bool {
        guard let reference = mcpResourceReference(serverID: serverID, index: index) else {
            setLastError("MCP resource is no longer available.")
            return false
        }

        let call = ToolCall(
            name: ToolDefinition.mcpReadResource.name,
            argumentsJSON: ToolArguments.json([
                "serverID": serverID,
                reference.key: reference.value
            ])
        )
        runMCPReferenceToolCall(call)
        return true
    }

    @discardableResult
    func getMCPPrompt(serverID: String, index: Int) -> Bool {
        guard let promptName = mcpPromptName(serverID: serverID, index: index) else {
            setLastError("MCP prompt is no longer available.")
            return false
        }

        let call = ToolCall(
            name: ToolDefinition.mcpGetPrompt.name,
            argumentsJSON: ToolArguments.json([
                "serverID": serverID,
                "promptName": promptName
            ])
        )
        runMCPReferenceToolCall(call)
        return true
    }

    private func selectedMCPServerManifest(id: String) -> ProjectExtensionManifest? {
        selectedProject?.extensionManifests.first {
            $0.id == id && $0.kind == .mcpServer
        }
    }

    private func mcpResourceReference(serverID: String, index: Int) -> (key: String, value: String)? {
        guard mcpServerCanUseReferences(serverID: serverID),
              let summary = extensions.mcpServerProbeSummaries[serverID],
              summary.resourceNames.indices.contains(index)
        else { return nil }

        if summary.resourceURIs.indices.contains(index) {
            return ("resourceURI", summary.resourceURIs[index])
        }
        return ("resourceName", summary.resourceNames[index])
    }

    private func mcpPromptName(serverID: String, index: Int) -> String? {
        guard mcpServerCanUseReferences(serverID: serverID),
              let summary = extensions.mcpServerProbeSummaries[serverID],
              summary.promptNames.indices.contains(index)
        else { return nil }
        return summary.promptNames[index]
    }

    private func mcpServerCanUseReferences(serverID: String) -> Bool {
        selectedMCPServerManifest(id: serverID)?.isEnabled == true
            && extensions.mcpServerStatuses[serverID] == .ready
            && extensions.mcpServerProbeSummaries[serverID]?.errorMessage == nil
    }

    private func runMCPReferenceToolCall(_ call: ToolCall) {
        if selectedThread == nil {
            _ = newChat()
        }
        let startPlan = WorkspaceToolRunLifecyclePlanner.started()
        setLastError(startPlan.lastError)
        refreshTopBar(agentStatus: startPlan.agentStatus)

        let result = mcpRuntime.execute(call: call, extensions: extensions)
            ?? ToolResult(ok: false, error: "MCP server is not running or is not Ready.")
        mutateSelectedThread { thread in
            WorkspaceToolEventRecorder.append(call: call, result: result, to: &thread)
        }
        appendMCPReferenceAnswer(for: call, result: result)
        refreshTopBar(agentStatus: result.ok ? TopBarAgentStatusLabel.idle : TopBarAgentStatusLabel.failed)
    }

    private func appendMCPReferenceAnswer(for call: ToolCall, result: ToolResult) {
        guard let answer = mcpReferenceAnswer(for: call, result: result) else { return }
        mutateSelectedThread { thread in
            WorkspaceThreadNoticeAppender.appendAssistantNotice(answer, to: &thread)
        }
        if let thread = selectedThread {
            threadPersistence.save(thread)
        }
    }

    private func mcpReferenceAnswer(for call: ToolCall, result: ToolResult) -> String? {
        if !result.ok {
            let details = [result.error, result.stderr.trimmedMCPOutput]
                .compactMap { $0 }
                .joined(separator: "\n")
            return details.isEmpty ? "Command failed." : "Command failed:\n\(details.truncatedMCPOutput)"
        }

        let output = result.stdout.trimmedMCPOutput
        switch call.name {
        case ToolDefinition.mcpReadResource.name:
            return output.map { "MCP resource contents:\n\($0.truncatedMCPOutput)" }
                ?? "MCP resource read completed with no text content."
        case ToolDefinition.mcpGetPrompt.name:
            return output.map { "MCP prompt:\n\($0.truncatedMCPOutput)" }
                ?? "MCP prompt loaded."
        default:
            return nil
        }
    }

    private func applyMCPRuntimeResult(_ result: WorkspaceMCPRuntimeResult) {
        setLastError(result.errorMessage)
        if let agentStatus = result.agentStatus {
            refreshTopBar(agentStatus: agentStatus)
        }
        if let notice = result.notice {
            appendNotice(notice)
        }
    }

    private func finishMCPServerProcess(id: String, terminationStatus: Int32) {
        let result = mcpRuntime.finishServer(
            id: id,
            terminationStatus: terminationStatus,
            extensions: &extensions
        )
        if let agentStatus = result.agentStatus {
            refreshTopBar(agentStatus: agentStatus)
        }
    }
}

private extension String {
    var trimmedMCPOutput: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var truncatedMCPOutput: String {
        count <= 4_000 ? self : "\(prefix(4_000))..."
    }
}
