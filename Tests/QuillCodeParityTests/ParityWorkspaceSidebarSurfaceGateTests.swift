import XCTest

final class ParityWorkspaceSidebarSurfaceGateTests: QuillCodeParityTestCase {
    func testWorkspaceSurfaceDelegatesSidebarSurfaceContracts() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let projectListText = try Self.appSourceText(named: "QuillCodeProjectListSurface.swift")
        let sidebarText = try Self.appSourceText(named: "QuillCodeThreadSidebarSurface.swift")
        let sidebarItemText = try Self.appSourceText(named: "QuillCodeSidebarItemSurface.swift")
        let sidebarFilterText = try Self.appSourceText(named: "QuillCodeSidebarFilterSurface.swift")
        let threadListBuilderText = try Self.appSourceText(named: "QuillCodeSidebarThreadListBuilder.swift")
        let broadSurfaceTests = try Self.appTestSourceText(named: "WorkspaceSurfaceTests.swift")
        let sidebarSurfaceTests = try Self.appTestSourceText(named: "QuillCodeThreadSidebarSurfaceTests.swift")
        let sidebarIntegrationTests = try Self.appTestSourceText(named: "WorkspaceSidebarIntegrationTests.swift")

        assertProjectListContracts(projectListText, sidebarText, surfaceText)
        assertThreadSidebarContracts(sidebarText, sidebarItemText, sidebarFilterText, surfaceText)
        assertSidebarListBuilderContracts(sidebarText, projectListText, surfaceText, threadListBuilderText)
        assertFocusedSidebarTestOwnership(broadSurfaceTests, sidebarSurfaceTests, sidebarIntegrationTests)
    }

    func testWorkspaceSurfaceDelegatesNavigationSurfaceBuilding() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceNavigationSurfaceBuilder.swift")

        Self.assertSource(surfaceText, contains: "WorkspaceNavigationSurfaceBuilder(")
        Self.assertSource(builderText, contains: "struct WorkspaceNavigationSurfaceBuilder")
        Self.assertSource(builderText, contains: "ProjectListSurface(")
        Self.assertSource(builderText, contains: "SidebarSurface(")
        Self.assertSource(builderText, contains: "SidebarBulkActionSurface")
        Self.assertSource(builderText, contains: "activeSidebarFilter")
        Self.assertSource(builderText, contains: "visibleSidebarItems")
        Self.assertSource(builderText, contains: "selectedThreadIDs.intersection")
        Self.assertSource(surfaceText, excludes: "private func sidebarBulkActions")
        Self.assertSource(surfaceText, excludes: "private func projectItems")
        Self.assertSource(surfaceText, excludes: "ProjectListSurface(")
        Self.assertSource(surfaceText, excludes: "SidebarSurface(")
    }

    private func assertProjectListContracts(
        _ projectListText: String,
        _ sidebarText: String,
        _ surfaceText: String
    ) {
        Self.assertSource(projectListText, contains: "public struct ProjectListSurface")
        Self.assertSource(projectListText, contains: "public struct ProjectItemSurface")
        Self.assertSource(projectListText, contains: "public enum ProjectItemActionKind")
        Self.assertSource(projectListText, contains: "public struct ProjectItemActionSurface")
        Self.assertSource(sidebarText, excludes: "public struct ProjectListSurface")
        Self.assertSource(sidebarText, excludes: "public struct ProjectItemSurface")
        Self.assertSource(sidebarText, excludes: "ProjectItemActionSurface")
        Self.assertSource(surfaceText, excludes: "public struct ProjectListSurface")
        Self.assertSource(surfaceText, excludes: "public struct ProjectItemSurface")
        Self.assertSource(surfaceText, excludes: "public enum ProjectItemActionKind")
        Self.assertSource(surfaceText, excludes: "public struct ProjectItemActionSurface")
    }

    private func assertThreadSidebarContracts(
        _ sidebarText: String,
        _ sidebarItemText: String,
        _ sidebarFilterText: String,
        _ surfaceText: String
    ) {
        Self.assertSource(sidebarText, contains: "public struct SidebarSurface")
        Self.assertSource(sidebarItemText, contains: "public struct SidebarItemSurface")
        Self.assertSource(sidebarItemText, contains: "public enum SidebarBulkActionKind")
        Self.assertSource(sidebarItemText, contains: "public struct SidebarBulkActionSurface")
        Self.assertSource(sidebarItemText, contains: "public enum SidebarItemActionKind")
        Self.assertSource(sidebarItemText, contains: "public struct SidebarItemActionSurface")
        Self.assertSource(sidebarFilterText, contains: "public enum SidebarSavedFilterKind")
        Self.assertSource(sidebarFilterText, contains: "public struct SidebarSavedSearchSurface")
        Self.assertSource(sidebarItemText, excludes: "public struct SidebarSurface")
        Self.assertSource(sidebarFilterText, excludes: "public struct SidebarSurface")
        Self.assertSource(surfaceText, excludes: "public struct SidebarSurface")
        Self.assertSource(surfaceText, excludes: "public struct SidebarItemSurface")
        Self.assertSource(surfaceText, excludes: "public enum SidebarBulkActionKind")
        Self.assertSource(surfaceText, excludes: "public struct SidebarBulkActionSurface")
        Self.assertSource(surfaceText, excludes: "public enum SidebarItemActionKind")
        Self.assertSource(surfaceText, excludes: "public struct SidebarItemActionSurface")
    }

    private func assertSidebarListBuilderContracts(
        _ sidebarText: String,
        _ projectListText: String,
        _ surfaceText: String,
        _ threadListBuilderText: String
    ) {
        Self.assertSource(sidebarText, contains: "filteredItems")
        Self.assertSource(sidebarText, contains: "selectionLabel")
        Self.assertSource(sidebarText, contains: "SidebarThreadListBuilder(items: items)")
        Self.assertSource(threadListBuilderText, contains: "struct SidebarThreadListBuilder")
        Self.assertSource(threadListBuilderText, contains: "private enum SidebarThreadDateBucket")
        Self.assertSource(projectListText, excludes: "SidebarThreadListBuilder")
        Self.assertSource(projectListText, excludes: "public struct SidebarSurface")
        Self.assertSource(projectListText, excludes: "public struct SidebarItemSurface")
        Self.assertSource(sidebarText, excludes: "private enum SidebarThreadDateBucket")
        Self.assertSource(surfaceText, excludes: "selectionLabel(count:")
    }

    private func assertFocusedSidebarTestOwnership(
        _ broadSurfaceTests: String,
        _ sidebarSurfaceTests: String,
        _ sidebarIntegrationTests: String
    ) {
        Self.assertSource(sidebarSurfaceTests, contains: "testSidebarSearchExcludesHiddenInternalContext")
        Self.assertSource(sidebarSurfaceTests, contains: "workspace manager")
        Self.assertSource(sidebarIntegrationTests, contains: "testBulkSelectionArchivesAndDeletesChats")
        Self.assertSource(broadSurfaceTests, excludes: "testSidebarSearchExcludesHiddenInternalContext")
        Self.assertSource(
            broadSurfaceTests,
            excludes: "testSidebarSearchFiltersByThreadTitleSubtitleAndTranscriptContent"
        )
        Self.assertSource(broadSurfaceTests, excludes: "testSidebarBulkSelectionArchivesAndDeletesChats")
    }
}
