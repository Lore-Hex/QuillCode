import XCTest

final class ParityHTMLSidebarRendererGateTests: QuillCodeParityTestCase {
    func testWorkspaceHTMLRendererDelegatesSidebarRendering() throws {
        let htmlText = try Self.appSourceText(named: "WorkspaceHTMLRenderer.swift")
        let sidebarText = try Self.appSourceText(named: "WorkspaceHTMLSidebarRenderer.swift")
        let commandText = try Self.appSourceText(named: "WorkspaceHTMLSidebarCommandRenderer.swift")
        let projectText = try Self.appSourceText(named: "WorkspaceHTMLSidebarProjectRenderer.swift")
        let savedSearchText = try Self.appSourceText(named: "WorkspaceHTMLSidebarSavedSearchRenderer.swift")
        let threadText = try Self.appSourceText(named: "WorkspaceHTMLSidebarThreadRenderer.swift")

        assertSidebarFacadeContracts(sidebarText)
        assertProjectSidebarContracts(projectText)
        assertThreadSidebarContracts(threadText)
        assertSavedSearchSidebarContracts(savedSearchText)
        assertCommandSidebarContracts(commandText)
        Self.assertSource(htmlText, contains: "WorkspaceHTMLSidebarRenderer.render")
        assertSidebarFacadeAvoidsFeatureDetails(sidebarText)
        assertWorkspaceRendererAvoidsSidebarOwnership(htmlText)
    }

    private func assertSidebarFacadeContracts(_ source: String) {
        [
            "enum WorkspaceHTMLSidebarRenderer",
            "static func render(",
            "WorkspaceHTMLSidebarCommandRenderer.renderPrimaryActions",
            "WorkspaceHTMLSidebarThreadRenderer.render",
            "WorkspaceHTMLSidebarProjectRenderer.render",
            "WorkspaceHTMLSidebarCommandRenderer.renderFooter"
        ].forEach { Self.assertSource(source, contains: $0) }
    }

    private func assertProjectSidebarContracts(_ source: String) {
        [
            "enum WorkspaceHTMLSidebarProjectRenderer",
            "private static func renderProjects",
            "project-empty",
            "WorkspaceHTMLPrimitives.escape"
        ].forEach { Self.assertSource(source, contains: $0) }
    }

    private func assertThreadSidebarContracts(_ source: String) {
        [
            "enum WorkspaceHTMLSidebarThreadRenderer",
            "private static func renderThreadSections",
            "private static func renderBulkToolbar",
            "private static func renderSelectionHeaderAction",
            "sidebar-empty",
            "WorkspaceHTMLPrimitives.escape",
            "renderWorktreeChip",
            "sidebar-worktree-branch",
            "sidebar-worktree-warning",
            "renderRunStatus",
            "sidebar-run-status",
            "data-run-status"
        ].forEach { Self.assertSource(source, contains: $0) }
    }

    func testWorktreeChipTestidsMatchBetweenHTMLRendererAndHarness() throws {
        // The native thread renderer and the mock harness must render the same worktree-chip testids,
        // so a change to one surface that isn't mirrored in the other fails here.
        let threadText = try Self.appSourceText(named: "WorkspaceHTMLSidebarThreadRenderer.swift")
        let harness = try harnessText()
        for token in ["sidebar-worktree-branch", "sidebar-worktree-warning", "sidebar-run-status", "data-run-status"] {
            Self.assertSource(threadText, contains: token)
            Self.assertSource(harness, contains: token)
        }
    }

    private func harnessText() throws -> String {
        try String(
            contentsOf: Self.packageRoot().appendingPathComponent("E2E/harness/index.html"),
            encoding: .utf8
        )
    }

    private func assertSavedSearchSidebarContracts(_ source: String) {
        [
            "enum WorkspaceHTMLSidebarSavedSearchRenderer",
            "sidebar-saved-search-row",
            "sidebar-saved-search-create",
            "private static func renderMoveButton"
        ].forEach { Self.assertSource(source, contains: $0) }
    }

    private func assertCommandSidebarContracts(_ source: String) {
        [
            "enum WorkspaceHTMLSidebarCommandRenderer",
            "static func renderFooter",
            "private static func renderUtilityAction",
            "sidebar-tools-popover",
            "WorkspaceHTMLPrimitives.escape"
        ].forEach { Self.assertSource(source, contains: $0) }
    }

    private func assertSidebarFacadeAvoidsFeatureDetails(_ sidebarText: String) {
        [
            "private static func renderProjects",
            "private static func renderThreadSections",
            "private static func renderBulkToolbar",
            "private static func renderFooter",
            "private static func renderUtilityAction",
            "sidebar-tools-popover",
            "project-empty"
        ].forEach { Self.assertSource(sidebarText, excludes: $0) }
    }

    private func assertWorkspaceRendererAvoidsSidebarOwnership(_ htmlText: String) {
        [
            "private static func renderSidebar",
            "private static func renderSidebarPrimaryActions",
            "private static func renderSidebarSection",
            "private static func renderSidebarBulkToolbar",
            "sidebar-tools-popover",
            "project-empty"
        ].forEach { Self.assertSource(htmlText, excludes: $0) }
    }
}
