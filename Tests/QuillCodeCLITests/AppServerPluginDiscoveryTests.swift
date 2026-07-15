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
