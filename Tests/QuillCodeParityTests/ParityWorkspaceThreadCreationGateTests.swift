import XCTest

final class ParityWorkspaceThreadCreationGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesThreadCreationRecords() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let threadText = try Self.appSourceText(named: "WorkspaceModelThreads.swift")
        let selectionText = try Self.appSourceText(named: "WorkspaceModelThreadSelection.swift")
        let creationText = try Self.appSourceText(named: "WorkspaceThreadCreationEngine.swift")

        Self.assertSource(threadText, contains: "extension QuillCodeWorkspaceModel")
        assertSelectionOwnsDraftSwitching(selectionText)
        assertCreationEngineContracts(creationText)
        assertThreadAPIsDelegateCreation(threadText)
        assertWorkspaceModelAvoidsThreadCreation(modelText)
    }

    private func assertSelectionOwnsDraftSwitching(_ source: String) {
        [
            "func insertCreatedThread",
            "ComposerDraftStore.select"
        ].forEach { Self.assertSource(source, contains: $0) }
    }

    private func assertCreationEngineContracts(_ source: String) {
        [
            "struct WorkspaceThreadCreationContext",
            "struct WorkspaceThreadCreationEngine",
            "static func newThread",
            "static func forkThread",
            "static func compactThread",
            "static func duplicateThread"
        ].forEach { Self.assertSource(source, contains: $0) }
    }

    private func assertThreadAPIsDelegateCreation(_ threadText: String) {
        [
            "WorkspaceThreadCreationEngine.newThread",
            "WorkspaceThreadCreationEngine.forkThread",
            "WorkspaceThreadCreationEngine.compactThread",
            "WorkspaceThreadCreationEngine.duplicateThread"
        ].forEach { Self.assertSource(threadText, contains: $0) }
    }

    private func assertWorkspaceModelAvoidsThreadCreation(_ modelText: String) {
        [
            "public func newChat",
            "public func forkFromLast",
            "public func compactContext",
            "public func duplicateThread",
            "title: \"Fork:",
            "title: \"Compact:",
            "title: \"Copy:"
        ].forEach { Self.assertSource(modelText, excludes: $0) }
    }
}
