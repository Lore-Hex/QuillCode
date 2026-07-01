import XCTest

final class ParityWorkspaceThreadLifecycleGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesThreadLifecycleTransitions() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let threadText = try Self.appSourceText(named: "WorkspaceModelThreads.swift")
        let lifecycleActionsText = try Self.appSourceText(named: "WorkspaceModelThreadLifecycleActions.swift")
        let selectionText = try Self.appSourceText(named: "WorkspaceModelThreadSelection.swift")
        let mutationText = try Self.appSourceText(named: "WorkspaceModelThreadMutation.swift")
        let lifecycleText = try Self.appSourceText(named: "WorkspaceThreadLifecycleEngine.swift")
        let persistenceText = try Self.appSourceText(named: "WorkspaceThreadPersistence.swift")

        assertLifecycleEngineContracts(lifecycleText)
        assertPersistenceContracts(persistenceText)
        assertLifecycleActionsDelegate(lifecycleActionsText)
        assertSelectionAndMutationDelegates(selectionText, mutationText)
        Self.assertSource(
            modelText,
            contains: "WorkspaceThreadPersistence(store: threadStore)"
        )
        assertWorkspaceModelAvoidsLifecycleOwnership(modelText)
        assertThreadCreationAPIsAvoidLifecycleOwnership(threadText)
    }

    private func assertLifecycleEngineContracts(_ source: String) {
        [
            "struct WorkspaceThreadLifecycleEngine",
            "static func renameThread",
            "static func archiveThread",
            "static func unarchiveThread",
            "static func deleteThread",
            "static func applyAgentRunThreadUpdate"
        ].forEach { Self.assertSource(source, contains: $0) }
    }

    private func assertPersistenceContracts(_ source: String) {
        [
            "struct WorkspaceThreadPersistence",
            "func mutate(",
            "func saveOrThrow"
        ].forEach { Self.assertSource(source, contains: $0) }
    }

    private func assertLifecycleActionsDelegate(_ source: String) {
        [
            "WorkspaceThreadLifecycleEngine.renameThread",
            "WorkspaceThreadLifecycleEngine.archiveThread",
            "WorkspaceThreadLifecycleEngine.deleteThread",
            "updateAndSaveThread"
        ].forEach { Self.assertSource(source, contains: $0) }
    }

    private func assertSelectionAndMutationDelegates(
        _ selectionText: String,
        _ mutationText: String
    ) {
        [
            "func applyThreadDraftSelection",
            "func selectThread"
        ].forEach { Self.assertSource(selectionText, contains: $0) }
        [
            "WorkspaceThreadLifecycleEngine.applyAgentRunThreadUpdate",
            "func mutateSelectedThread",
            "func mutateThread",
            "func selectedSidebarThreadIDs",
            "func validThreadIDs",
            "threadPersistence.mutate"
        ].forEach { Self.assertSource(mutationText, contains: $0) }
    }

    private func assertWorkspaceModelAvoidsLifecycleOwnership(_ modelText: String) {
        [
            "WorkspaceThreadLifecycleEngine.applyAgentRunThreadUpdate",
            "func mutateSelectedThread",
            "func mutateThread",
            "func selectedSidebarThreadIDs",
            "func validThreadIDs",
            "threadPersistence.mutate",
            "public func renameThread",
            "public func archiveThread",
            "public func unarchiveThread",
            "public func deleteThread",
            "thread.title = trimmed",
            "thread.isArchived = true",
            "thread.isArchived = false",
            "private func upsertThread",
            "private func selectUpdatedThread",
            "threadStore?.save",
            "threadStore?.delete"
        ].forEach { Self.assertSource(modelText, excludes: $0) }
    }

    private func assertThreadCreationAPIsAvoidLifecycleOwnership(_ threadText: String) {
        [
            "WorkspaceThreadLifecycleEngine.renameThread",
            "func applyThreadDraftSelection"
        ].forEach { Self.assertSource(threadText, excludes: $0) }
    }
}
