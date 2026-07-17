import Foundation
import QuillCodeAgent
@testable import QuillCodeCLI
import QuillCodeCore
import QuillCodePersistence
import QuillCodeSafety
import XCTest

final class AppServerExperimentalFeatureTests: XCTestCase {
    func testListProjectsMetadataAndCodexPagination() async throws {
        let fixture = try await makeFixture()
        try await fixture.request(id: 1, method: "experimentalFeature/list", params: ["limit": 1])
        try await fixture.request(id: 2, method: "experimentalFeature/list", params: ["limit": 0])
        try await fixture.request(
            id: 3,
            method: "experimentalFeature/list",
            params: ["cursor": "1", "limit": 1]
        )
        try await fixture.request(
            id: 4,
            method: "experimentalFeature/list",
            params: ["cursor": "bad"]
        )
        try await fixture.request(
            id: 5,
            method: "experimentalFeature/list",
            params: ["cursor": "3"]
        )

        let records = try await fixture.output.records()
        let first = try XCTUnwrap(
            result(for: 1, in: records)?["data"]?.arrayValue?.first?.objectValue
        )
        XCTAssertEqual(first["name"]?.stringValue, "hooks")
        XCTAssertEqual(first["stage"]?.stringValue, "stable")
        XCTAssertEqual(first["displayName"], .null)
        XCTAssertEqual(first["description"], .null)
        XCTAssertEqual(first["announcement"], .null)
        XCTAssertEqual(first["enabled"]?.boolValue, true)
        XCTAssertEqual(first["defaultEnabled"]?.boolValue, true)
        XCTAssertEqual(result(for: 1, in: records)?["nextCursor"]?.stringValue, "1")
        XCTAssertEqual(
            result(for: 2, in: records)?["data"]?.arrayValue?.count,
            1,
            "limit=0 must advance by one item"
        )

        let memories = try XCTUnwrap(
            result(for: 3, in: records)?["data"]?.arrayValue?.first?.objectValue
        )
        XCTAssertEqual(memories["name"]?.stringValue, "memories")
        XCTAssertEqual(memories["stage"]?.stringValue, "beta")
        XCTAssertEqual(memories["displayName"]?.stringValue, "Memories")
        XCTAssertNotNil(memories["description"]?.stringValue)
        XCTAssertNotNil(memories["announcement"]?.stringValue)
        XCTAssertEqual(result(for: 3, in: records)?["nextCursor"], .null)
        XCTAssertEqual(errorCode(for: 4, in: records), -32_600)
        XCTAssertEqual(errorCode(for: 5, in: records), -32_600)
    }

    func testRuntimePatchFiltersKeysAndRespectsConfigPrecedence() async throws {
        let fixture = try await makeFixture()
        try await fixture.request(
            id: 1,
            method: "experimentalFeature/enablement/set",
            params: ["enablement": ["hooks": false, "memories": false, "unknown": true]]
        )
        try await fixture.request(id: 2, method: "experimentalFeature/list")
        try writeFile("[features]\nmemories = true\n", to: fixture.configFile)
        try await fixture.request(id: 3, method: "experimentalFeature/list")
        try await fixture.request(
            id: 4,
            method: "experimentalFeature/enablement/set",
            params: ["enablement": ["memories": "false"]]
        )
        try await fixture.request(
            id: 5,
            method: "experimentalFeature/enablement/set",
            params: [:]
        )

        let records = try await fixture.output.records()
        XCTAssertEqual(result(for: 1, in: records)?["enablement"], .object([
            "memories": .bool(false)
        ]))
        assertFeature("memories", enabled: false, responseID: 2, records: records)
        assertFeature("memories", enabled: true, responseID: 3, records: records)
        XCTAssertEqual(errorCode(for: 4, in: records), -32_600)
        XCTAssertEqual(errorCode(for: 5, in: records), -32_600)
    }

    func testRuntimePatchIsSharedAcrossSessions() async throws {
        let runtimeFeatureStore = AppServerRuntimeFeatureStore()
        let writer = try await makeFixture(runtimeFeatureStore: runtimeFeatureStore)
        let reader = try await makeFixture(runtimeFeatureStore: runtimeFeatureStore)

        try await writer.request(
            id: 1,
            method: "experimentalFeature/enablement/set",
            params: ["enablement": ["memories": false]]
        )
        try await reader.request(id: 2, method: "experimentalFeature/list")

        assertFeature(
            "memories",
            enabled: false,
            responseID: 2,
            records: try await reader.output.records()
        )
    }

    func testResolutionUsesThreadProjectCLIAndManagedPrecedence() async throws {
        let managedFile = try temporaryDirectory(prefix: "managed")
            .appendingPathComponent("requirements.toml")
        try writeFile("[features]\nmemories = true\n", to: managedFile)
        let fixture = try await makeFixture(
            featureEnablement: ["memories": false],
            managedRequirementFiles: [managedFile]
        )
        try writeFile("[features]\nmemories = false\n", to: fixture.configFile)
        let project = try temporaryDirectory(prefix: "project")
        try writeFile(
            "[features]\nmemories = false\n",
            to: project.appendingPathComponent(".quillcode/config.toml")
        )
        try await fixture.request(
            id: 1,
            method: "experimentalFeature/enablement/set",
            params: ["enablement": ["memories": false]]
        )
        try await fixture.request(
            id: 2,
            method: "thread/start",
            params: ["cwd": project.path]
        )
        var records = try await fixture.output.records()
        let threadID = try XCTUnwrap(
            result(for: 2, in: records)?["thread"]?.objectValue?["id"]?.stringValue
        )
        try await fixture.request(
            id: 3,
            method: "experimentalFeature/list",
            params: ["threadId": threadID]
        )
        try await fixture.request(
            id: 4,
            method: "experimentalFeature/list",
            params: ["threadId": UUID().uuidString.lowercased()]
        )

        records = try await fixture.output.records()
        assertFeature(
            "memories",
            enabled: true,
            responseID: 3,
            records: records,
            message: "managed requirements must win over CLI, config, and runtime state"
        )
        XCTAssertEqual(errorCode(for: 4, in: records), -32_600)
    }

