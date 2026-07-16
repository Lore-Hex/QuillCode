import XCTest

final class ParityWorkspaceSidebarPlaywrightGateTests: QuillCodeParityTestCase {
    func testPlaywrightSidebarAndProjectFlowsStayInFocusedSpec() throws {
        let testRoot = Self.packageRoot().appendingPathComponent("E2E/playwright/tests")
        let sidebarSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("sidebar.spec.ts"),
            encoding: .utf8
        )
        let chatLifecycleSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("sidebar-chat-lifecycle.spec.ts"),
            encoding: .utf8
        )
        let filterSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("sidebar-filters.spec.ts"),
            encoding: .utf8
        )
        let projectSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("sidebar-projects.spec.ts"),
            encoding: .utf8
        )
        let helperText = try String(
            contentsOf: testRoot.appendingPathComponent("sidebar-test-helpers.ts"),
            encoding: .utf8
        )
        let coreSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("core.spec.ts"),
            encoding: .utf8
        )
        let focusedSpecs: [(String, String, [String])] = [
            (
                "sidebar.spec.ts",
                sidebarSpecText,
                [
                    "searches and reopens an existing chat",
                    "starts a new chat from the sidebar action"
                ]
            ),
            (
                "sidebar-chat-lifecycle.spec.ts",
                chatLifecycleSpecText,
                [
                    "manages chat lifecycle from the sidebar",
                    "groups sidebar chats by recency bucket",
                    "bulk-selects chats from the sidebar"
                ]
            ),
            (
                "sidebar-filters.spec.ts",
                filterSpecText,
                [
                    "filters sidebar chats with saved filters",
                    "filters sidebar chats with custom saved searches",
                    "creates and deletes custom saved searches from explicit sidebar targets",
                    "reorders custom saved searches from explicit sidebar targets"
                ]
            ),
            (
                "sidebar-projects.spec.ts",
                projectSpecText,
                [
                    "manages projects from the sidebar",
                    "mock harness discovers and probes an SSH remote from the native connection dialog",
                    "SSH connection is available from Settings and validates manual addresses",
                    "closing the SSH dialog cancels an in-flight remote probe"
                ]
            )
        ]

        Self.assertSource(sidebarSpecText, contains: "harnessURL()")
        Self.assertSource(helperText, contains: "clickProjectAction")
        Self.assertSource(helperText, contains: "clickThreadAction")
        Self.assertSource(projectSpecText, contains: "clickSidebarTool")
        Self.assertSource(projectSpecText, contains: "ssh://feather.local/srv/quill")
        Self.assertSource(coreSpecText, excludes: "clickProjectAction")
        Self.assertSource(coreSpecText, excludes: "replaceFocusedText")

        for (specName, specText, flowNames) in focusedSpecs {
            XCTAssertTrue(
                specText.contains("harnessURL()"),
                "\(specName) should use the shared harness URL helper."
            )
            for flowName in flowNames {
                XCTAssertTrue(specText.contains(flowName), "\(flowName) should live in \(specName).")
                XCTAssertFalse(coreSpecText.contains(flowName), "\(flowName) should not drift back into core.spec.ts.")
            }
        }
    }
}
