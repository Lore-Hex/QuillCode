import XCTest

final class ParityWorkspaceMemoryIntegrationGateTests: QuillCodeParityTestCase {
    func testWorkspaceMemoryIntegrationTestsOwnModelMemoryFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let surfaceTests = try Self.appTestSourceText(named: "WorkspaceSurfaceTests.swift")
        let memoryTests = try Self.appTestSourceText(
            named: "WorkspaceMemoryIntegrationTests.swift"
        )

        let focusedMemoryTests = [
            "testMemoryNotesLoadGlobalAndProjectIntoThreadAndSurface",
            "testSurfaceIncludesMemorySummariesAndCommand",
            "testSlashRememberWritesGlobalMemoryAndRefreshesThreadSurface",
            "testMemoryEditWorkspaceCommandPrefillsAndSlashUpdateRewritesGlobalMemory",
            "testMemoryEditWorkspaceCommandRewritesRemoteProjectMemoryThroughSSH",
            "testAgentRememberToolWritesGlobalMemoryAndRefreshesThreadSurface",
            "testMemoryDeleteWorkspaceCommandRemovesGlobalMemoryAndRefreshesThreadSurface",
            "testMemoryDeleteWorkspaceCommandRemovesProjectMemoryAndRefreshesThreadSurface",
            "testMemoryDeleteWorkspaceCommandRemovesRemoteProjectMemoryThroughSSH"
        ]

        Self.assertSource(memoryTests, containsAll: focusedMemoryTests)
        Self.assertSource(modelTests, excludesAll: focusedMemoryTests.filter {
            $0 != "testSurfaceIncludesMemorySummariesAndCommand"
        })
        Self.assertSource(
            surfaceTests,
            excludes: "testSurfaceIncludesMemorySummariesAndCommand"
        )
    }
}
