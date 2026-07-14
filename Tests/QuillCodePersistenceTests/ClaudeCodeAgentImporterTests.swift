import XCTest
import QuillCodeCore
@testable import QuillCodePersistence

final class ClaudeCodeAgentImporterTests: PersistenceTestCase {
    func testDiscoveryAndImportCoverSupportedSetupWithoutCopyingSecrets() throws {
        let fixture = try ClaudeImportFixture(testCase: self)
        let preview = fixture.importer.discover(existingProjects: [], now: fixture.now)

        XCTAssertEqual(Set(preview.candidates.map(\.kind)), Set(AgentImportItemKind.allCases))
        XCTAssertEqual(preview.projects.map(\.path), [fixture.project.path])
        XCTAssertEqual(preview.selectableCandidates.count, preview.candidates.count)

        let mutation = fixture.importer.prepareImport(
            selection: AgentImportSelection(
                source: .claudeCode,
                candidateIDs: preview.defaultCandidateIDs,
                projectPaths: preview.defaultProjectPaths
            ),
            existingProjects: [],
            existingThreads: [],
            config: AppConfig(defaultModel: "trustedrouter/fast"),
            now: fixture.now
        )

        XCTAssertEqual(mutation.projects.map(\.path), [fixture.project.path])
        XCTAssertEqual(mutation.threads.count, 1)
        XCTAssertEqual(mutation.threads.first?.messages.map(\.content), ["Please inspect this project", "I inspected it."])
        XCTAssertEqual(mutation.threads.first?.projectID, mutation.projects.first?.id)
        XCTAssertGreaterThan(mutation.outcome.importedCount, 8)
        XCTAssertTrue(mutation.outcome.setupFollowUps.contains { $0.contains("MCP") })
        XCTAssertTrue(mutation.outcome.setupFollowUps.contains { $0.contains("hooks") })
        XCTAssertTrue(mutation.outcome.diagnostics.isEmpty, mutation.outcome.diagnostics.joined(separator: "\n"))

        let importedFiles = try allRegularFiles(inside: fixture.project)
        XCTAssertTrue(importedFiles.contains { $0.path.contains(".quillcode/rules/imported-claude-") })
        XCTAssertTrue(importedFiles.contains { $0.path.contains(".quillcode/plugins/demo-imported-") })
        XCTAssertTrue(importedFiles.contains { $0.lastPathComponent == "mcp.json" })
        XCTAssertTrue(importedFiles.contains { $0.lastPathComponent == "hooks.json" })
        XCTAssertEqual(try text(at: fixture.existingFile), "keep me")

        let importedText = importedFiles
            .compactMap { try? text(at: $0) }
            .joined(separator: "\n")
        for secret in fixture.secrets {
            XCTAssertFalse(importedText.contains(secret), "Imported data leaked secret: \(secret)")
        }
        XCTAssertTrue(importedText.contains("API_TOKEN"))
        XCTAssertTrue(importedText.contains("transport=sse"))
        XCTAssertFalse(importedText.contains("token=hidden-query"))

        let importedPluginManifest = try XCTUnwrap(importedFiles.first {
            $0.path.contains("demo-imported-") && $0.path.hasSuffix(".codex-plugin/plugin.json")
        })
        XCTAssertTrue(try text(at: importedPluginManifest).contains("demo"))
    }

    func testCommittedImportIsNotOfferedOrMaterializedAgain() throws {
        let fixture = try ClaudeImportFixture(testCase: self)
        let preview = fixture.importer.discover(existingProjects: [], now: fixture.now)
        let selection = AgentImportSelection(
            source: .claudeCode,
            candidateIDs: preview.defaultCandidateIDs,
            projectPaths: preview.defaultProjectPaths
        )
        let first = fixture.importer.prepareImport(
            selection: selection,
            existingProjects: [],
            existingThreads: [],
            config: AppConfig(),
            now: fixture.now
        )
        try fixture.importer.commit(first.importedCandidateIDs, at: fixture.now)

        let refreshed = fixture.importer.discover(existingProjects: first.projects, now: fixture.now)
        let repeated = fixture.importer.prepareImport(
            selection: selection,
            existingProjects: first.projects,
            existingThreads: first.threads,
            config: AppConfig(),
            now: fixture.now
        )

        XCTAssertTrue(refreshed.selectableCandidates.isEmpty)
        XCTAssertEqual(refreshed.alreadyImportedCount, refreshed.candidates.count)
        XCTAssertEqual(repeated.outcome.importedCount, 0)
        XCTAssertTrue(repeated.projects.isEmpty)
        XCTAssertTrue(repeated.threads.isEmpty)
    }

