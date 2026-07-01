import XCTest

final class ParityWorkspacePlaywrightMemoryGateTests: QuillCodeParityTestCase {
    func testPlaywrightMemoryFlowsStayInFocusedSpec() throws {
        let testRoot = Self.packageRoot().appendingPathComponent("E2E/playwright/tests")
        let memoriesSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("memories.spec.ts"),
            encoding: .utf8
        )
        let coreSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("core.spec.ts"),
            encoding: .utf8
        )
        let memoryFlowName = "shows memories from sidebar and command palette"

        Self.assertSource(memoriesSpecText, containsAll: [
            "harnessURL()",
            "clickSidebarTool",
            "project-memories-status",
            "/remember Prefer small reviewable commits",
            "memory-edit",
            "memory-delete",
            memoryFlowName
        ])
        Self.assertSource(coreSpecText, excludes: memoryFlowName)
    }
}
