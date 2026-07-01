import XCTest

final class ParityWorkspaceProjectIntegrationGateTests: QuillCodeParityTestCase {
    func testWorkspaceProjectExtensionIntegrationTestsOwnModelExtensionFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let broadSurfaceTests = try Self.appTestSourceText(named: "WorkspaceSurfaceTests.swift")
        let extensionIntegrationTests = try Self.appTestSourceText(
            named: "WorkspaceProjectExtensionIntegrationTests.swift"
        )

        [
            "testProjectExtensionManifestsLoadIntoProjectSurface",
            "testSurfaceIncludesProjectExtensionSummaryAndCommand",
            "testProjectExtensionInstallCommandRunsAndRefreshesProjectMetadata",
            "testProjectExtensionUpdateCommandRunsAndRefreshesProjectMetadata",
            "testProjectExtensionUpdateFailureKeepsManifestAndRecordsFailureNotice"
        ].forEach { Self.assertSource(extensionIntegrationTests, contains: $0) }
        [
            "testProjectExtensionManifestsLoadIntoProjectSurface",
            "testProjectExtensionInstallCommandRunsAndRefreshesProjectMetadata",
            "testProjectExtensionUpdateCommandRunsAndRefreshesProjectMetadata"
        ].forEach { Self.assertSource(modelTests, excludes: $0) }
        Self.assertSource(
            broadSurfaceTests,
            excludes: "testSurfaceIncludesProjectExtensionSummaryAndCommand"
        )
    }

    func testWorkspaceProjectIntegrationTestsOwnModelProjectFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let projectIntegrationTests = try Self.appTestSourceText(named: "WorkspaceProjectIntegrationTests.swift")

        [
            "testModelPersistsProjectRegistryChanges",
            "testSelectingProjectControlsNextChatAndWorkspaceRoot",
            "testProjectLifecycleActionsRenameRefreshNewChatAndRemove",
            "testProjectInstructionsLoadIntoNewThreadsAndRefreshBeforeRun"
        ].forEach {
            Self.assertSource(projectIntegrationTests, contains: $0)
            Self.assertSource(modelTests, excludes: $0)
        }
    }
}