    func testRollbackRemovesOnlyArtifactsCreatedByTheImport() throws {
        let fixture = try ClaudeImportFixture(testCase: self)
        let preview = fixture.importer.discover(existingProjects: [], now: fixture.now)
        let mutation = fixture.importer.prepareImport(
            selection: AgentImportSelection(
                source: .claudeCode,
                candidateIDs: preview.defaultCandidateIDs,
                projectPaths: preview.defaultProjectPaths
            ),
            existingProjects: [],
            existingThreads: [],
            config: AppConfig(),
            now: fixture.now
        )

        XCTAssertFalse(mutation.createdArtifacts.isEmpty)
        fixture.importer.rollbackArtifacts(in: mutation)

        let existingPath = fixture.existingFile.standardizedFileURL.path
        let remainingImportedFiles = try allRegularFiles(inside: fixture.project).filter {
            $0.path.contains("/.quillcode/") && $0.standardizedFileURL.path != existingPath
        }
        XCTAssertTrue(remainingImportedFiles.isEmpty, remainingImportedFiles.map(\.path).joined(separator: "\n"))
        XCTAssertEqual(try text(at: fixture.existingFile), "keep me")
    }

    func testOldAndMalformedTranscriptsDoNotBecomeChats() throws {
        let fixture = try ClaudeImportFixture(testCase: self)
        let old = fixture.transcriptsDirectory.appendingPathComponent("old.jsonl")
        try Data("{not-json}\n".utf8).write(to: old)
        try FileManager.default.setAttributes(
            [.modificationDate: fixture.now.addingTimeInterval(-31 * 24 * 60 * 60)],
            ofItemAtPath: old.path
        )
        let malformed = fixture.transcriptsDirectory.appendingPathComponent("malformed.jsonl")
        try Data("{not-json}\n".utf8).write(to: malformed)
        try FileManager.default.setAttributes([.modificationDate: fixture.now], ofItemAtPath: malformed.path)

        let preview = fixture.importer.discover(existingProjects: [], now: fixture.now)

        XCTAssertEqual(preview.candidates.filter { $0.kind == .chats }.count, 1)
    }

    func testGlobalSetupCanBeImportedIntoAProjectAddedLater() throws {
        let fixture = try ClaudeImportFixture(testCase: self)
        let initialPreview = fixture.importer.discover(existingProjects: [], now: fixture.now)
        let initial = fixture.importer.prepareImport(
            selection: AgentImportSelection(
                source: .claudeCode,
                candidateIDs: initialPreview.defaultCandidateIDs,
                projectPaths: initialPreview.defaultProjectPaths
            ),
            existingProjects: [],
            existingThreads: [],
            config: AppConfig(),
            now: fixture.now
        )
        try fixture.importer.commit(initial.importedCandidateIDs, at: fixture.now)
        let firstRuleCount = try allRegularFiles(inside: fixture.project).filter {
            $0.path.contains(".quillcode/rules/imported-claude-")
        }.count

        let secondProject = try makeTempDirectory().appendingPathComponent("second-project")
        try FileManager.default.createDirectory(at: secondProject, withIntermediateDirectories: true)
        let registeredSecond = ProjectRef(name: "second-project", path: secondProject.path)
        let existingProjects = initial.projects + [registeredSecond]
        let expandedPreview = fixture.importer.discover(existingProjects: existingProjects, now: fixture.now)

        XCTAssertTrue(expandedPreview.selectableCandidates.contains {
            $0.projectPath == nil && $0.kind == .instructions
        })
        let expanded = fixture.importer.prepareImport(
            selection: AgentImportSelection(
                source: .claudeCode,
                candidateIDs: expandedPreview.defaultCandidateIDs,
                projectPaths: expandedPreview.defaultProjectPaths
            ),
            existingProjects: existingProjects,
            existingThreads: initial.threads,
            config: AppConfig(),
            now: fixture.now
        )

        let secondFiles = try allRegularFiles(inside: secondProject)
        XCTAssertTrue(secondFiles.contains { $0.path.contains(".quillcode/rules/imported-claude-") })
        XCTAssertEqual(
            try allRegularFiles(inside: fixture.project).filter {
                $0.path.contains(".quillcode/rules/imported-claude-")
            }.count,
            firstRuleCount
        )
        XCTAssertGreaterThan(expanded.outcome.importedCount, 0)
    }

    private func allRegularFiles(inside root: URL) throws -> [URL] {
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ))
        return try enumerator.compactMap { value in
            let url = try XCTUnwrap(value as? URL)
            return try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true ? url : nil
        }
    }

    private func text(at file: URL) throws -> String {
        String(decoding: try Data(contentsOf: file), as: UTF8.self)
    }
}

