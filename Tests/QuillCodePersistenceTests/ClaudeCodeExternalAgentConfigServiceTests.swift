import Foundation
import XCTest
@testable import QuillCodeCore
@testable import QuillCodePersistence

final class ClaudeCodeExternalAgentConfigServiceTests: XCTestCase {
    func testDetectImportAndRedetectAreScopedAdditiveAndSecretFree() async throws {
        let fixture = try makeFixture()
        try fixture.writeSourceSetup()
        let service = ClaudeCodeExternalAgentConfigService(
            sourceHomeDirectory: fixture.sourceHome,
            destinationPaths: fixture.paths,
            appConfig: AppConfig()
        )

        let items = try await service.detect(
            cwds: [fixture.repository.appendingPathComponent("Sources")],
            includeHome: true
        )
        XCTAssertEqual(items.map(\.itemType), [
            .config, .mcpServerConfig, .hooks, .skills, .commands, .subagents,
            .agentsMD, .plugins,
            .config, .mcpServerConfig, .skills, .agentsMD,
        ])
        XCTAssertNil(items.first { $0.itemType == .skills }?.details)
        XCTAssertEqual(
            items.first { $0.itemType == .mcpServerConfig && $0.cwd == nil }?
                .details?.mcpServers.map(\.name),
            ["home-server"]
        )

        for item in items {
            let result = await service.importItem(item) { _ in
                XCTFail("This fixture does not contain sessions")
                return UUID()
            }
            XCTAssertTrue(result.failures.isEmpty, "\(item.itemType): \(result.failures)")
            XCTAssertFalse(result.successes.isEmpty, "\(item.itemType) produced no import result")
        }

        let remaining = try await service.detect(
            cwds: [fixture.repository],
            includeHome: true
        )
        XCTAssertTrue(remaining.isEmpty, "Expected idempotent detection, found \(remaining)")

        let homeConfig = try ConfigDocumentStore(fileURL: fixture.paths.configFile).load()
        XCTAssertEqual(homeConfig.values["sandbox_mode"], .string("workspace-write"))
        let server = try XCTUnwrap(
            homeConfig.values["mcp_servers"]?.objectValue?["home-server"]?.objectValue
        )
        XCTAssertEqual(server["env_vars"], .array([.string("API_TOKEN")]))
        let encoded = try JSONEncoder().encode(homeConfig.values)
        let encodedText = String(decoding: encoded, as: UTF8.self)
        XCTAssertFalse(encodedText.contains("super-secret"))
        XCTAssertFalse(encodedText.contains("nested-secret"))

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: fixture.root.appendingPathComponent(".agents/skills/home-skill/SKILL.md").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: fixture.repository.appendingPathComponent(".agents/skills/repo-skill/SKILL.md").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: fixture.root.appendingPathComponent(".agents/skills/explain/SKILL.md").path
        ))
    }

    func testSessionImportRejectsClientSuppliedPathAndBecomesIdempotentAfterHistory() async throws {
        let fixture = try makeFixture()
        let transcript = fixture.sourceHome
            .appendingPathComponent(".claude/projects/repo/session-1.jsonl")
        try fixture.write(
            "{\"sessionId\":\"session-1\",\"cwd\":\"\(fixture.repository.path)\","
                + "\"timestamp\":\"2026-07-16T12:00:00Z\",\"type\":\"user\","
                + "\"message\":{\"role\":\"user\",\"content\":\"Fix the tests\"}}\n",
            to: transcript
        )
        let service = ClaudeCodeExternalAgentConfigService(
            sourceHomeDirectory: fixture.sourceHome,
            destinationPaths: fixture.paths,
            appConfig: AppConfig()
        )
        let detected = try await service.detect(includeHome: true)
        let item = try XCTUnwrap(detected.first { $0.itemType == .sessions })
        let collector = ImportedSessionCollector()
        let result = await service.importItem(item) { imported in
            await collector.append(imported)
            return imported.thread.id
        }
        XCTAssertTrue(result.failures.isEmpty)
        let importedSessions = await collector.values()
        XCTAssertEqual(importedSessions.first?.thread.title, "Fix the tests")
        XCTAssertEqual(
            result.successes.first?.source,
            transcript.standardizedFileURL.resolvingSymlinksInPath().path
        )

        let history = ExternalAgentConfigImportHistory(
            importId: UUID(),
            completedAtMs: 1,
            successes: result.successes,
            failures: result.failures
        )
        try await service.record(history)
        let remaining = try await service.detect(includeHome: true)
        XCTAssertFalse(remaining.contains { $0.itemType == .sessions })

        var forged = item
        forged.details?.sessions[0].path = "/tmp/not-a-claude-session.jsonl"
        let rejected = await service.importItem(forged) { _ in
            XCTFail("A forged path must never reach the session importer")
            return UUID()
        }
        XCTAssertEqual(rejected.failures.first?.errorType, "migration_item_not_detected")
    }

    func testHistoryStorePersistsNewestFirstWithPrivatePermissions() throws {
        let root = try temporaryDirectory()
        let file = root.appendingPathComponent("imports/history.json")
        let store = ExternalAgentConfigImportHistoryStore(fileURL: file)
        let old = ExternalAgentConfigImportHistory(
            importId: UUID(),
            completedAtMs: 1,
            successes: [],
            failures: []
        )
        let new = ExternalAgentConfigImportHistory(
            importId: UUID(),
            completedAtMs: 2,
            successes: [],
            failures: []
        )
        try store.record(old)
        try store.record(new)
        XCTAssertEqual(try store.load().map(\.importId), [new.importId, old.importId])
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testSelectiveHooksDoNotImportUnselectedCommands() async throws {
        let fixture = try makeFixture()
        try fixture.write(
            """
            {"hooks": {
              "Stop": [{"hooks": [{"type": "command", "command": "echo stop"}]}],
              "PreToolUse": [{"hooks": [{"type": "command", "command": "echo pre"}]}]
            }}
            """,
            to: fixture.sourceHome.appendingPathComponent(".claude/settings.json")
        )
        let service = ClaudeCodeExternalAgentConfigService(
            sourceHomeDirectory: fixture.sourceHome,
            destinationPaths: fixture.paths,
            appConfig: AppConfig()
        )
        let detected = try await service.detect(includeHome: true)
        var hookItem = try XCTUnwrap(detected.first { $0.itemType == .hooks })
        hookItem.details?.hooks = [.init(name: "Stop")]
        let result = await service.importItem(hookItem) { imported in imported.thread.id }
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(result.successes.map(\.source), ["Stop"])

        let data = try Data(contentsOf: fixture.paths.home.appendingPathComponent("hooks.json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hooks = try XCTUnwrap(object["hooks"] as? [String: Any])
        XCTAssertEqual(Set(hooks.keys), ["Stop"])
    }

    func testSelectivePluginImportAcceptsSubsetAndLeavesOtherPluginsDetectable() async throws {
        let fixture = try makeFixture()
        for name in ["alpha", "beta"] {
            try fixture.write(
                "{\"name\":\"\(name)\",\"version\":\"1.0.0\"}",
                to: fixture.sourceHome.appendingPathComponent(
                    ".claude/plugins/\(name)/.claude-plugin/plugin.json"
                )
            )
        }
        let service = ClaudeCodeExternalAgentConfigService(
            sourceHomeDirectory: fixture.sourceHome,
            destinationPaths: fixture.paths,
            appConfig: AppConfig()
        )
        let detected = try await service.detect(includeHome: true)
        var plugins = try XCTUnwrap(detected.first { $0.itemType == .plugins })
        plugins.details?.plugins = [.init(marketplaceName: "local", pluginNames: ["alpha"])]

        let result = await service.importItem(plugins) { imported in imported.thread.id }

        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(result.successes.map(\.source), ["alpha"])
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: fixture.paths.home.appendingPathComponent("plugins/alpha").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.paths.home.appendingPathComponent("plugins/beta").path
        ))
        let remaining = try await service.detect(includeHome: true)
        XCTAssertEqual(
            remaining.first { $0.itemType == .plugins }?.details?.plugins.first?.pluginNames,
            ["beta"]
        )
    }

    func testConcurrentMCPSubsetsSerializeWithoutLosingServers() async throws {
        let fixture = try makeFixture()
        try fixture.write(
            """
            {"mcpServers": {
              "alpha": {"command": "echo", "args": ["alpha"]},
              "beta": {"command": "echo", "args": ["beta"]}
            }}
            """,
            to: fixture.sourceHome.appendingPathComponent(".claude/settings.json")
        )
        let service = ClaudeCodeExternalAgentConfigService(
            sourceHomeDirectory: fixture.sourceHome,
            destinationPaths: fixture.paths,
            appConfig: AppConfig()
        )
        let detected = try await service.detect(includeHome: true)
        let item = try XCTUnwrap(detected.first { $0.itemType == .mcpServerConfig })
        var alpha = item
        alpha.details?.mcpServers = [.init(name: "alpha")]
        var beta = item
        beta.details?.mcpServers = [.init(name: "beta")]

        async let alphaResult = service.importItem(alpha) { imported in imported.thread.id }
        async let betaResult = service.importItem(beta) { imported in imported.thread.id }
        let results = await [alphaResult, betaResult]
        XCTAssertTrue(results.flatMap(\.failures).isEmpty)

        let config = try ConfigDocumentStore(fileURL: fixture.paths.configFile).load()
        XCTAssertEqual(
            Set(config.values["mcp_servers"]?.objectValue?.keys ?? [:].keys),
            ["alpha", "beta"]
        )
    }

    func testHistoryStoreRejectsSymlinkWithoutTouchingTarget() throws {
        let root = try temporaryDirectory()
        let imports = root.appendingPathComponent("imports")
        try FileManager.default.createDirectory(at: imports, withIntermediateDirectories: true)
        let outside = root.appendingPathComponent("outside.json")
        try Data("[]".utf8).write(to: outside)
        let history = imports.appendingPathComponent("history.json")
        try FileManager.default.createSymbolicLink(at: history, withDestinationURL: outside)
        let store = ExternalAgentConfigImportHistoryStore(fileURL: history)

        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(
                error as? ExternalAgentConfigImportHistoryStoreError,
                .invalidHistoryFile
            )
        }
        XCTAssertThrowsError(try store.record(.init(
            importId: UUID(),
            completedAtMs: 1,
            successes: [],
            failures: []
        )))
        XCTAssertEqual(try Data(contentsOf: outside), Data("[]".utf8))
    }
}

