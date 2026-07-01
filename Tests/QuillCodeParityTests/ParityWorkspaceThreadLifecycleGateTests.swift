import XCTest

final class ParityWorkspaceThreadLifecycleGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesThreadLifecycleTransitions() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let threadExtensionText = try Self.appSourceText(named: "WorkspaceModelThreads.swift")
        let lifecycleActionsText = try Self.appSourceText(named: "WorkspaceModelThreadLifecycleActions.swift")
        let threadSelectionText = try Self.appSourceText(named: "WorkspaceModelThreadSelection.swift")
        let threadMutationText = try Self.appSourceText(named: "WorkspaceModelThreadMutation.swift")
        let lifecycleText = try Self.appSourceText(named: "WorkspaceThreadLifecycleEngine.swift")
        let persistenceText = try Self.appSourceText(named: "WorkspaceThreadPersistence.swift")

        [
            "struct WorkspaceThreadLifecycleEngine",
            "static func renameThread",
            "static func archiveThread",
            "static func unarchiveThread",
            "static func deleteThread",
            "static func applyAgentRunThreadUpdate"
        ].forEach { Self.assertSource(lifecycleText, contains: $0) }
        [
            "struct WorkspaceThreadPersistence",
            "func mutate(",
            "func saveOrThrow"
        ].forEach { Self.assertSource(persistenceText, contains: $0) }
        [
            "WorkspaceThreadLifecycleEngine.renameThread",
            "WorkspaceThreadLifecycleEngine.archiveThread",
            "WorkspaceThreadLifecycleEngine.deleteThread",
            "updateAndSaveThread"
        ].forEach { Self.assertSource(lifecycleActionsText, contains: $0) }
        [
            "func applyThreadDraftSelection",
            "func selectThread"
        ].forEach { Self.assertSource(threadSelectionText, contains: $0) }
        [
            "WorkspaceThreadLifecycleEngine.applyAgentRunThreadUpdate",
            "func mutateSelectedThread",
            "func mutateThread",
            "func selectedSidebarThreadIDs",
            "func validThreadIDs",
            "threadPersistence.mutate"
        ].forEach { Self.assertSource(threadMutationText, contains: $0) }
        Self.assertSource(modelText, contains: "WorkspaceThreadPersistence(store: threadStore)")
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
        [
            "WorkspaceThreadLifecycleEngine.renameThread",
            "func applyThreadDraftSelection"
        ].forEach { Self.assertSource(threadExtensionText, excludes: $0) }
    }
}