    func testListRefreshesLoadedThreadProjectConfig() async throws {
        let fixture = try await makeFixture()
        try writeFile("[features]\nmemories = true\n", to: fixture.configFile)
        let project = try temporaryDirectory(prefix: "thread-project")
        let projectConfig = project.appendingPathComponent(".quillcode/config.toml")
        try writeFile("[features]\nmemories = false\n", to: projectConfig)
        try await fixture.request(
            id: 1,
            method: "thread/start",
            params: ["cwd": project.path]
        )
        var records = try await fixture.output.records()
        let threadID = try XCTUnwrap(
            result(for: 1, in: records)?["thread"]?.objectValue?["id"]?.stringValue
        )
        try await fixture.request(id: 2, method: "experimentalFeature/list")
        try await fixture.request(
            id: 3,
            method: "experimentalFeature/list",
            params: ["threadId": threadID]
        )
        try writeFile("[features]\nmemories = true\n", to: projectConfig)
        try await fixture.request(
            id: 4,
            method: "experimentalFeature/list",
            params: ["threadId": threadID]
        )

        records = try await fixture.output.records()
        assertFeature("memories", enabled: true, responseID: 2, records: records)
        assertFeature("memories", enabled: false, responseID: 3, records: records)
        assertFeature("memories", enabled: true, responseID: 4, records: records)
    }

    private func makeFixture(
        featureEnablement: [String: Bool] = [:],
        managedRequirementFiles: [URL] = [],
        runtimeFeatureStore: AppServerRuntimeFeatureStore = AppServerRuntimeFeatureStore()
    ) async throws -> ExperimentalFeatureFixture {
        let home = try temporaryDirectory(prefix: "home")
        let workspace = try temporaryDirectory(prefix: "workspace")
        let paths = QuillCodePaths(
            home: home,
            hookConfigurationPaths: HookConfigurationPaths(
                userQuillCodeDirectory: home,
                managedRequirementFiles: managedRequirementFiles
            )
        )
        try paths.ensure()
        let output = ExperimentalFeatureOutputCollector()
        let session = try AppServerSession(
            request: CLIAppServerRequest(
                live: false,
                home: home,
                featureEnablement: featureEnablement
            ),
            environment: [:],
            currentDirectory: workspace,
            runnerFactory: { configuration in
                AgentRunner(
                    llm: MockLLMClient(),
                    safety: StaticSafetyReviewer(),
                    maxToolSteps: configuration.appConfig.maxToolSteps
                )
            },
            paths: paths,
            runtimeFeatureStore: runtimeFeatureStore,
            sink: { line in await output.append(line) }
        )
        let fixture = ExperimentalFeatureFixture(
            session: session,
            output: output,
            configFile: paths.configFile
        )
        try await fixture.request(
            id: 100,
            method: "initialize",
            params: ["clientInfo": ["name": "FeatureTests", "version": "1"]]
        )
        try await fixture.notify(method: "initialized")
        return fixture
    }

    private func assertFeature(
        _ name: String,
        enabled: Bool,
        responseID: Int,
        records: [[String: CLIJSONValue]],
        message: String = ""
    ) {
        let actual = result(for: responseID, in: records)?["data"]?.arrayValue?
            .compactMap(\.objectValue)
            .first { $0["name"]?.stringValue == name }?["enabled"]?.boolValue
        XCTAssertEqual(actual, enabled, message)
    }

    private func result(
        for id: Int,
        in records: [[String: CLIJSONValue]]
    ) -> [String: CLIJSONValue]? {
        records.first { $0["id"]?.numberValue == Double(id) }?["result"]?.objectValue
    }

    private func errorCode(
        for id: Int,
        in records: [[String: CLIJSONValue]]
    ) -> Double? {
        let record = records.first { $0["id"]?.numberValue == Double(id) }
        return record?["error"]?.objectValue?["code"]?.numberValue
    }

    private func writeFile(_ value: String, to destination: URL) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try value.write(to: destination, atomically: true, encoding: .utf8)
    }

    private func temporaryDirectory(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "quillcode-app-server-feature-\(prefix)-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}

private struct ExperimentalFeatureFixture {
    let session: AppServerSession
    let output: ExperimentalFeatureOutputCollector
    let configFile: URL

    func request(
        id: Int,
        method: String,
        params: [String: Any] = [:]
    ) async throws {
        try await send(["id": id, "method": method, "params": params])
    }

    func notify(method: String, params: [String: Any] = [:]) async throws {
        try await send(["method": method, "params": params])
    }

    private func send(_ value: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        await session.receive(data)
    }
}

private actor ExperimentalFeatureOutputCollector {
    private var lines: [String] = []

    func append(_ line: String) {
        lines.append(line)
    }

    func records() throws -> [[String: CLIJSONValue]] {
        try lines.map { line in
            guard let record = try CLIJSONCodec.decode(line).objectValue else {
                throw ExperimentalFeatureTestError.invalidRecord
            }
            return record
        }
    }
}

private enum ExperimentalFeatureTestError: Error {
    case invalidRecord
}
