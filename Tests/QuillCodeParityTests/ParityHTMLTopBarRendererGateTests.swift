import XCTest

final class ParityHTMLTopBarRendererGateTests: QuillCodeParityTestCase {
    func testWorkspaceHTMLRendererDelegatesTopBarRendering() throws {
        let htmlText = try Self.appSourceText(named: "WorkspaceHTMLRenderer.swift")
        let topBarText = try Self.appSourceText(named: "WorkspaceHTMLTopBarRenderer.swift")

        [
            "enum WorkspaceHTMLTopBarRenderer",
            "static func render(_ topBar: TopBarSurface",
            "private static func renderStatusMetadata",
            "private static func renderActionCluster",
            "private static func renderActivityHairline",
            "private static func renderRuntimeIssuePill",
            "TopBarOverflowCommandCatalog.commands",
            "WorkspaceHTMLPrimitives.escape"
        ].forEach { Self.assertSource(topBarText, contains: $0) }
        [
            "renderPrimaryCluster",
            "private static func renderStatusCluster",
            "topbar-status-menu",
            "top-bar-status-button"
        ].forEach { Self.assertSource(topBarText, excludes: $0) }
        Self.assertSource(htmlText, contains: "WorkspaceHTMLTopBarRenderer.render")
        [
            "private static func renderTopBar",
            "private static func renderTopBarOverflow",
            "topbar-primary-cluster",
            "runtime-issue-pill",
            "top-bar-overflow-popover"
        ].forEach { Self.assertSource(htmlText, excludes: $0) }
    }
}
