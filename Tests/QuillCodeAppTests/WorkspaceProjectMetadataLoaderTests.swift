import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceProjectMetadataLoaderTests: XCTestCase {
    func testLoadLocalAggregatesInstructionsActionsExtensionsAndMemories() throws {
        let root = try makeQuillCodeTestDirectory()
        try "Root rules\n".write(
            to: root.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )

        let actionsDirectory = root.appendingPathComponent(".quillcode/actions")
        try FileManager.default.createDirectory(at: actionsDirectory, withIntermediateDirectories: true)
        try "printf ok".write(
            to: actionsDirectory.appendingPathComponent("bootstrap.sh"),
            atomically: true,
            encoding: .utf8
        )

        let mcpDirectory = root.appendingPathComponent(".quillcode/mcp")
        try FileManager.default.createDirectory(at: mcpDirectory, withIntermediateDirectories: true)
        try #"{"id":"filesystem","name":"Filesystem MCP","command":"quill-mcp"}"#.write(
            to: mcpDirectory.appendingPathComponent("filesystem.json"),
            atomically: true,
            encoding: .utf8
        )

        let memoryDirectory = root.appendingPathComponent(".quillcode/memories")
        try FileManager.default.createDirectory(at: memoryDirectory, withIntermediateDirectories: true)
        try "Prefer small PRs.\n".write(
            to: memoryDirectory.appendingPathComponent("team-note.md"),
            atomically: true,
            encoding: .utf8
        )

        let metadata = WorkspaceProjectMetadataLoader.loadLocal(from: root)

        XCTAssertEqual(metadata.instructions.map(\.path), ["AGENTS.md"])
        XCTAssertEqual(metadata.localActions.map(\.title), ["Bootstrap"])
        XCTAssertEqual(metadata.extensionManifests.map(\.id), ["mcp_server:filesystem", "skill:burstyrouter"])
        XCTAssertEqual(metadata.memories.map(\.relativePath), [".quillcode/memories/team-note.md"])
    }

    func testRemoteContextMetadataKeepsOnlyRemoteInstructionsAndMemories() {
        let instruction = ProjectInstruction(
            path: "AGENTS.md",
            title: "Project AGENTS.md",
            content: "Remote rules",
            byteCount: 12
        )
        let memory = MemoryNote(
            id: "project:.quillcode/memories/team.md",
            scope: .project,
            title: "Team",
            content: "Prefer short answers.",
            relativePath: ".quillcode/memories/team.md",
            byteCount: 21
        )

        let metadata = WorkspaceProjectMetadataLoader.metadata(from: SSHRemoteProjectContext(
            instructions: [instruction],
            memories: [memory]
        ))

        XCTAssertEqual(metadata.instructions, [instruction])
        XCTAssertEqual(metadata.memories, [memory])
        XCTAssertTrue(metadata.localActions.isEmpty)
        XCTAssertTrue(metadata.extensionManifests.isEmpty)
    }

    func testLoadLocalUsesProjectConfigForAdditionalActionDirectoriesAndCaps() throws {
        let root = try makeQuillCodeTestDirectory()
        let quillDirectory = root.appendingPathComponent(".quillcode")
        try FileManager.default.createDirectory(
            at: quillDirectory.appendingPathComponent("actions"),
            withIntermediateDirectories: true
        )
        try """
        [local_actions]
        directories = ["scripts/actions"]
        max = 1
        """.write(
            to: quillDirectory.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )
        try "printf default".write(
            to: quillDirectory.appendingPathComponent("actions/default.sh"),
            atomically: true,
            encoding: .utf8
        )

        let customActions = root.appendingPathComponent("scripts/actions")
        try FileManager.default.createDirectory(at: customActions, withIntermediateDirectories: true)
        try "printf custom".write(
            to: customActions.appendingPathComponent("custom.sh"),
            atomically: true,
            encoding: .utf8
        )
        try """
        { "title": "Custom", "order": 0 }
        """.write(
            to: customActions.appendingPathComponent("custom.json"),
            atomically: true,
            encoding: .utf8
        )

        let metadata = WorkspaceProjectMetadataLoader.loadLocal(from: root)

        XCTAssertEqual(metadata.localActions.map(\.relativePath), ["scripts/actions/custom.sh"])
    }
}