private struct ClaudeImportFixture {
    let home: URL
    let project: URL
    let destination: URL
    let transcriptsDirectory: URL
    let existingFile: URL
    let importer: ClaudeCodeAgentImporter
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let secrets = [
        "sk-test-super-secret",
        "hidden-env-value",
        "hidden-header-value",
        "hidden-argument-value",
        "hidden-query",
        "hidden-hook-value"
    ]

    init(testCase: PersistenceTestCase) throws {
        home = try testCase.makeTempDirectory()
        project = try testCase.makeTempDirectory().appendingPathComponent("sample-project")
        destination = try testCase.makeTempDirectory().appendingPathComponent(".quillcode")
        let claude = home.appendingPathComponent(".claude")
        transcriptsDirectory = claude.appendingPathComponent("projects/sample-project")
        existingFile = project.appendingPathComponent(".quillcode/rules/custom.md")
        importer = ClaudeCodeAgentImporter(
            sourceHomeDirectory: home,
            destinationPaths: QuillCodePaths(home: destination)
        )

        try FileManager.default.createDirectory(at: transcriptsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: existingFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("keep me".utf8).write(to: existingFile)
        try Data("Use tests before changing behavior.".utf8).write(to: claude.appendingPathComponent("CLAUDE.md"))
        try Data("Project-specific guidance.".utf8).write(to: project.appendingPathComponent("CLAUDE.md"))

        try writeSettings(to: claude.appendingPathComponent("settings.json"))
        try writeSkill(to: claude.appendingPathComponent("skills/reviewer/SKILL.md"))
        try writePlugin(to: claude.appendingPathComponent("plugins/demo"))
        try writeMarkdown("Deploy carefully.", to: claude.appendingPathComponent("commands/deploy.md"))
        try writeMarkdown("Review changes independently.", to: claude.appendingPathComponent("agents/reviewer.md"))
        try writeRegistry(to: home.appendingPathComponent(".claude.json"))
        try writeTranscript(to: transcriptsDirectory.appendingPathComponent("session-1.jsonl"))
    }

    private func writeSettings(to file: URL) throws {
        let payload: [String: Any] = [
            "apiKey": secrets[0],
            "theme": "dark",
            "mcpServers": [
                "docs": [
                    "command": "node",
                    "args": ["server.js", "--token", secrets[3]],
                    "env": ["API_TOKEN": secrets[1]],
                    "headers": ["Authorization": "Bearer \(secrets[2])"],
                    "url": "https://user:password@example.test/mcp?token=\(secrets[4])&transport=sse"
                ]
            ],
            "hooks": [
                "PreToolUse": [["hooks": [["type": "command", "command": "echo token=\(secrets[5])"]]]]
            ]
        ]
        try writeJSON(payload, to: file)
    }

    private func writeSkill(to file: URL) throws {
        try writeMarkdown("---\nname: reviewer\ndescription: Review code.\n---\nReview it.", to: file)
    }

    private func writePlugin(to directory: URL) throws {
        try writeJSON(
            ["name": "demo", "version": "1.0.0"],
            to: directory.appendingPathComponent(".claude-plugin/plugin.json")
        )
        try writeMarkdown("# Demo", to: directory.appendingPathComponent("README.md"))
        try writeMarkdown("DO_NOT_COPY", to: directory.appendingPathComponent(".env"))
    }

    private func writeRegistry(to file: URL) throws {
        try writeJSON(["projects": [project.path: ["lastCost": 0]]], to: file)
    }

    private func writeTranscript(to file: URL) throws {
        let timestamp = "2027-01-15T08:00:00Z"
        let lines: [[String: Any]] = [
            [
                "sessionId": "session-1", "cwd": project.path, "type": "user", "timestamp": timestamp,
                "message": ["role": "user", "content": "Please inspect this project"]
            ],
            [
                "sessionId": "session-1", "cwd": project.path, "type": "assistant", "timestamp": timestamp,
                "message": ["role": "assistant", "content": [["type": "text", "text": "I inspected it."], ["type": "tool_use", "name": "Read"]]]
            ],
            ["type": "progress", "content": "internal progress"],
        ]
        let data = try lines.map {
            String(decoding: try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]), as: UTF8.self)
        }.joined(separator: "\n").data(using: .utf8)!
        try data.write(to: file)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path)
    }

    private func writeMarkdown(_ content: String, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: file)
    }

    private func writeJSON(_ object: Any, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: file)
    }
}
