import XCTest

final class ParityHTMLTopBarRendererGateTests: QuillCodeParityTestCase {
    func testWorkspaceHTMLRendererDelegatesTopBarRendering() throws {
        let htmlText = try Self.appSourceText(named: "WorkspaceHTMLRenderer.swift")
        let topBarText = try Self.appSourceText(named: "WorkspaceHTMLTopBarRenderer.swift")

        assertTopBarRendererContracts(topBarText)
        Self.assertSource(htmlText, contains: "WorkspaceHTMLTopBarRenderer.render")
        assertWorkspaceRendererAvoidsTopBarOwnership(htmlText)
    }

    private func assertTopBarRendererContracts(_ source: String) {
        [
            "enum WorkspaceHTMLTopBarRenderer",
            "static func render(_ topBar: TopBarSurface",
            "private static func renderStatusMetadata",
            "private static func renderActionCluster",
            "private static func renderActivityHairline",
            "private static func renderRuntimeIssuePill",
            "TopBarOverflowCommandCatalog.commands",
            "WorkspaceHTMLPrimitives.escape"
        ].forEach { Self.assertSource(source, contains: $0) }
        [
            "renderPrimaryCluster",
            "private static func renderStatusCluster",
            "topbar-status-menu",
            "top-bar-status-button"
        ].forEach { Self.assertSource(source, excludes: $0) }
    }

    private func assertWorkspaceRendererAvoidsTopBarOwnership(_ htmlText: String) {
        [
            "private static func renderTopBar",
            "private static func renderTopBarOverflow",
            "topbar-primary-cluster",
            "runtime-issue-pill",
            "top-bar-overflow-popover"
        ].forEach { Self.assertSource(htmlText, excludes: $0) }
    }
}
