import XCTest

final class ParityWorkspaceThreadCreationGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesThreadCreationRecords() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let threadExtensionText = try Self.appSourceText(named: "WorkspaceModelThreads.swift")
        let threadSelectionText = try Self.appSourceText(named: "WorkspaceModelThreadSelection.swift")
        let creationText = try Self.appSourceText(named: "WorkspaceThreadCreationEngine.swift")

        [
            "extension QuillCodeWorkspaceModel",
            "WorkspaceThreadCreationEngine.newThread",
            "WorkspaceThreadCreationEngine.forkThread",
            "WorkspaceThreadCreationEngine.compactThread",
            "WorkspaceThreadCreationEngine.duplicateThread"
        ].forEach { Self.assertSource(threadExtensionText, contains: $0) }
        [
            "func insertCreatedThread",
            "ComposerDraftStore.select"
        ].forEach { Self.assertSource(threadSelectionText, contains: $0) }
        [
            "struct WorkspaceThreadCreationContext",
            "struct WorkspaceThreadCreationEngine",
            "static func newThread",
            "static func forkThread",
            "static func compactThread",
            "static func duplicateThread"
        ].forEach { Self.assertSource(creationText, contains: $0) }
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
