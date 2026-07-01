import XCTest

final class ParityWorkspaceMemoryModelGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesMemoryCommandOrchestration() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let memoryModelText = try Self.appSourceText(named: "WorkspaceModelMemory.swift")
        let workflowText = try Self.appSourceText(named: "WorkspaceMemoryWorkflow.swift")

        Self.assertSource(workflowText, containsAll: [
            "enum WorkspaceMemoryWorkflow",
            "struct WorkspaceMemoryWorkflowContext",
            "WorkspaceMemoryEngine.updateGlobal",
            "WorkspaceMemoryEngine.updateProject",
            "WorkspaceMemoryEngine.updateRemoteProject",
            "WorkspaceMemoryEngine.deleteGlobal",
            "WorkspaceMemoryEngine.deleteProject",
            "WorkspaceMemoryEngine.deleteRemoteProject"
        ])
        Self.assertSource(memoryModelText, containsAll: [
            "func runRememberSlashCommand",
            "func prepareEditMemory",
            "func runEditMemorySlashCommand",
            "func deleteMemory",
            "func deleteGlobalMemory",
            "func refreshThreadMemoryContext",
            "WorkspaceMemoryEngine.saveGlobal",
            "WorkspaceMemoryWorkflow.update",
            "WorkspaceMemoryWorkflow.delete",
            "WorkspaceMemoryWorkflow.editableNote",
            "WorkspaceProjectContextRefresher.globalMemories",
            "WorkspaceMemoryEngine.contextUpdate"
        ])
        Self.assertSource(memoryModelText, excludesAll: [
            "project?.isRemote == true",
            "id.hasPrefix(\"project:\")",
            "WorkspaceMemoryEngine.updateGlobal",
            "WorkspaceMemoryEngine.updateProject",
            "WorkspaceMemoryEngine.updateRemoteProject",
            "WorkspaceMemoryEngine.deleteGlobal",
            "WorkspaceMemoryEngine.deleteProject",
            "WorkspaceMemoryEngine.deleteRemoteProject"
        ])
        Self.assertSource(modelText, excludesAll: [
            "func runRememberSlashCommand",
            "func runEditMemorySlashCommand",
            "func deleteGlobalMemory",
            "func applyGlobalMemoryMutation",
            "func refreshThreadMemoryContext",
            "It will be included as background context in future turns.",
            "Memory not saved",
            "It will no longer be included as background context.",
            "Memory not deleted",
            "Forgot memory:",
            "MemoryNoteLoader.saveGlobal",
            "MemoryNoteLoader.updateGlobal",
            "MemoryNoteLoader.deleteGlobal",
            "MemoryNoteLoader.deleteProject",
            "MemoryNoteLoader.loadGlobal",
            "MemoryNoteDeleteError.deleteFailed.localizedDescription",
            "payloadJSON: note.relativePath"
        ])
    }
}
