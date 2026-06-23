import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

final class QuillCodeSecondaryPaneSurfaceTests: XCTestCase {
    func testExtensionsSurfaceMapsManifestCountsAndMCPActions() {
        let plugin = ProjectExtensionManifest(
            id: "plugin:lint",
            kind: .plugin,
            name: "Lint",
            summary: "Run lint checks.",
            relativePath: ".quillcode/plugins/lint.json"
        )
        let mcp = ProjectExtensionManifest(
            id: "mcp:filesystem",
            kind: .mcpServer,
            name: "Filesystem",
            summary: "Expose workspace files.",
            relativePath: ".quillcode/mcp/filesystem.json",
            transport: .stdio,
            launchExecutable: "quill-mcp",
            launchCommand: "quill-mcp --root .",
            updateCommand: "quill-mcp update"
        )
        let probe = MCPServerProbeSummary(
            protocolVersion: "2024-11-05",
            serverName: "Filesystem",
            serverVersion: "1.0",
            toolDescriptors: [
                MCPToolDescriptor(
                    name: "read_file",
                    description: "Read a file",
                    requiredArguments: ["path"],
                    schemaSummary: "path: string"
                )
            ],
            resourceNames: ["README"],
            promptNames: ["review"]
        )

        let surface = WorkspaceExtensionsSurface(
            isVisible: true,
            manifests: [plugin, mcp],
            mcpServerStatuses: ["mcp:filesystem": .ready],
            mcpServerProbeSummaries: ["mcp:filesystem": probe]
        )

        XCTAssertTrue(surface.isVisible)
        XCTAssertEqual(surface.title, "Extensions")
        XCTAssertEqual(surface.subtitle, "1 plugin · 0 skills · 1 MCP server")
        XCTAssertEqual(surface.pluginCount, 1)
        XCTAssertEqual(surface.skillCount, 0)
        XCTAssertEqual(surface.mcpServerCount, 1)
        XCTAssertEqual(surface.items.map(\.name), ["Lint", "Filesystem"])
        XCTAssertEqual(surface.items[1].statusLabel, "Ready")
        XCTAssertEqual(surface.items[1].transportLabel, "STDIO")
        XCTAssertEqual(surface.items[1].serverLabel, "Filesystem 1.0")
        XCTAssertEqual(surface.items[1].toolDescriptors.map(\.name), ["read_file"])
        XCTAssertEqual(surface.items[1].resourceNames, ["README"])
        XCTAssertEqual(surface.items[1].promptNames, ["review"])
        XCTAssertFalse(surface.items[1].canStart)
        XCTAssertTrue(surface.items[1].canStop)
        XCTAssertTrue(surface.items[1].canUpdate)
        XCTAssertEqual(surface.items[1].stopCommandID, "mcp-stop:mcp:filesystem")
        XCTAssertEqual(surface.items[1].updateCommandID, "extension-update:mcp:filesystem")
    }

    func testMemoriesSurfaceBuildsPreviewCountsAndDeleteCommands() {
        let global = MemoryNote(
            id: "global-1",
            scope: .global,
            title: "Preferences",
            content: String(repeating: "Prefer small reviewable changes. ", count: 12),
            relativePath: "memories/preferences.md",
            byteCount: 420,
            wasTruncated: true
        )
        let project = MemoryNote(
            id: "project-1",
            scope: .project,
            title: "Repo note",
            content: "Use SwiftPM.",
            relativePath: ".quillcode/memories/repo.md",
            byteCount: 12
        )

        let surface = WorkspaceMemoriesSurface(isVisible: true, notes: [global, project])

        XCTAssertTrue(surface.isVisible)
        XCTAssertEqual(surface.subtitle, "1 global memory · 1 project memory")
        XCTAssertEqual(surface.globalCount, 1)
        XCTAssertEqual(surface.projectCount, 1)
        XCTAssertEqual(surface.items[0].scopeLabel, "Global")
        XCTAssertEqual(surface.items[0].byteCountLabel, "420 bytes, truncated")
        XCTAssertTrue(surface.items[0].preview.hasSuffix("..."))
        XCTAssertTrue(surface.items[0].canDelete)
        XCTAssertEqual(surface.items[0].deleteCommandID, "memory-delete:global-1")
        XCTAssertFalse(surface.items[1].canDelete)
        XCTAssertNil(surface.items[1].deleteCommandID)
    }

    func testAutomationsSurfaceUsesConfiguredWorkflowsAndActions() {
        let due = Date(timeIntervalSince1970: 100)
        let active = QuillAutomation(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            title: "Morning check",
            detail: "Check the workspace.",
            kind: .workspaceSchedule,
            status: .active,
            scheduleKind: .cron,
            scheduleDescription: "Every morning",
            nextRunAt: due
        )
        let paused = QuillAutomation(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
            title: "Follow up",
            detail: "Wake the thread.",
            kind: .threadFollowUp,
            status: .paused,
            scheduleKind: .heartbeat,
            scheduleDescription: "Tomorrow at 9:00 AM"
        )

        let surface = WorkspaceAutomationsSurface(isVisible: true, automations: [paused, active])

        XCTAssertTrue(surface.isVisible)
        XCTAssertEqual(surface.title, "Automations")
        XCTAssertEqual(surface.statusLabel, "1 active · 1 paused")
        XCTAssertEqual(surface.workflows.map(\.title), ["Morning check", "Follow up"])
        XCTAssertEqual(surface.workflows[0].statusLabel, "Due")
        XCTAssertEqual(surface.workflows[0].scheduleLabel, "Every morning")
        XCTAssertEqual(surface.workflows[0].runActionTitle, "Run now")
        XCTAssertEqual(surface.workflows[0].runCommandID, "automation-run:00000000-0000-0000-0000-000000000101")
        XCTAssertEqual(surface.workflows[0].primaryActionTitle, "Pause")
        XCTAssertEqual(surface.workflows[0].primaryCommandID, "automation-pause:00000000-0000-0000-0000-000000000101")
        XCTAssertEqual(surface.workflows[1].primaryActionTitle, "Resume")
        XCTAssertEqual(surface.workflows[1].primaryCommandID, "automation-resume:00000000-0000-0000-0000-000000000102")
        XCTAssertNil(surface.workflows[1].runCommandID)
    }
}
