import XCTest

final class ParityWorkspaceMemoryIntegrationGateTests: QuillCodeParityTestCase {
    func testWorkspaceMemoryIntegrationTestsOwnModelMemoryFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let broadSurfaceTests = try Self.appTestSourceText(named: "WorkspaceSurfaceTests.swift")
        let memoryIntegrationTests = try Self.appTestSourceText(named: "WorkspaceMemoryIntegrationTests.swift")

        let memoryFlowTests = [
            "testMemoryNotesLoadGlobalAndProjectIntoThreadAndSurface",
            "testSlashRememberWritesGlobalMemoryAndRefreshesThreadSurface",
            "testMemoryEditWorkspaceCommandPrefillsAndSlashUpdateRewritesGlobalMemory",
            "testMemoryEditWorkspaceCommandRewritesRemoteProjectMemoryThroughSSH",
            "testAgentRememberToolWritesGlobalMemoryAndRefreshesThreadSurface",
            "testMemoryDeleteWorkspaceCommandRemovesGlobalMemoryAndRefreshesThreadSurface",
            "testMemoryDeleteWorkspaceCommandRemovesProjectMemoryAndRefreshesThreadSurface",
            "testMemoryDeleteWorkspaceCommandRemovesRemoteProjectMemoryThroughSSH"
        ]

        Self.assertSource(memoryIntegrationTests, containsAll: memoryFlowTests + [
            "testSurfaceIncludesMemorySummariesAndCommand"
        ])
        Self.assertSource(modelTests, excludesAll: memoryFlowTests)
        Self.assertSource(broadSurfaceTests, excludes: "testSurfaceIncludesMemorySummariesAndCommand")
    }
}
