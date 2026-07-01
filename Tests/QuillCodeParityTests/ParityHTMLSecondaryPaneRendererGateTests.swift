import XCTest

final class ParityHTMLSecondaryPaneRendererGateTests: QuillCodeParityTestCase {
    func testWorkspaceHTMLRendererDelegatesSecondaryPaneRendering() throws {
        let htmlText = try Self.appSourceText(named: "WorkspaceHTMLRenderer.swift")
        let secondaryText = try Self.appSourceText(named: "WorkspaceHTMLSecondaryPaneRenderer.swift")
        let extensionsText = try Self.appSourceText(named: "WorkspaceHTMLExtensionsPaneRenderer.swift")
        let memoriesText = try Self.appSourceText(named: "WorkspaceHTMLMemoriesPaneRenderer.swift")
        let activityText = try Self.appSourceText(named: "WorkspaceHTMLActivityPaneRenderer.swift")
        let automationsText = try Self.appSourceText(named: "WorkspaceHTMLAutomationsPaneRenderer.swift")
        let primitivesText = try Self.appSourceText(named: "WorkspaceHTMLSecondaryPanePrimitives.swift")

        [
            "enum WorkspaceHTMLSecondaryPaneRenderer",
            "static func renderExtensions",
            "static func renderMemories",
            "static func renderActivity",
            "static func renderAutomations",
            "WorkspaceHTMLExtensionsPaneRenderer.render",
            "WorkspaceHTMLMemoriesPaneRenderer.render",
            "WorkspaceHTMLActivityPaneRenderer.render",
            "WorkspaceHTMLAutomationsPaneRenderer.render"
        ].forEach { Self.assertSource(secondaryText, contains: $0) }
        [
            "enum WorkspaceHTMLExtensionsPaneRenderer",
            "private static func renderMCPTools"
        ].forEach { Self.assertSource(extensionsText, contains: $0) }
        Self.assertSource(memoriesText, contains: "enum WorkspaceHTMLMemoriesPaneRenderer")
        Self.assertSource(activityText, contains: "enum WorkspaceHTMLActivityPaneRenderer")
        [
            "enum WorkspaceHTMLAutomationsPaneRenderer",
            "private static func renderAutomationActions"
        ].forEach { Self.assertSource(automationsText, contains: $0) }
        [
            "WorkspaceHTMLPrimitives.escape",
            "static func countLabel"
        ].forEach { Self.assertSource(primitivesText, contains: $0) }
        [
            "WorkspaceHTMLSecondaryPaneRenderer.renderExtensions",
            "WorkspaceHTMLSecondaryPaneRenderer.renderMemories",
            "WorkspaceHTMLSecondaryPaneRenderer.renderActivity",
            "WorkspaceHTMLSecondaryPaneRenderer.renderAutomations"
        ].forEach { Self.assertSource(htmlText, contains: $0) }
        [
            "private static func renderMCPTools",
            "private static func renderAutomationActions",
            "private static func countLabel"
        ].forEach { Self.assertSource(secondaryText, excludes: $0) }
        [
            "private static func renderExtensions",
            "private static func renderMemories",
            "private static func renderActivity",
            "private static func renderAutomations",
            "private static func countLabel",
            "extension-mcp-tool-schema"
        ].forEach { Self.assertSource(htmlText, excludes: $0) }
    }
}
