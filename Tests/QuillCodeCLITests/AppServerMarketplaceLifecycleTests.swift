import Foundation
import QuillCodeAgent
@testable import QuillCodeCLI
import QuillCodeCore
import QuillCodeSafety
import QuillCodeTools
import XCTest

final class AppServerMarketplaceLifecycleTests: XCTestCase {
    func testLocalMarketplaceAddIsIdempotentDiscoverableAndRemovable() async throws {
        let fixture = try await makeFixture()
        let source = fixture.workspace.appendingPathComponent("local-marketplace", isDirectory: true)
        try writeMarketplace(named: "local-tools", version: "1.0.0", in: source)

        try await fixture.request(id: 1, method: "marketplace/add", params: ["source": source.path])
        let addResult = try await fixture.result(id: 1)
        let added = try XCTUnwrap(addResult)
        XCTAssertEqual(added["marketplaceName"], .string("local-tools"))
        XCTAssertEqual(added["installedRoot"], .string(source.path))
        XCTAssertEqual(added["alreadyAdded"], .bool(false))

        try await fixture.request(id: 2, method: "marketplace/add", params: ["source": source.path])
        let duplicateResult = try await fixture.result(id: 2)
        XCTAssertEqual(duplicateResult?["alreadyAdded"], .bool(true))

        try await fixture.request(id: 3, method: "plugin/list")
        let names = try await marketplaceNames(in: fixture, responseID: 3)
        XCTAssertTrue(names.contains("local-tools"))

        try await fixture.request(
            id: 4,
            method: "marketplace/remove",
            params: ["marketplaceName": "local-tools"]
        )
        let removeResult = try await fixture.result(id: 4)
        let removed = try XCTUnwrap(removeResult)
        XCTAssertEqual(removed["marketplaceName"], .string("local-tools"))
        XCTAssertEqual(removed["installedRoot"], .null)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))

        try await fixture.request(id: 5, method: "plugin/list")
        let remainingNames = try await marketplaceNames(in: fixture, responseID: 5)
        XCTAssertFalse(remainingNames.contains("local-tools"))
    }

    func testGitMarketplaceAddUpgradeAndRemoveAreTransactional() async throws {
        let fixture = try await makeFixture()
        let source = fixture.workspace.appendingPathComponent("git-marketplace", isDirectory: true)
        try writeMarketplace(named: "git-tools", version: "1.0.0", in: source)
        try initializeGitRepository(at: source)

        try await fixture.request(
            id: 10,
            method: "marketplace/add",
            params: ["source": source.path, "refName": "main"]
        )
        let addResult = try await fixture.result(id: 10)
        let added = try XCTUnwrap(addResult)
        let installedRoot = try XCTUnwrap(added["installedRoot"]?.stringValue)
        XCTAssertEqual(added["marketplaceName"], .string("git-tools"))
        XCTAssertEqual(added["alreadyAdded"], .bool(false))
        XCTAssertTrue(FileManager.default.fileExists(atPath: installedRoot))
        XCTAssertEqual(try installedVersion(at: URL(fileURLWithPath: installedRoot)), "1.0.0")

        try writePackageVersion("2.0.0", in: source)
        try commitAll(in: source, message: "upgrade marketplace")
        try await fixture.request(
            id: 11,
            method: "marketplace/upgrade",
            params: ["marketplaceName": "git-tools"]
        )
        let upgradeResult = try await fixture.result(id: 11)
        let upgraded = try XCTUnwrap(upgradeResult)
        XCTAssertEqual(upgraded["selectedMarketplaces"], .array([.string("git-tools")]))
        XCTAssertEqual(upgraded["upgradedRoots"], .array([.string(installedRoot)]))
        XCTAssertEqual(upgraded["errors"], .array([]))
        XCTAssertEqual(try installedVersion(at: URL(fileURLWithPath: installedRoot)), "2.0.0")

        try await fixture.request(id: 12, method: "marketplace/upgrade")
        let unchangedResult = try await fixture.result(id: 12)
        let unchanged = try XCTUnwrap(unchangedResult)
        XCTAssertEqual(unchanged["selectedMarketplaces"], .array([.string("git-tools")]))
        XCTAssertEqual(unchanged["upgradedRoots"], .array([]))
        XCTAssertEqual(unchanged["errors"], .array([]))

        try await fixture.request(
            id: 13,
            method: "marketplace/remove",
            params: ["marketplaceName": "git-tools"]
        )
        let removeResult = try await fixture.result(id: 13)
        let removed = try XCTUnwrap(removeResult)
        XCTAssertEqual(removed["installedRoot"], .string(installedRoot))
        XCTAssertFalse(FileManager.default.fileExists(atPath: installedRoot))

        try await fixture.request(
            id: 14,
            method: "marketplace/upgrade",
            params: ["marketplaceName": "git-tools"]
        )
        let missingUpgradeCode = try await fixture.errorCode(id: 14)
        XCTAssertEqual(missingUpgradeCode, -32_600)
    }

    func testIdempotentGitAddRejectsDamagedInstalledCatalog() async throws {
        let fixture = try await makeFixture()
        let source = fixture.workspace.appendingPathComponent("damaged-source", isDirectory: true)
        try writeMarketplace(named: "damage-check", version: "1.0.0", in: source)
        try initializeGitRepository(at: source)

        try await fixture.request(
            id: 20,
            method: "marketplace/add",
            params: ["source": source.path, "refName": "main"]
        )
        let addResult = try await fixture.result(id: 20)
        let installedRoot = try XCTUnwrap(addResult?["installedRoot"]?.stringValue)
        try FileManager.default.removeItem(
            at: URL(fileURLWithPath: installedRoot)
                .appendingPathComponent(".agents/plugins/marketplace.json")
        )

        try await fixture.request(
            id: 21,
            method: "marketplace/add",
            params: ["source": source.path, "refName": "main"]
        )
        let damagedCode = try await fixture.errorCode(id: 21)
        let damagedMessage = try await fixture.errorMessage(id: 21)
        XCTAssertEqual(damagedCode, -32_600)
        XCTAssertTrue(damagedMessage?.contains("expected exactly one") == true)

        try await fixture.request(
            id: 22,
            method: "marketplace/upgrade",
            params: ["marketplaceName": "damage-check"]
        )
        let upgradeResult = try await fixture.result(id: 22)
        let upgrade = try XCTUnwrap(upgradeResult)
        XCTAssertEqual(upgrade["upgradedRoots"], .array([]))
        XCTAssertEqual(
            upgrade["errors"]?.arrayValue?.first?.objectValue?["marketplaceName"],
            .string("damage-check")
        )
        XCTAssertTrue(
            upgrade["errors"]?.arrayValue?.first?.objectValue?["message"]?
                .stringValue?.contains("expected exactly one") == true
        )
    }

    func testMarketplaceAddRejectsCatalogRenameAtConfiguredSource() async throws {
        let fixture = try await makeFixture()
        let source = fixture.workspace.appendingPathComponent("renamed-source", isDirectory: true)
        try writeMarketplace(named: "original-name", version: "1.0.0", in: source)

        try await fixture.request(
            id: 25,
            method: "marketplace/add",
            params: ["source": source.path]
        )
        try writeMarketplace(named: "replacement-name", version: "1.0.0", in: source)
        try await fixture.request(
            id: 26,
            method: "marketplace/add",
            params: ["source": source.path]
        )

        let code = try await fixture.errorCode(id: 26)
        let message = try await fixture.errorMessage(id: 26)
        XCTAssertEqual(code, -32_600)
        XCTAssertTrue(message?.contains("already configured as `original-name`") == true)
    }

    func testMarketplaceAddRejectsCredentialsAndUnsafeSparsePaths() async throws {
        let fixture = try await makeFixture()
        try await fixture.request(
            id: 30,
            method: "marketplace/add",
            params: ["source": "https://user:secret@example.com/tools.git"]
        )
        try await fixture.request(
            id: 31,
            method: "marketplace/add",
            params: ["source": "Lore-Hex/QuillCode", "sparsePaths": ["../escape"]]
        )
        let credentialsCode = try await fixture.errorCode(id: 30)
        let sparseCode = try await fixture.errorCode(id: 31)
        let credentialsMessage = try await fixture.errorMessage(id: 30)
        let sparseMessage = try await fixture.errorMessage(id: 31)
        XCTAssertEqual(credentialsCode, -32_600)
        XCTAssertEqual(sparseCode, -32_600)
        XCTAssertTrue(credentialsMessage?.contains("source must be") == true)
        XCTAssertTrue(sparseMessage?.contains("invalid sparse marketplace path") == true)
    }

    private func makeFixture() async throws -> MarketplaceLifecycleFixture {
        let home = try temporaryDirectory(prefix: "marketplace-home")
        let workspace = try temporaryDirectory(prefix: "marketplace-workspace")
        let output = MarketplaceLifecycleOutput()
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
        let fixture = MarketplaceLifecycleFixture(
            session: session,
            output: output,
            home: home,
            workspace: workspace
        )
        try await fixture.request(
            id: 100,
            method: "initialize",
            params: ["clientInfo": ["name": "MarketplaceTests", "version": "1"]]
        )
        try await fixture.notify(method: "initialized")
        return fixture
    }

    private func marketplaceNames(
        in fixture: MarketplaceLifecycleFixture,
        responseID: Int
    ) async throws -> [String] {
        let response = try await fixture.result(id: responseID)
        return try XCTUnwrap(response?["marketplaces"]?.arrayValue)
            .compactMap { $0.objectValue?["name"]?.stringValue }
    }

    private func writeMarketplace(named name: String, version: String, in root: URL) throws {
        let catalog = root.appendingPathComponent(".agents/plugins/marketplace.json")
        try FileManager.default.createDirectory(
            at: catalog.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try #"{"name":"\#(name)","plugins":[{"name":"smoke-plugin","source":"./catalog/smoke-plugin"}]}"#
            .write(to: catalog, atomically: true, encoding: .utf8)
        try writePackageVersion(version, in: root)
    }

    private func writePackageVersion(_ version: String, in root: URL) throws {
        let manifest = root.appendingPathComponent("catalog/smoke-plugin/.codex-plugin/plugin.json")
        try FileManager.default.createDirectory(
            at: manifest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try #"{"name":"smoke-plugin","version":"\#(version)"}"#
            .write(to: manifest, atomically: true, encoding: .utf8)
    }

    private func installedVersion(at root: URL) throws -> String? {
        let manifest = root.appendingPathComponent("catalog/smoke-plugin/.codex-plugin/plugin.json")
        let data = try Data(contentsOf: manifest)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["version"] as? String
    }

    private func initializeGitRepository(at root: URL) throws {
        try runGit(["init", "-b", "main"], in: root)
        try runGit(["config", "user.email", "marketplace@quillcode.local"], in: root)
        try runGit(["config", "user.name", "QuillCode Marketplace Tests"], in: root)
        try commitAll(in: root, message: "initial marketplace")
    }

    private func commitAll(in root: URL, message: String) throws {
        try runGit(["add", "."], in: root)
        try runGit(["commit", "-m", message], in: root)
    }

    private func runGit(_ arguments: [String], in root: URL) throws {
        let result = GitProcessRunner().runGit(arguments, cwd: root, timeoutSeconds: 10)
        guard result.ok else {
            throw MarketplaceLifecycleTestError.gitFailed(result.stderr)
        }
    }

    private func temporaryDirectory(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}

private struct MarketplaceLifecycleFixture {
    let session: AppServerSession
    let output: MarketplaceLifecycleOutput
    let home: URL
    let workspace: URL

    func request(id: Int, method: String, params: [String: Any] = [:]) async throws {
        try await send(["id": id, "method": method, "params": params])
    }

    func notify(method: String, params: [String: Any] = [:]) async throws {
        try await send(["method": method, "params": params])
    }

    func result(id: Int) async throws -> [String: CLIJSONValue]? {
        try await record(id: id)?["result"]?.objectValue
    }

    func errorCode(id: Int) async throws -> Double? {
        try await record(id: id)?["error"]?.objectValue?["code"]?.numberValue
    }

    func errorMessage(id: Int) async throws -> String? {
        try await record(id: id)?["error"]?.objectValue?["message"]?.stringValue
    }

    private func record(id: Int) async throws -> [String: CLIJSONValue]? {
        try await output.records().first { $0["id"]?.numberValue == Double(id) }
    }

    private func send(_ value: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        await session.receive(data)
    }
}

private actor MarketplaceLifecycleOutput {
    private var lines: [String] = []

    func append(_ line: String) {
        lines.append(line)
    }

    func records() throws -> [[String: CLIJSONValue]] {
        try lines.map { line in
            guard let record = try CLIJSONCodec.decode(line).objectValue else {
                throw MarketplaceLifecycleTestError.invalidRecord
            }
            return record
        }
    }
}

private enum MarketplaceLifecycleTestError: Error {
    case gitFailed(String)
    case invalidRecord
}
