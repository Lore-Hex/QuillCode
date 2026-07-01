import XCTest

final class ParityWorkspaceMemoryModelGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesMemoryCommandOrchestration() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let memoryModelText = try Self.appSourceText(named: "WorkspaceModelMemory.swift")
        let workflowText = try Self.appSourceText(named: "WorkspaceMemoryWorkflow.swift")
        let engineText = try Self.appSourceText(named: "WorkspaceMemoryEngine.swift")
        let loaderText = try Self.appSourceText(named: "MemoryNoteLoader.swift")
        let contentPolicyText = try Self.appSourceText(named: "MemoryNoteContentPolicy.swift")
        let pathResolverText = try Self.appSourceText(named: "MemoryNotePathResolver.swift")
        let remoteUpdaterText = try Self.appSourceText(
            named: "WorkspaceRemoteProjectMemoryUpdater.swift"
        )
        let plannerText = try Self.appSourceText(
            named: "WorkspaceMemoryCommandTranscriptPlanner.swift"
        )
        let errorText = try Self.appSourceText(
            named: "WorkspaceMemoryErrorMessageBuilder.swift"
        )
        let contextUpdateText = try Self.appSourceText(
            named: "WorkspaceMemoryContextUpdatePlanner.swift"
        )

        Self.assertSource(engineText, containsAll: [
            "enum WorkspaceMemoryEngine",
            "struct WorkspaceMemoryMutation",
            "WorkspaceRemoteProjectMemoryUpdater.update",
            "WorkspaceRemoteProjectMemoryDeleter.delete"
        ])
        Self.assertSource(contentPolicyText, contains: "enum MemoryNoteContentPolicy")
        Self.assertSource(pathResolverText, contains: "enum MemoryNotePathResolver")
        Self.assertSource(loaderText, containsAll: [
            "MemoryNoteContentPolicy.validatedWriteContent",
            "MemoryNotePathResolver.projectMemoryDirectory",
            "MemoryNotePathResolver.globalMemoryFileURL"
        ])
        Self.assertSource(loaderText, excludesAll: [
            "private static func looksSensitive",
            "private static func projectMemoryFileURL"
        ])
        Self.assertSource(workflowText, containsAll: [
            "enum WorkspaceMemoryWorkflow",
            "struct WorkspaceMemoryWorkflowContext"
        ])
        Self.assertSource(remoteUpdaterText, containsAll: [
            "enum WorkspaceRemoteProjectMemoryUpdater",
            "enum WorkspaceRemoteProjectMemoryDeleter",
            "MemoryNoteLoader.validatedUpdateContent"
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
        Self.assertSource(plannerText, contains: "struct WorkspaceMemoryCommandTranscriptPlanner")
        Self.assertSource(errorText, contains: "enum WorkspaceMemoryErrorMessageBuilder")
        Self.assertSource(contextUpdateText, contains: "struct WorkspaceMemoryContextUpdatePlanner")

        assertEngineDelegatesTranscriptCopy(engineText)
        assertWorkflowRoutesMemoryMutations(workflowText)
    }

    private func assertEngineDelegatesTranscriptCopy(_ engineText: String) {
        for delegatedCall in [
            "WorkspaceMemoryCommandTranscriptPlanner.memorySaved",
            "WorkspaceMemoryCommandTranscriptPlanner.memoryNotSaved",
            "WorkspaceMemoryCommandTranscriptPlanner.memorySavedSummary",
            "WorkspaceMemoryCommandTranscriptPlanner.memoryUpdated",
            "WorkspaceMemoryCommandTranscriptPlanner.memoryNotUpdated",
            "WorkspaceMemoryCommandTranscriptPlanner.memoryUpdatedSummary",
            "WorkspaceMemoryCommandTranscriptPlanner.memoryForgotten",
            "WorkspaceMemoryCommandTranscriptPlanner.memoryNotDeleted",
            "WorkspaceMemoryCommandTranscriptPlanner.memoryForgottenSummary",
            "WorkspaceMemoryErrorMessageBuilder.userFacingMessage",
            "WorkspaceMemoryContextUpdatePlanner.memoryChanged"
        ] {
            Self.assertSource(engineText, contains: delegatedCall)
        }
    }

    private func assertWorkflowRoutesMemoryMutations(_ workflowText: String) {
        for routedCall in [
            "WorkspaceMemoryEngine.updateGlobal",
            "WorkspaceMemoryEngine.updateProject",
            "WorkspaceMemoryEngine.updateRemoteProject",
            "WorkspaceMemoryEngine.deleteGlobal",
            "WorkspaceMemoryEngine.deleteProject",
            "WorkspaceMemoryEngine.deleteRemoteProject"
        ] {
            Self.assertSource(workflowText, contains: routedCall)
        }
    }
}
