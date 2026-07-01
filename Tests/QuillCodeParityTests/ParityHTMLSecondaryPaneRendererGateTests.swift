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

        assertSecondaryFacadeContracts(secondaryText)
        assertFocusedPaneRendererContracts(
            extensions: extensionsText,
            memories: memoriesText,
            activity: activityText,
            automations: automationsText
        )
        assertSecondaryPrimitiveContracts(primitivesText)
        assertWorkspaceRendererDelegatesPanes(htmlText)
        assertSecondaryFacadeAvoidsPaneDetails(secondaryText)
        assertWorkspaceRendererAvoidsPaneOwnership(htmlText)
    }

    private func assertSecondaryFacadeContracts(_ source: String) {
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
        ].forEach { Self.assertSource(source, contains: $0) }
    }

    private func assertFocusedPaneRendererContracts(
        extensions: String,
        memories: String,
        activity: String,
        automations: String
    ) {
        Self.assertSource(extensions, contains: "enum WorkspaceHTMLExtensionsPaneRenderer")
        Self.assertSource(extensions, contains: "private static func renderMCPTools")
        Self.assertSource(memories, contains: "enum WorkspaceHTMLMemoriesPaneRenderer")
        Self.assertSource(activity, contains: "enum WorkspaceHTMLActivityPaneRenderer")
        Self.assertSource(automations, contains: "enum WorkspaceHTMLAutomationsPaneRenderer")
        Self.assertSource(automations, contains: "private static func renderAutomationActions")
    }

    private func assertSecondaryPrimitiveContracts(_ source: String) {
        [
            "WorkspaceHTMLPrimitives.escape",
            "static func countLabel"
        ].forEach { Self.assertSource(source, contains: $0) }
    }

    private func assertWorkspaceRendererDelegatesPanes(_ htmlText: String) {
        [
            "WorkspaceHTMLSecondaryPaneRenderer.renderExtensions",
            "WorkspaceHTMLSecondaryPaneRenderer.renderMemories",
            "WorkspaceHTMLSecondaryPaneRenderer.renderActivity",
            "WorkspaceHTMLSecondaryPaneRenderer.renderAutomations"
        ].forEach { Self.assertSource(htmlText, contains: $0) }
    }

    private func assertSecondaryFacadeAvoidsPaneDetails(_ secondaryText: String) {
        [
            "private static func renderMCPTools",
            "private static func renderAutomationActions",
            "private static func countLabel"
        ].forEach { Self.assertSource(secondaryText, excludes: $0) }
    }

    private func assertWorkspaceRendererAvoidsPaneOwnership(_ htmlText: String) {
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
