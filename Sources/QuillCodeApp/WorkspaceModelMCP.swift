import Foundation
import QuillCodeCore

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

    private func selectedMCPServerManifest(id: String) -> ProjectExtensionManifest? {
        selectedProject?.extensionManifests.first {
            $0.id == id && $0.kind == .mcpServer
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
