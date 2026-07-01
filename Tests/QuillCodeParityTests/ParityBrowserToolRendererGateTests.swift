import XCTest

final class ParityBrowserToolRendererGateTests: QuillCodeParityTestCase {
    func testBrowserAgentToolsShareFocusedExecutor() throws {
        let definitionsText = try Self.coreSourceText(named: "CoreToolDefinitions.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceAgentRunContextBuilder.swift")
        let executorText = try Self.appSourceText(named: "WorkspaceToolCallExecutor.swift")
        let browserToolText = try Self.appSourceText(named: "WorkspaceBrowserToolExecutor.swift")
        let normalizerText = try Self.agentSourceText(named: "AgentToolArgumentNormalizer.swift")
        let finalAnswerText = try Self.agentSourceText(named: "AgentBrowserToolAnswerFormatters.swift")

        Self.assertSource(definitionsText, contains: "static let browserOpen")
        Self.assertSource(builderText, contains: "ToolDefinition.browserOpen")
        Self.assertSource(executorText, contains: "WorkspaceBrowserToolExecutor.execute")
        Self.assertSource(browserToolText, contains: "ToolDefinition.browserInspect.name")
        Self.assertSource(browserToolText, contains: "ToolDefinition.browserOpen.name")
        Self.assertSource(browserToolText, contains: "WorkspaceBrowserWorkflow.openPreview")
        Self.assertSource(browserToolText, contains: "ToolArguments(")
        Self.assertSource(browserToolText, excludes: "JSONSerialization")
        Self.assertSource(normalizerText, contains: "ToolDefinition.browserOpen.name")
        Self.assertSource(finalAnswerText, contains: "browserOpenAnswer")
    }

    func testWorkspaceHTMLRendererDelegatesBrowserRendering() throws {
        let htmlText = try Self.appSourceText(named: "WorkspaceHTMLRenderer.swift")
        let browserText = try Self.appSourceText(named: "WorkspaceHTMLBrowserRenderer.swift")

        for expected in [
            "enum WorkspaceHTMLBrowserRenderer",
            "static func render(_ browser: BrowserSurface",
            "private static func renderPreview",
            "private static func renderSnapshot",
            "private static func renderComment",
            "WorkspaceHTMLPrimitives.escape"
        ] {
            Self.assertSource(browserText, contains: expected)
        }
        Self.assertSource(htmlText, contains: "WorkspaceHTMLBrowserRenderer.render")
        Self.assertSource(htmlText, excludes: "private static func renderBrowser")
        Self.assertSource(htmlText, excludes: "browser-snapshot-outline")
        Self.assertSource(htmlText, excludes: "browser-comment")
    }

    func testPlaywrightBrowserFlowsStayInFocusedSpec() throws {
        let root = Self.packageRoot().appendingPathComponent("E2E/playwright/tests")
        let browserSpecText = try String(contentsOf: root.appendingPathComponent("browser.spec.ts"), encoding: .utf8)
        let coreSpecText = try String(contentsOf: root.appendingPathComponent("core.spec.ts"), encoding: .utf8)
        let helperText = try String(contentsOf: root.appendingPathComponent("harness-helpers.ts"), encoding: .utf8)

        for expected in [
            "opens browser preview and records comments",
            "opens browser preview from chat",
            "harnessURL()"
        ] {
            Self.assertSource(browserSpecText, contains: expected)
        }
        Self.assertSource(helperText, contains: "export function harnessURL")
        Self.assertSource(helperText, contains: "export async function clickSidebarTool")
        Self.assertSource(coreSpecText, excludes: "opens browser preview and records comments")
        Self.assertSource(coreSpecText, excludes: "opens browser preview from chat")
    }
}