private actor ImportedSessionCollector {
    private var imported: [ExternalAgentConfigImportedSession] = []

    func append(_ value: ExternalAgentConfigImportedSession) {
        imported.append(value)
    }

    func values() -> [ExternalAgentConfigImportedSession] {
        imported
    }
}

private struct ExternalAgentConfigFixture {
    var root: URL
    var sourceHome: URL
    var repository: URL
    var paths: QuillCodePaths

    func writeSourceSetup() throws {
        try write("", to: repository.appendingPathComponent(".git/HEAD"))
        try FileManager.default.createDirectory(
            at: repository.appendingPathComponent("Sources"),
            withIntermediateDirectories: true
        )
        try write(
            """
            {
              "sandbox": {"enabled": true},
              "mcpServers": {
                "home-server": {
                  "command": "echo",
                  "args": ["ready"],
                  "env": {"API_TOKEN": "super-secret"},
                  "metadata": {"apiKey": "nested-secret"}
                }
              },
              "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "echo done"}]}]}
            }
            """,
            to: sourceHome.appendingPathComponent(".claude/settings.json")
        )
        try write(
            "{\"sandbox\":{\"enabled\":true}}",
            to: repository.appendingPathComponent(".claude/settings.local.json")
        )
        try write(
            "{\"mcpServers\":{\"repo-server\":{\"command\":\"echo\"}}}",
            to: repository.appendingPathComponent(".mcp.json")
        )
        try write("Home instructions", to: sourceHome.appendingPathComponent(".claude/CLAUDE.md"))
        try write("Repo instructions", to: repository.appendingPathComponent("CLAUDE.md"))
        try write(
            "---\nname: home-skill\ndescription: Home\n---\n",
            to: sourceHome.appendingPathComponent(".claude/skills/home-skill/SKILL.md")
        )
        try write(
            "---\nname: repo-skill\ndescription: Repo\n---\n",
            to: repository.appendingPathComponent(".claude/skills/repo-skill/SKILL.md")
        )
        try write("Explain this", to: sourceHome.appendingPathComponent(".claude/commands/explain.md"))
        try write("Review code", to: sourceHome.appendingPathComponent(".claude/agents/reviewer.md"))
        try write(
            "{\"name\":\"local-plugin\",\"version\":\"1.0.0\"}",
            to: sourceHome.appendingPathComponent(
                ".claude/plugins/local-plugin/.claude-plugin/plugin.json"
            )
        )
    }

    func write(_ contents: String, to file: URL) throws {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: file, atomically: true, encoding: .utf8)
    }
}

private extension ClaudeCodeExternalAgentConfigServiceTests {
    func makeFixture() throws -> ExternalAgentConfigFixture {
        let root = try temporaryDirectory()
        let sourceHome = root.appendingPathComponent("home")
        let repository = root.appendingPathComponent("repo")
        let destination = root.appendingPathComponent("quill-home")
        try FileManager.default.createDirectory(at: sourceHome, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        return .init(
            root: root,
            sourceHome: sourceHome,
            repository: repository,
            paths: QuillCodePaths(home: destination)
        )
    }

    func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-external-agent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
