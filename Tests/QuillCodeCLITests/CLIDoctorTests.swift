import Foundation
@testable import QuillCodeCLI
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools
import XCTest

final class CLIDoctorTests: XCTestCase {
    func testHealthyReportIsCompleteStableAndDoesNotCreateState() async throws {
        let fixture = try Fixture()
        let home = fixture.root.appendingPathComponent("missing-home", isDirectory: true)
        let report = await fixture.doctor().collect(
            request: CLIDoctorRequest(home: home),
            environment: fixture.environment(apiKey: "healthy-secret"),
            currentDirectory: fixture.root,
            inputIsTerminal: true
        )

        XCTAssertEqual(report.schemaVersion, 1)
        XCTAssertEqual(report.generatedAt, "2023-11-14T22:13:20.000Z")
        XCTAssertEqual(report.overallStatus, .ok)
        XCTAssertEqual(report.checks.count, 15)
        XCTAssertEqual(report.checks["network.provider_reachability"]?.status, .ok)
        XCTAssertEqual(report.checks["state.paths"]?.summary, "state home has not been created yet")
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.path))

        let object = try XCTUnwrap(try jsonObject(CLIDoctorRenderer.json(report)))
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(object["overallStatus"] as? String, "ok")
        XCTAssertEqual((object["checks"] as? [String: Any])?.count, 15)
    }

    func testReportsNeverExposeCredentialsProxyValuesOrMCPSecrets() async throws {
        let fixture = try Fixture()
        let home = fixture.root.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let configURL = home.appendingPathComponent("config.toml")
        try ConfigStore(fileURL: configURL).save(AppConfig(
            apiBaseURL: "https://url-user:url-password@example.test/v1?token=query-secret#fragment"
        ))
        try append(
            """

            [mcp_servers.redaction-fixture]
            url = "https://mcp.example.test/api"
            http_headers = { "X-Token" = "mcp-static-secret" }

            [mcp_servers.oauth-fixture]
            url = "https://oauth-mcp.example.test/api"
            """,
            to: configURL
        )
        let mcpToken = "mcp-oauth-private-token"
        try MCPTokenStore(
            serverID: "mcp_server:oauth-fixture",
            secretStore: AppServerMCPSecretStore(
                directory: home.appendingPathComponent("secrets", isDirectory: true)
            )
        ).saveTokens(MCPOAuthTokens(accessToken: mcpToken))
        let apiKey = "sk-tr-doctor-private"
        let doctor = fixture.doctor(networkResult: CLIDoctorNetworkResult(
            endpoint: "https://network-user:network-password@example.test/v1/models?key=query-secret",
            statusCode: nil,
            error: "transport accidentally echoed \(apiKey)"
        ))
        var environment = fixture.environment(apiKey: apiKey)
        environment["HTTPS_PROXY"] = "https://proxy-user:proxy-secret@proxy.example.test"
        let report = await doctor.collect(
            request: CLIDoctorRequest(home: home),
            environment: environment,
            currentDirectory: fixture.root,
            inputIsTerminal: true
        )
        let rendered = try CLIDoctorRenderer.json(report)
            + CLIDoctorRenderer.human(
                report,
                request: CLIDoctorRequest(home: home, disablesColor: true, usesASCII: true),
                environment: environment
            )

        for secret in [
            apiKey, "url-user", "url-password", "network-user", "network-password",
            "query-secret", "proxy-user", "proxy-secret", "mcp-static-secret", mcpToken
        ] {
            XCTAssertFalse(rendered.contains(secret), "diagnostics leaked \(secret)")
        }
        XCTAssertTrue(rendered.contains("QUILLCODE_API_KEY"))
        XCTAssertTrue(rendered.contains("HTTPS_PROXY"))
        XCTAssertTrue(rendered.contains("<redacted>"))
        XCTAssertTrue(rendered.contains("https://example.test/v1"))
        XCTAssertTrue(rendered.contains("oauth-fixture (optional, oAuth)"))
    }

    func testMalformedConfigFailsWithoutEchoingItsContents() async throws {
        let fixture = try Fixture()
        let home = try fixture.makeHome()
        let marker = "malformed-private-config-marker"
        try marker.write(
            to: home.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )
        let report = await fixture.collect(home: home)
        let config = try XCTUnwrap(report.checks["config.load"])
        let rendered = try CLIDoctorRenderer.json(report)

        XCTAssertEqual(config.status, .fail)
        XCTAssertEqual(config.summary, "config could not be loaded")
        XCTAssertFalse(rendered.contains(marker))
    }

    func testLegacyConfigIsIdentifiedAsCompatibilityInput() async throws {
        let fixture = try Fixture()
        let home = try fixture.makeHome()
        try "mode = auto\napi_base_url = https://api.trustedrouter.com/v1\n".write(
            to: home.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )
        let report = await fixture.collect(home: home)

        XCTAssertEqual(report.checks["config.load"]?.status, .warning)
        XCTAssertEqual(
            report.checks["config.load"]?.summary,
            "legacy config loaded with compatibility parsing"
        )
    }

    func testThreadInventoryFindsCorruptionOversizeMismatchesAndDuplicates() throws {
        let fixture = try Fixture()
        let home = try fixture.makeHome()
        let paths = QuillCodePaths(home: home)
        try FileManager.default.createDirectory(at: paths.threadsDirectory, withIntermediateDirectories: true)
        let thread = ChatThread(id: UUID())
        let store = JSONThreadStore(directory: paths.threadsDirectory)
        try store.save(thread)
        let original = paths.threadsDirectory.appendingPathComponent("\(thread.id.uuidString).json")
        let duplicate = paths.threadsDirectory.appendingPathComponent("\(UUID().uuidString).json")
        try FileManager.default.copyItem(at: original, to: duplicate)
        try Data("not-json".utf8).write(
            to: paths.threadsDirectory.appendingPathComponent("corrupt.json")
        )
        let oversized = paths.threadsDirectory.appendingPathComponent("oversized.json")
        FileManager.default.createFile(atPath: oversized.path, contents: Data())
        let handle = try FileHandle(forWritingTo: oversized)
        try handle.truncate(atOffset: UInt64(8 * 1_024 * 1_024 + 1))
        try handle.close()

        let check = CLIDoctorStateChecks.threadInventory(paths)
        XCTAssertEqual(check.status, .warning)
        XCTAssertEqual(text("files scanned", in: check), "4")
        XCTAssertEqual(text("healthy tasks", in: check), "2")
        XCTAssertEqual(text("unreadable tasks", in: check), "1")
        XCTAssertEqual(text("oversized tasks", in: check), "1")
        XCTAssertEqual(text("identifier mismatches", in: check), "1")
        XCTAssertEqual(text("duplicate identifiers", in: check), "1")
    }

    func testThreadInventoryStopsAtConfiguredScanCap() throws {
        let fixture = try Fixture()
        let home = try fixture.makeHome()
        let paths = QuillCodePaths(home: home)
        try FileManager.default.createDirectory(at: paths.threadsDirectory, withIntermediateDirectories: true)
        for index in 0..<3 {
            try Data("not-json-\(index)".utf8).write(
                to: paths.threadsDirectory.appendingPathComponent("\(index).json")
            )
        }

        let check = CLIDoctorStateChecks.threadInventory(
            paths,
            limits: CLIDoctorThreadInventoryLimits(maximumFiles: 2, maximumBytes: 1_024)
        )
        XCTAssertEqual(check.status, .warning)
        XCTAssertEqual(text("files scanned", in: check), "2")
        XCTAssertEqual(text("scan cap", in: check), "2")
        XCTAssertEqual(text("scan cap reached", in: check), "true")
    }

    func testReachabilityClassifiesAuthenticationRateLimitsAndTransportFailures() async throws {
        let fixture = try Fixture()
        let home = fixture.root.appendingPathComponent("missing-home", isDirectory: true)
        let unauthorizedWithoutKey = await fixture.doctor(networkResult: .init(
            endpoint: "https://api.example.test/v1/models",
            statusCode: 401,
            error: nil
        )).collect(
            request: CLIDoctorRequest(home: home),
            environment: fixture.environment(apiKey: nil),
            currentDirectory: fixture.root,
            inputIsTerminal: true
        )
        let unauthorizedWithKey = await fixture.doctor(networkResult: .init(
            endpoint: "https://api.example.test/v1/models",
            statusCode: 401,
            error: nil
        )).collect(
            request: CLIDoctorRequest(home: home),
            environment: fixture.environment(apiKey: "invalid-key"),
            currentDirectory: fixture.root,
            inputIsTerminal: true
        )
        let rateLimited = await fixture.doctor(networkResult: .init(
            endpoint: "https://api.example.test/v1/models",
            statusCode: 429,
            error: nil
        )).collect(
            request: CLIDoctorRequest(home: home),
            environment: fixture.environment(apiKey: "valid-key"),
            currentDirectory: fixture.root,
            inputIsTerminal: true
        )
        let transportFailure = await fixture.doctor(networkResult: .init(
            endpoint: "https://api.example.test/v1/models",
            statusCode: nil,
            error: "timed out"
        )).collect(
            request: CLIDoctorRequest(home: home),
            environment: fixture.environment(apiKey: "valid-key"),
            currentDirectory: fixture.root,
            inputIsTerminal: true
        )

        XCTAssertEqual(unauthorizedWithoutKey.checks["network.provider_reachability"]?.status, .ok)
        XCTAssertEqual(unauthorizedWithKey.checks["network.provider_reachability"]?.status, .fail)
        XCTAssertEqual(rateLimited.checks["network.provider_reachability"]?.status, .warning)
        XCTAssertEqual(transportFailure.checks["network.provider_reachability"]?.status, .fail)
    }

    func testHumanRendererSupportsSummaryExpansionAndStrictASCII() throws {
        let values = (1...7).map { "item-\($0)" }
        let report = CLIDoctorReport(
            generatedAt: "2026-07-15T00:00:00.000Z",
            quillCodeVersion: "test",
            checks: [
                CLIDoctorCheck(
                    id: "runtime.provenance",
                    category: "runtime",
                    status: .ok,
                    summary: "runtime ready",
                    details: ["platform": .text("TestOS")]
                ),
                CLIDoctorCheck(
                    id: "network.fixture",
                    category: "network",
                    status: .warning,
                    summary: "fixture warning",
                    details: ["items": .list(values)],
                    remediation: "inspect fixture"
                )
            ]
        )
        let environment = ["NO_COLOR": "1"]
        let summary = CLIDoctorRenderer.human(
            report,
            request: CLIDoctorRequest(summaryOnly: true, disablesColor: true, usesASCII: true),
            environment: environment
        )
        let bounded = CLIDoctorRenderer.human(
            report,
            request: CLIDoctorRequest(disablesColor: true, usesASCII: true),
            environment: environment
        )
        let expanded = CLIDoctorRenderer.human(
            report,
            request: CLIDoctorRequest(expandsLongLists: true, disablesColor: true, usesASCII: true),
            environment: environment
        )

        XCTAssertFalse(summary.contains("items:"))
        XCTAssertTrue(bounded.contains("... 2 more"))
        XCTAssertFalse(bounded.contains("item-7"))
        XCTAssertTrue(expanded.contains("item-7"))
        XCTAssertFalse(expanded.contains("more"))
        XCTAssertTrue(summary.contains("[!!]"))
        XCTAssertFalse(summary.contains("\u{001B}"))
        for scalar in ["✓", "✕", "─", "…", "·", "—"] {
            XCTAssertFalse(summary.contains(scalar), "ASCII report contained \(scalar)")
        }
    }

    private func jsonObject(_ text: String) throws -> [String: Any]? {
        try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
    }

    private func text(_ key: String, in check: CLIDoctorCheck) -> String? {
        guard case .text(let value) = check.details[key] else { return nil }
        return value
    }

    private func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }
}

