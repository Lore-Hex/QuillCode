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

    func testExtensionsSurfaceMarksMarketplaceEntriesAvailable() {
        let availablePlugin = ProjectExtensionManifest(
            id: "plugin:github",
            kind: .plugin,
            name: "GitHub",
            summary: "PR helpers.",
            version: "1.2.0",
            relativePath: ".quillcode/marketplace/github.json",
            installCommand: "git clone https://github.com/Lore-Hex/quillcode-github .quillcode/plugins/github"
        )

        let surface = WorkspaceExtensionsSurface(
            isVisible: true,
            manifests: [availablePlugin]
        )

        XCTAssertEqual(surface.subtitle, "1 plugin · 0 skills · 0 MCP servers · 1 available extension")
        XCTAssertEqual(surface.availableCount, 1)
        XCTAssertEqual(surface.items.first?.statusLabel, "Available")
        XCTAssertEqual(surface.items.first?.installCommandID, "extension-install:plugin:github")
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
        XCTAssertEqual(surface.items.map(\.id), ["global-1", "project-1"])
    }

    func testMemoriesSurfaceFlagsObviousGlobalProjectConflicts() {
        let global = MemoryNote(
            id: "global-preferences",
            scope: .global,
            title: "Global preferences",
            content: "Prefer SwiftUI surfaces.",
            relativePath: "memories/preferences.md",
            byteCount: 24
        )
        let project = MemoryNote(
            id: "project:.quillcode/memories/project.md",
            scope: .project,
            title: "Project memory",
            content: "Do not use SwiftUI surfaces.",
            relativePath: ".quillcode/memories/project.md",
            byteCount: 29
        )

        let surface = WorkspaceMemoriesSurface(
            isVisible: true,
            notes: [global, project],
            canEditProjectMemories: true
        )

        XCTAssertEqual(surface.subtitle, "1 global memory · 1 project memory · 1 conflict")
        XCTAssertEqual(surface.conflictCount, 1)
        XCTAssertEqual(surface.conflicts.first?.title, "Memory conflict: swiftui surfaces")
        XCTAssertEqual(surface.conflicts.first?.global.editCommandID, "memory-edit:global-preferences")
        XCTAssertEqual(
            surface.conflicts.first?.project.editCommandID,
            "memory-edit:project:.quillcode/memories/project.md"
        )
    }

    func testMemoriesSurfaceIgnoresNonOpposingOrSameScopeNotes() {
        let notes = [
            MemoryNote(
                id: "global-1",
                scope: .global,
                title: "Global one",
                content: "Prefer small commits.",
                relativePath: "memories/one.md",
                byteCount: 21
            ),
            MemoryNote(
                id: "global-2",
                scope: .global,
                title: "Global two",
                content: "Do not use small commits.",
                relativePath: "memories/two.md",
                byteCount: 25
            ),
            MemoryNote(
                id: "project-1",
                scope: .project,
                title: "Project",
                content: "Use SwiftPM.",
                relativePath: ".quillcode/memories/project.md",
                byteCount: 12
            )
        ]

        let surface = WorkspaceMemoriesSurface(isVisible: true, notes: notes)

        XCTAssertEqual(surface.conflicts, [])
        XCTAssertEqual(surface.subtitle, "2 global memories · 1 project memory")
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
        XCTAssertEqual(surface.workflows.map(\.id), [
            "00000000-0000-0000-0000-000000000101",
            "00000000-0000-0000-0000-000000000102"
        ])
    }
}
