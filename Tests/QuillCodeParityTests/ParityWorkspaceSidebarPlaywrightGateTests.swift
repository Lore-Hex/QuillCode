import XCTest

final class ParityWorkspaceSidebarPlaywrightGateTests: QuillCodeParityTestCase {
    func testPlaywrightSidebarAndProjectFlowsStayInFocusedSpec() throws {
        let testRoot = Self.packageRoot().appendingPathComponent("E2E/playwright/tests")
        let sidebarSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("sidebar.spec.ts"),
            encoding: .utf8
        )
        let coreSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("core.spec.ts"),
            encoding: .utf8
        )

        Self.assertSource(sidebarSpecText, contains: "harnessURL()")
        Self.assertSource(sidebarSpecText, contains: "clickSidebarTool")
        Self.assertSource(sidebarSpecText, contains: "clickProjectAction")
        Self.assertSource(sidebarSpecText, contains: "ssh://quill@feather.local/srv/quill")
        Self.assertSource(coreSpecText, excludes: "clickProjectAction")
        Self.assertSource(coreSpecText, excludes: "replaceFocusedText")

        for flowName in sidebarFlowNames {
            Self.assertSource(sidebarSpecText, contains: flowName)
            Self.assertSource(coreSpecText, excludes: flowName)
        }
    }

    private var sidebarFlowNames: [String] {
        [
            "searches and reopens an existing chat",
            "starts a new chat from the sidebar action",
            "manages chat lifecycle from the sidebar",
            "groups sidebar chats by recency bucket",
            "bulk-selects chats from the sidebar",
            "filters sidebar chats with saved filters",
            "manages projects from the sidebar",
            "adds an SSH remote project from command palette and slash command"
        ]
    }
}