private extension CLIDoctorTests {
    final class Fixture: @unchecked Sendable {
        let root: URL
        let bin: URL
        let quillCodeExecutable: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "quillcode-doctor-tests-\(UUID().uuidString)",
                isDirectory: true
            )
            bin = root.appendingPathComponent("bin", isDirectory: true)
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            quillCodeExecutable = try Self.makeExecutable(named: "quill-code", in: bin)
            _ = try Self.makeExecutable(named: "rg", in: bin)
        }

        deinit {
            try? FileManager.default.removeItem(at: root)
        }

        func makeHome() throws -> URL {
            let home = root.appendingPathComponent("home", isDirectory: true)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            return home
        }

        func environment(apiKey: String? = "test-api-key") -> [String: String] {
            var values = [
                "PATH": bin.path,
                "TERM": "xterm-256color",
                "LANG": "en_US.UTF-8"
            ]
            values["QUILLCODE_API_KEY"] = apiKey
            return values
        }

        func doctor(
            networkResult: CLIDoctorNetworkResult = CLIDoctorNetworkResult(
                endpoint: "https://api.trustedrouter.com/v1/models",
                statusCode: 200,
                error: nil
            )
        ) -> CLIDoctor {
            CLIDoctor(
                gitProbe: StubGitProbe(snapshot: CLIDoctorGitSnapshot(
                    version: "git version 2.49.0",
                    repositoryRoot: root.path,
                    branch: "main",
                    error: nil
                )),
                networkProbe: StubNetworkProbe(result: networkResult),
                runtimeProvider: { inputIsTerminal in
                    CLIDoctorRuntimeSnapshot(
                        executablePath: self.quillCodeExecutable.path,
                        operatingSystem: "TestOS 1.0",
                        inputIsTerminal: inputIsTerminal,
                        outputIsTerminal: false,
                        errorIsTerminal: false
                    )
                },
                now: { Date(timeIntervalSince1970: 1_700_000_000) }
            )
        }

        func collect(home: URL) async -> CLIDoctorReport {
            await doctor().collect(
                request: CLIDoctorRequest(home: home),
                environment: environment(),
                currentDirectory: root,
                inputIsTerminal: true
            )
        }

        private static func makeExecutable(named name: String, in directory: URL) throws -> URL {
            let url = directory.appendingPathComponent(name)
            try "#!/bin/sh\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: url.path
            )
            return url
        }
    }
}

private struct StubGitProbe: CLIDoctorGitProbing {
    var snapshot: CLIDoctorGitSnapshot

    func inspect(currentDirectory: URL) -> CLIDoctorGitSnapshot {
        snapshot
    }
}

private struct StubNetworkProbe: CLIDoctorNetworkProbing {
    var result: CLIDoctorNetworkResult

    func probe(apiBaseURL: String, apiKey: String?) async -> CLIDoctorNetworkResult {
        result
    }
}
