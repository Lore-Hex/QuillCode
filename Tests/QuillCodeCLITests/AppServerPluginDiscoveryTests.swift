import Foundation
import QuillCodeAgent
@testable import QuillCodeCLI
import QuillCodeCore
import QuillCodeSafety
import XCTest

final class AppServerPluginDiscoveryTests: XCTestCase {
    func testPluginListProjectsCodexSchemaAndInstalledState() async throws {
        let fixture = try await makeFixture()
        try writeMarketplace(
            #"""
            {
              "name": "team-tools",
              "interface": {"displayName": "Team Tools"},
              "plugins": [{
                "name": "review-kit",
                "source": {"source": "local", "path": "./catalog/review-kit"},
                "policy": {"installation": "AVAILABLE", "authentication": "ON_USE"},
                "category": "Engineering"
              }]
            }
            """#,
            in: fixture.workspace
        )
        try writePackage(
            #"""
            {
              "name": "review-kit",
              "version": "1.2.3",
              "keywords": ["review", "git"],
              "interface": {
                "displayName": "Review Kit",
                "shortDescription": "Focused code review",
                "longDescription": "Review project changes with repository context.",
                "developerName": "Lore Hex",
                "category": "Productivity",
                "capabilities": ["Read", "Write"],
                "websiteURL": "https://example.com/review-kit",
                "privacyPolicyURL": "https://example.com/privacy",
                "termsOfServiceURL": "https://example.com/terms",
                "defaultPrompt": ["Review this change", "Find regressions"],
                "brandColor": "#31A8FF",
                "composerIcon": "./assets/composer.png",
                "logo": "./assets/logo.png",
                "logoDark": "./assets/logo-dark.png",
                "screenshots": ["./assets/one.png"]
              }
            }
            """#,
            at: "catalog/review-kit",
            in: fixture.workspace
        )
        try writePackage(
            #"{"name":"review-kit","version":"2.0.0"}"#,
            at: ".quillcode/plugins/review-kit",
            in: fixture.workspace
        )

        try await fixture.request(
            id: 1,
            method: "plugin/list",
            params: ["cwds": [fixture.workspace.path]]
        )

        let response = try await fixture.result(id: 1)
        let result = try XCTUnwrap(response)
        XCTAssertEqual(result["featuredPluginIds"], .array([]))
        XCTAssertEqual(result["marketplaceLoadErrors"], .array([]))
        let marketplace = try XCTUnwrap(
            result["marketplaces"]?.arrayValue?.first?.objectValue
        )
        XCTAssertEqual(Set(marketplace.keys), ["name", "path", "interface", "plugins"])
        XCTAssertEqual(marketplace["name"], .string("team-tools"))
        XCTAssertEqual(
            marketplace["path"],
            .string(fixture.workspace.appendingPathComponent(
                ".agents/plugins/marketplace.json"
            ).path)
        )
        XCTAssertEqual(
            marketplace["interface"],
            .object(["displayName": .string("Team Tools")])
        )

        let plugin = try XCTUnwrap(marketplace["plugins"]?.arrayValue?.first?.objectValue)
        XCTAssertEqual(Set(plugin.keys), [
            "id", "remotePluginId", "localVersion", "name", "shareContext", "source",
            "installed", "enabled", "installPolicy", "authPolicy", "availability",
            "interface", "keywords"
        ])
        XCTAssertEqual(plugin["id"], .string("review-kit@team-tools"))
        XCTAssertEqual(plugin["remotePluginId"], .null)
        XCTAssertEqual(plugin["localVersion"], .string("2.0.0"))
        XCTAssertEqual(plugin["name"], .string("review-kit"))
        XCTAssertEqual(plugin["shareContext"], .null)
        XCTAssertEqual(plugin["installed"], .bool(true))
        XCTAssertEqual(plugin["enabled"], .bool(true))
        XCTAssertEqual(plugin["installPolicy"], .string("AVAILABLE"))
        XCTAssertEqual(plugin["authPolicy"], .string("ON_USE"))
        XCTAssertEqual(plugin["availability"], .string("AVAILABLE"))
        XCTAssertEqual(plugin["keywords"], .array([.string("review"), .string("git")]))
        XCTAssertEqual(
            plugin["source"],
            .object([
                "type": .string("local"),
                "path": .string(fixture.workspace.appendingPathComponent(
                    "catalog/review-kit"
                ).path)
            ])
        )

        let interface = try XCTUnwrap(plugin["interface"]?.objectValue)
        XCTAssertEqual(Set(interface.keys), [
            "displayName", "shortDescription", "longDescription", "developerName", "category",
            "capabilities", "websiteUrl", "privacyPolicyUrl", "termsOfServiceUrl",
            "defaultPrompt", "brandColor", "composerIcon", "composerIconUrl", "logo",
            "logoDark", "logoUrl", "logoUrlDark", "screenshots", "screenshotUrls"
        ])
        XCTAssertEqual(interface["displayName"], .string("Review Kit"))
        XCTAssertEqual(interface["category"], .string("Engineering"))
        XCTAssertEqual(interface["capabilities"], .array([.string("Read"), .string("Write")]))
        XCTAssertEqual(
            interface["defaultPrompt"],
            .array([.string("Review this change"), .string("Find regressions")])
        )
        XCTAssertEqual(
            interface["composerIcon"],
            .string(fixture.workspace.appendingPathComponent(
                "catalog/review-kit/assets/composer.png"
            ).path)
        )
        XCTAssertEqual(interface["composerIconUrl"], .null)
        XCTAssertEqual(
            interface["screenshots"],
            .array([.string(fixture.workspace.appendingPathComponent(
                "catalog/review-kit/assets/one.png"
            ).path)])
        )
    }

    func testPluginInstalledReturnsInstalledAndExplicitSuggestionsOnly() async throws {
        let fixture = try await makeFixture()
        try writeMarketplace(
            #"""
            {
              "name": "team-tools",
              "plugins": [
                {"name":"alpha","source":"./catalog/alpha"},
                {"name":"beta","source":"./catalog/beta"},
                {"name":"gamma","source":"./catalog/gamma"}
              ]
            }
            """#,
            in: fixture.workspace
        )
        for name in ["alpha", "beta", "gamma"] {
            try writePackage(
                #"{"name":"\#(name)","version":"1.0.0"}"#,
                at: "catalog/\(name)",
                in: fixture.workspace
            )
        }
        try writePackage(
            #"{"name":"alpha","version":"2.1.0"}"#,
            at: ".quillcode/plugins/alpha",
            in: fixture.workspace
        )
        try write(
            #"{"id":"plugin:alpha","version":"2.2.0","enabled":false}"#,
            to: ".quillcode/plugins/alpha.json",
            in: fixture.workspace
        )

        try await fixture.request(
            id: 1,
            method: "plugin/installed",
            params: [
                "cwds": [fixture.workspace.path],
                "installSuggestionPluginNames": ["beta"]
            ]
        )

        let response = try await fixture.result(id: 1)
        let result = try XCTUnwrap(response)
        XCTAssertNil(result["featuredPluginIds"])
        let plugins = try XCTUnwrap(
            result["marketplaces"]?.arrayValue?.first?.objectValue?["plugins"]?
                .arrayValue?.compactMap(\.objectValue)
        )
        XCTAssertEqual(plugins.compactMap { $0["name"]?.stringValue }, ["alpha", "beta"])
        XCTAssertEqual(plugins[0]["installed"], .bool(true))
        XCTAssertEqual(plugins[0]["enabled"], .bool(false))
        XCTAssertEqual(plugins[0]["localVersion"], .string("2.2.0"))
        XCTAssertEqual(plugins[1]["installed"], .bool(false))
        XCTAssertEqual(plugins[1]["enabled"], .bool(false))
        XCTAssertEqual(plugins[1]["localVersion"], .string("1.0.0"))
    }

    func testPluginListFindsHomeCatalogAndKeepsPartialLoadErrors() async throws {
        let fixture = try await makeFixture()
        try writeMarketplace(
            #"{"name":"home-tools","plugins":[{"name":"home","source":"./catalog/home"}]}"#,
            in: fixture.home
        )
        try writePackage(
            #"{"name":"home"}"#,
            at: "catalog/home",
            in: fixture.home
        )
        try write("{not json", to: ".claude-plugin/marketplace.json", in: fixture.home)

        try await fixture.request(id: 1, method: "plugin/list")

        let response = try await fixture.result(id: 1)
        let result = try XCTUnwrap(response)
        XCTAssertEqual(
            result["marketplaces"]?.arrayValue?.first?.objectValue?["name"],
            .string("home-tools")
        )
        let errors = try XCTUnwrap(
            result["marketplaceLoadErrors"]?.arrayValue?.compactMap(\.objectValue)
        )
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(
            errors[0]["marketplacePath"],
            .string(fixture.home.appendingPathComponent(
                ".claude-plugin/marketplace.json"
            ).path)
        )
        XCTAssertTrue(errors[0]["message"]?.stringValue?.contains("invalid marketplace file") == true)
    }

    func testPluginListRejectsSymlinkedInstalledStateDirectory() async throws {
        let fixture = try await makeFixture()
        let outside = try temporaryDirectory(prefix: "plugin-state-outside")
        try writeMarketplace(
            #"{"name":"team-tools","plugins":[{"name":"demo","source":"./catalog/demo"}]}"#,
            in: fixture.workspace
        )
        try writePackage(
            #"{"name":"demo","version":"1.0.0"}"#,
            at: "catalog/demo",
            in: fixture.workspace
        )
        try writePackage(
            #"{"name":"demo","version":"9.9.9"}"#,
            at: "demo",
            in: outside
        )
        let installDirectory = fixture.workspace.appendingPathComponent(
            ".quillcode/plugins",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: installDirectory.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: installDirectory,
            withDestinationURL: outside
        )

        try await fixture.request(
            id: 1,
            method: "plugin/list",
            params: ["cwds": [fixture.workspace.path]]
        )

        let response = try await fixture.result(id: 1)
        let plugin = try XCTUnwrap(
            response?["marketplaces"]?.arrayValue?.first?.objectValue?["plugins"]?
                .arrayValue?.first?.objectValue
        )
        XCTAssertEqual(plugin["installed"], .bool(false))
        XCTAssertEqual(plugin["enabled"], .bool(false))
        XCTAssertEqual(plugin["localVersion"], .string("1.0.0"))
    }

    func testPluginMethodsValidateInputsAndRemoteOnlyListIsEmpty() async throws {
        let fixture = try await makeFixture()

        try await fixture.request(
            id: 1,
            method: "plugin/list",
            params: ["cwds": ["relative/path"]]
        )
        try await fixture.request(
            id: 2,
            method: "plugin/list",
            params: ["marketplaceKinds": ["unknown"]]
        )
        try await fixture.request(
            id: 3,
            method: "plugin/installed",
            params: ["installSuggestionPluginNames": ["bad/name"]]
        )
        try await fixture.request(
            id: 4,
            method: "plugin/list",
            params: ["marketplaceKinds": ["workspace-directory"]]
        )

        let relativePathError = try await fixture.errorCode(id: 1)
        XCTAssertEqual(relativePathError, -32_600)
        for id in 2...3 {
            let code = try await fixture.errorCode(id: id)
            XCTAssertEqual(code, -32_602)
        }
        let remoteOnly = try await fixture.result(id: 4)
        XCTAssertEqual(
            remoteOnly,
            [
                "marketplaces": .array([]),
                "marketplaceLoadErrors": .array([]),
                "featuredPluginIds": .array([])
            ]
        )
    }

    func testPluginReadProjectsLocalBundleDetails() async throws {
        let fixture = try await makeFixture()
        try writeMarketplace(
            #"{"name":"codex-curated","plugins":[{"name":"demo-plugin","source":"./plugins/demo-plugin","policy":{"installation":"AVAILABLE","authentication":"ON_INSTALL"},"category":"Design"}]}"#,
            in: fixture.workspace
        )
        try writePackage(
            #"{"name":"demo-plugin","version":"1.0.0","description":"Longer manifest description","keywords":["api-key","developer tools"],"interface":{"displayName":"Plugin Display Name","defaultPrompt":["Draft the reply"],"logoDark":"./assets/logo-dark.png"}}"#,
            at: "plugins/demo-plugin",
            in: fixture.workspace
        )
        try write(
            """
            ---
            name: thread-summarizer
            description: Summarize email threads
            ---
            """,
            to: "plugins/demo-plugin/skills/thread-summarizer/SKILL.md",
            in: fixture.workspace
        )
        try write(
            """
            policy:
              products:
                - CODEX
            """,
            to: "plugins/demo-plugin/skills/thread-summarizer/agents/openai.yaml",
            in: fixture.workspace
        )
        try write(
            """
            ---
            name: chatgpt-only
            description: Hidden from Codex
            ---
            """,
            to: "plugins/demo-plugin/skills/chatgpt-only/SKILL.md",
            in: fixture.workspace
        )
        try write(
            """
            policy:
              products:
                - CHATGPT
            """,
            to: "plugins/demo-plugin/skills/chatgpt-only/agents/openai.yaml",
            in: fixture.workspace
        )
        try write(
            #"{"hooks":{"PreToolUse":[{"hooks":[{"type":"command"}]}],"SessionStart":[{"hooks":[{"type":"command"}]}]}}"#,
            to: "plugins/demo-plugin/hooks/hooks.json",
            in: fixture.workspace
        )
        try write(
            #"{"apps":{"gmail":{"id":"gmail","category":"Communication"}}}"#,
            to: "plugins/demo-plugin/.app.json",
            in: fixture.workspace
        )
        try write(
            #"{"mcpServers":{"demo":{"command":"demo-server"}}}"#,
            to: "plugins/demo-plugin/.mcp.json",
            in: fixture.workspace
        )
        try writePackage(
            #"{"name":"demo-plugin","version":"2.0.0"}"#,
            at: ".quillcode/plugins/demo-plugin",
            in: fixture.workspace
        )

        try await fixture.request(
            id: 70,
            method: "skills/config/write",
            params: ["name": "demo-plugin:thread-summarizer", "enabled": false]
        )
        try await fixture.request(
            id: 71,
            method: "plugin/read",
            params: [
                "marketplacePath": fixture.workspace.appendingPathComponent(
                    ".agents/plugins/marketplace.json"
                ).path,
                "pluginName": "demo-plugin"
            ]
        )

        let pluginReadResult = try await fixture.result(id: 71)
        let response = try XCTUnwrap(pluginReadResult)
        let plugin = try XCTUnwrap(response["plugin"]?.objectValue)
        XCTAssertEqual(Set(plugin.keys), [
            "marketplaceName", "marketplacePath", "summary", "shareUrl", "description",
            "skills", "hooks", "apps", "appTemplates", "mcpServers"
        ])
        XCTAssertEqual(plugin["marketplaceName"], .string("codex-curated"))
        XCTAssertEqual(plugin["shareUrl"], .null)
        XCTAssertEqual(plugin["description"], .string("Longer manifest description"))
        XCTAssertEqual(plugin["appTemplates"], .array([]))
        XCTAssertEqual(plugin["mcpServers"], .array([.string("demo")]))

        let summary = try XCTUnwrap(plugin["summary"]?.objectValue)
        XCTAssertEqual(summary["id"], .string("demo-plugin@codex-curated"))
        XCTAssertEqual(summary["localVersion"], .string("2.0.0"))
        XCTAssertEqual(summary["installed"], .bool(true))
        XCTAssertEqual(summary["enabled"], .bool(true))
        XCTAssertEqual(summary["installPolicy"], .string("AVAILABLE"))
        XCTAssertEqual(summary["authPolicy"], .string("ON_INSTALL"))
        XCTAssertEqual(
            summary["interface"]?.objectValue?["category"],
            .string("Design")
        )

        let skills = try XCTUnwrap(plugin["skills"]?.arrayValue?.compactMap(\.objectValue))
        XCTAssertEqual(skills.count, 1)
        XCTAssertEqual(skills[0]["name"], .string("demo-plugin:thread-summarizer"))
        XCTAssertEqual(skills[0]["enabled"], .bool(false))
        XCTAssertEqual(skills[0]["description"], .string("Summarize email threads"))

        let hooks = try XCTUnwrap(plugin["hooks"]?.arrayValue?.compactMap(\.objectValue))
        XCTAssertEqual(hooks, [
            [
                "key": .string(
                    "demo-plugin@codex-curated:hooks/hooks.json:pre_tool_use:0:0"
                ),
                "eventName": .string("preToolUse")
            ],
            [
                "key": .string(
                    "demo-plugin@codex-curated:hooks/hooks.json:session_start:0:0"
                ),
                "eventName": .string("sessionStart")
            ]
        ])
        let app = try XCTUnwrap(plugin["apps"]?.arrayValue?.first?.objectValue)
        XCTAssertEqual(app, [
            "id": .string("gmail"),
            "name": .string("gmail"),
            "description": .null,
            "installUrl": .null,
            "category": .string("Communication")
        ])
    }

    func testPluginReadValidatesSourcesAndReportsUnsupportedRemoteReads() async throws {
        let fixture = try await makeFixture()
        try writeMarketplace(
            #"{"name":"local","plugins":[{"name":"demo","source":"./plugins/demo"}]}"#,
            in: fixture.workspace
        )
        try writePackage(#"{"name":"demo"}"#, at: "plugins/demo", in: fixture.workspace)
        let catalog = fixture.workspace.appendingPathComponent(
            ".agents/plugins/marketplace.json"
        ).path

        try await fixture.request(
            id: 80,
            method: "plugin/read",
            params: ["pluginName": "demo"]
        )
        try await fixture.request(
            id: 81,
            method: "plugin/read",
            params: [
                "marketplacePath": catalog,
                "remoteMarketplaceName": "remote",
                "pluginName": "demo"
            ]
        )
        try await fixture.request(
            id: 82,
            method: "plugin/read",
            params: ["remoteMarketplaceName": "remote", "pluginName": "demo"]
        )
        try await fixture.request(
            id: 83,
            method: "plugin/skill/read",
            params: [
                "remoteMarketplaceName": "remote",
                "remotePluginId": "plugin-1",
                "skillName": "review"
            ]
        )
        try await fixture.request(
            id: 84,
            method: "plugin/read",
            params: ["marketplacePath": catalog, "pluginName": "missing"]
        )
        try await fixture.request(
            id: 85,
            method: "plugin/read",
            params: ["marketplacePath": fixture.workspace.path, "pluginName": "demo"]
        )
        try await fixture.request(
            id: 86,
            method: "plugin/read",
            params: ["remoteMarketplaceName": "remote", "pluginName": "bad/name"]
        )

        for id in 80...86 {
            let errorCode = try await fixture.errorCode(id: id)
            XCTAssertEqual(errorCode, -32_600)
        }
        let remoteReadMessage = try await fixture.errorMessage(id: 82)
        let remoteSkillMessage = try await fixture.errorMessage(id: 83)
        let missingPluginMessage = try await fixture.errorMessage(id: 84)
        let invalidPathMessage = try await fixture.errorMessage(id: 85)
        XCTAssertTrue(remoteReadMessage?.contains("remote plugin read is not available") == true)
        XCTAssertTrue(
            remoteSkillMessage?.contains("remote plugin skill read is not available") == true
        )
        XCTAssertTrue(missingPluginMessage?.contains("was not found") == true)
        XCTAssertTrue(invalidPathMessage?.contains("unsupported marketplace path") == true)
    }

    private func makeFixture() async throws -> PluginDiscoveryFixture {
        let home = try temporaryDirectory(prefix: "plugin-home")
        let workspace = try temporaryDirectory(prefix: "plugin-workspace")
        let output = PluginDiscoveryOutput()
        let session = try AppServerSession(
            request: CLIAppServerRequest(live: false, home: home),
            environment: [:],
            currentDirectory: workspace,
            runnerFactory: { configuration in
                AgentRunner(
                    llm: MockLLMClient(),
                    safety: StaticSafetyReviewer(),
                    maxToolSteps: configuration.appConfig.maxToolSteps
                )
            },
            sink: { line in await output.append(line) }
        )
        let fixture = PluginDiscoveryFixture(
            session: session,
            output: output,
            home: home,
            workspace: workspace
        )
        try await fixture.request(
            id: 100,
            method: "initialize",
            params: ["clientInfo": ["name": "PluginTests", "version": "1"]]
        )
        try await fixture.notify(method: "initialized")
        return fixture
    }

    private func writeMarketplace(_ contents: String, in root: URL) throws {
        try write(contents, to: ".agents/plugins/marketplace.json", in: root)
    }

    private func writePackage(_ contents: String, at relativeRoot: String, in root: URL) throws {
        try write(contents, to: "\(relativeRoot)/.codex-plugin/plugin.json", in: root)
    }

    private func write(_ contents: String, to relativePath: String, in root: URL) throws {
        let file = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: file, atomically: true, encoding: .utf8)
    }

    private func temporaryDirectory(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}

private struct PluginDiscoveryFixture {
    let session: AppServerSession
    let output: PluginDiscoveryOutput
    let home: URL
    let workspace: URL

    func request(id: Int, method: String, params: [String: Any] = [:]) async throws {
        try await send(["id": id, "method": method, "params": params])
    }

    func notify(method: String, params: [String: Any] = [:]) async throws {
        try await send(["method": method, "params": params])
    }

    func result(id: Int) async throws -> [String: CLIJSONValue]? {
        try await output.records().first {
            $0["id"]?.numberValue == Double(id)
        }?["result"]?.objectValue
    }

    func errorCode(id: Int) async throws -> Double? {
        try await output.records().first {
            $0["id"]?.numberValue == Double(id)
        }?["error"]?.objectValue?["code"]?.numberValue
    }

    func errorMessage(id: Int) async throws -> String? {
        try await output.records().first {
            $0["id"]?.numberValue == Double(id)
        }?["error"]?.objectValue?["message"]?.stringValue
    }

    private func send(_ value: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        await session.receive(data)
    }
}

private actor PluginDiscoveryOutput {
    private var lines: [String] = []

    func append(_ line: String) {
        lines.append(line)
    }

    func records() throws -> [[String: CLIJSONValue]] {
        try lines.map { line in
            guard let record = try CLIJSONCodec.decode(line).objectValue else {
                throw PluginDiscoveryTestError.invalidRecord
            }
            return record
        }
    }
}

private enum PluginDiscoveryTestError: Error {
    case invalidRecord
}
