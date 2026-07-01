import XCTest

final class ParityHTMLTerminalRendererGateTests: QuillCodeParityTestCase {
    func testWorkspaceHTMLRendererDelegatesTerminalRendering() throws {
        let htmlText = try Self.appSourceText(named: "WorkspaceHTMLRenderer.swift")
        let terminalText = try Self.appSourceText(named: "WorkspaceHTMLTerminalRenderer.swift")

        [
            "enum WorkspaceHTMLTerminalRenderer",
            "static func render(_ terminal: TerminalSurface",
            "private static func renderEntry",
            "private static func statusClass",
            "WorkspaceHTMLPrimitives.executionContextChip"
        ].forEach { Self.assertSource(terminalText, contains: $0) }
        Self.assertSource(htmlText, contains: "WorkspaceHTMLTerminalRenderer.render")
        [
            "private static func renderTerminal",
            "private static func terminalStatusClass"
        ].forEach { Self.assertSource(htmlText, excludes: $0) }
    }
}
