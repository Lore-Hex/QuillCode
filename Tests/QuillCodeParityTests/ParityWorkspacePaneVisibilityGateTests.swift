import XCTest

final class ParityWorkspacePaneVisibilityGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesPaneVisibilityMutations() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let paneVisibilityText = try Self.appSourceText(
            named: "WorkspaceModelPaneVisibility.swift"
        )
        let toggleAPIs = [
            "public func toggleExtensions",
            "public func toggleMemories",
            "public func toggleActivity",
            "public func toggleAutomations",
            "public func toggleActivitySection"
        ]

        Self.assertSource(paneVisibilityText, contains: "extension QuillCodeWorkspaceModel")
        Self.assertSource(paneVisibilityText, containsAll: toggleAPIs)
        Self.assertSource(modelText, excludesAll: toggleAPIs + [
            "activity.collapsedSectionIDs"
        ])
    }
}
