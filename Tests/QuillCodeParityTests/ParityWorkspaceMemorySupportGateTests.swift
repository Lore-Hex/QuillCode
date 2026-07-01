import XCTest

final class ParityWorkspaceMemorySupportGateTests: QuillCodeParityTestCase {
    func testWorkspaceMemorySupportOwnsStoragePolicyAndCopyBoundaries() throws {
        let engineText = try Self.appSourceText(named: "WorkspaceMemoryEngine.swift")
        let mutationFactoryText = try Self.appSourceText(named: "WorkspaceMemoryMutationFactory.swift")
        let loaderText = try Self.appSourceText(named: "MemoryNoteLoader.swift")
        let contentPolicyText = try Self.appSourceText(named: "MemoryNoteContentPolicy.swift")
        let pathResolverText = try Self.appSourceText(named: "MemoryNotePathResolver.swift")
        let remoteUpdaterText = try Self.appSourceText(named: "WorkspaceRemoteProjectMemoryUpdater.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceMemoryCommandTranscriptPlanner.swift")
        let errorText = try Self.appSourceText(named: "WorkspaceMemoryErrorMessageBuilder.swift")
        let contextUpdateText = try Self.appSourceText(named: "WorkspaceMemoryContextUpdatePlanner.swift")

        Self.assertSource(engineText, containsAll: [
            "enum WorkspaceMemoryEngine",
            "struct WorkspaceMemoryMutation",
            "WorkspaceRemoteProjectMemoryUpdater.update",
            "WorkspaceRemoteProjectMemoryDeleter.delete"
        ])
        Self.assertSource(mutationFactoryText, contains: "enum WorkspaceMemoryMutationFactory")
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
        Self.assertSource(remoteUpdaterText, containsAll: [
            "enum WorkspaceRemoteProjectMemoryUpdater",
            "enum WorkspaceRemoteProjectMemoryDeleter",
            "MemoryNoteLoader.validatedUpdateContent"
        ])
        Self.assertSource(plannerText, contains: "struct WorkspaceMemoryCommandTranscriptPlanner")
        Self.assertSource(errorText, contains: "enum WorkspaceMemoryErrorMessageBuilder")
        Self.assertSource(contextUpdateText, contains: "struct WorkspaceMemoryContextUpdatePlanner")
        Self.assertSource(mutationFactoryText, containsAll: [
            "WorkspaceMemoryCommandTranscriptPlanner.memorySaved",
            "WorkspaceMemoryCommandTranscriptPlanner.memoryNotSaved",
            "WorkspaceMemoryCommandTranscriptPlanner.memorySavedSummary",
            "WorkspaceMemoryCommandTranscriptPlanner.memoryUpdated",
            "WorkspaceMemoryCommandTranscriptPlanner.memoryNotUpdated",
            "WorkspaceMemoryCommandTranscriptPlanner.memoryUpdatedSummary",
            "WorkspaceMemoryCommandTranscriptPlanner.memoryForgotten",
            "WorkspaceMemoryCommandTranscriptPlanner.memoryNotDeleted",
            "WorkspaceMemoryCommandTranscriptPlanner.memoryForgottenSummary",
            "WorkspaceMemoryErrorMessageBuilder.userFacingMessage"
        ])
        Self.assertSource(engineText, contains: "WorkspaceMemoryContextUpdatePlanner.memoryChanged")
    }
}
