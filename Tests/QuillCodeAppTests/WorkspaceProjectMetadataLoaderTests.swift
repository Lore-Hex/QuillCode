import XCTest
import QuillCodeCore
import QuillCodeTools
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
        XCTAssertEqual(metadata.extensionManifests.map(\.id), [
            "mcp_server:filesystem",
            "skill:llm-advisor",
            "skill:browser-use",
            "skill:openclaw-video-toolkit",
            "skill:burstyrouter"
        ])
        XCTAssertEqual(metadata.memories.map(\.relativePath), [".quillcode/memories/team-note.md"])
    }

    func testBundledMarketplaceSkillsAreHiddenByInstalledManifests() throws {
        let root = try makeQuillCodeTestDirectory()
        let skillDirectory = root.appendingPathComponent(".quillcode/skills")
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try #"""
        {
          "id": "llm-advisor",
          "kind": "skill",
          "name": "LLM Advisor",
          "description": "Installed project copy."
        }
        """#.write(
            to: skillDirectory.appendingPathComponent("llm-advisor.json"),
            atomically: true,
            encoding: .utf8
        )

        let metadata = WorkspaceProjectMetadataLoader.loadLocal(from: root)

        XCTAssertEqual(
            metadata.extensionManifests.filter { $0.id == "skill:llm-advisor" }.map(\.relativePath),
            [".quillcode/skills/llm-advisor.json"]
        )
        XCTAssertFalse(
            metadata.extensionManifests.contains {
                $0.id == "skill:llm-advisor" && $0.relativePath == ".quillcode/marketplace/llm-advisor.json"
            }
        )
    }

    func testBundledMarketplaceSkillsAreInstallOnlyUntilInstalled() throws {
        let root = try makeQuillCodeTestDirectory()

        let bundledSkills = WorkspaceProjectMetadataLoader.loadLocal(from: root).extensionManifests.filter {
            $0.relativePath.hasPrefix(".quillcode/marketplace/")
        }

        XCTAssertEqual(bundledSkills.map(\.name), [
            "LLM Advisor",
            "Browser Use",
            "OpenClaw Video Toolkit",
            "BurstyRouter"
        ])
        for skill in bundledSkills {
            XCTAssertEqual(skill.kind, .skill)
            XCTAssertNotNil(skill.installCommand, "\(skill.name) should be installable from the bundled catalog.")
            XCTAssertNil(skill.updateCommand, "\(skill.name) should not show Update before it is installed.")
            XCTAssertEqual(skill.installTimeoutSeconds, 300)
            XCTAssertTrue(skill.installCommand?.contains(".quillcode/skills") == true)
            XCTAssertTrue(skill.installCommand?.contains(".json") == true)
        }
    }

    func testRemoteContextMetadataKeepsRemoteInstructionsHooksAndMemories() {
        let instruction = ProjectInstruction(
            path: "AGENTS.md",
            title: "Project AGENTS.md",
            content: "Remote rules",
            byteCount: 12
        )
        let hook = ProjectRunHook(
            id: "before:.quillcode/hooks/before-agent-run/01-prepare.sh",
            timing: .beforeAgentRun,
            title: "Prepare",
            relativePath: ".quillcode/hooks/before-agent-run/01-prepare.sh",
            command: "sh .quillcode/hooks/before-agent-run/01-prepare.sh"
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
            runHooks: [hook],
            memories: [memory]
        ))

        XCTAssertEqual(metadata.instructions, [instruction])
        XCTAssertEqual(metadata.runHooks, [hook])
        XCTAssertEqual(metadata.memories, [memory])
        XCTAssertTrue(metadata.localActions.isEmpty)
        XCTAssertTrue(metadata.extensionManifests.isEmpty)
    }

    func testLoadRemoteDiscoversBoundedDefaultRunHooks() throws {
        let root = try makeQuillCodeTestDirectory()
        let remoteRoot = root.appendingPathComponent("remote")
        let beforeDirectory = remoteRoot.appendingPathComponent(".quillcode/hooks/before-agent-run")
        let afterDirectory = remoteRoot.appendingPathComponent(".quillcode/hooks/after-agent-run")
        try FileManager.default.createDirectory(at: beforeDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: afterDirectory, withIntermediateDirectories: true)
        try "printf before".write(
            to: beforeDirectory.appendingPathComponent("01-prepare.sh"),
            atomically: true,
            encoding: .utf8
        )
        try "printf ignored".write(
            to: beforeDirectory.appendingPathComponent("not-a-hook.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "printf after".write(
            to: afterDirectory.appendingPathComponent("99-cleanup.sh"),
            atomically: true,
            encoding: .utf8
        )
        let argumentsFile = root.appendingPathComponent("ssh-arguments.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: root, argumentsFile: argumentsFile)

        let metadata = try WorkspaceProjectMetadataLoader.loadRemote(
            connection: .ssh(path: remoteRoot.path, host: "quill-feather.local", user: "quill"),
            executor: SSHRemoteShellExecutor(sshExecutable: fakeSSH.path)
        )

        XCTAssertEqual(metadata.runHooks.map(\.relativePath), [
            ".quillcode/hooks/before-agent-run/01-prepare.sh",
            ".quillcode/hooks/after-agent-run/99-cleanup.sh"
        ])
        XCTAssertEqual(metadata.runHooks.map(\.timing), [.beforeAgentRun, .afterAgentRun])
        XCTAssertEqual(metadata.runHooks.map(\.title), ["01 Prepare", "99 Cleanup"])
        XCTAssertEqual(metadata.runHooks.map(\.command), [
            "sh '.quillcode/hooks/before-agent-run/01-prepare.sh'",
            "sh '.quillcode/hooks/after-agent-run/99-cleanup.sh'"
        ])
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
