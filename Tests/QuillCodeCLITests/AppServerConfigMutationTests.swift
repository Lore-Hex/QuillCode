import Foundation
import QuillCodeAgent
@testable import QuillCodeCLI
import QuillCodeCore
import QuillCodePersistence
import QuillCodeSafety
import XCTest

final class AppServerConfigMutationTests: XCTestCase {
    func testValueWriteReplacesValueAndReadReturnsMatchingVersionAndOrigin() async throws {
        let fixture = try await makeSession(initialConfig: "model = \"trustedrouter/old\"\n")

        try await fixture.request(id: 1, method: "config/read")
        var records = try await fixture.output.records()
        let original = try XCTUnwrap(result(for: 1, in: records))
        XCTAssertNil(original["layers"])
        let version = try XCTUnwrap(
            original["origins"]?.objectValue?["model"]?.objectValue?["version"]?.stringValue
        )

        try await fixture.request(id: 2, method: "config/value/write", params: [
            "keyPath": "model",
            "value": "trustedrouter/new",
            "mergeStrategy": "replace",
            "expectedVersion": version
        ])
        try await fixture.request(id: 3, method: "config/read", params: ["includeLayers": true])

        records = try await fixture.output.records()
        let write = try XCTUnwrap(result(for: 2, in: records))
        XCTAssertEqual(write["status"]?.stringValue, "ok")
        XCTAssertEqual(write["filePath"]?.stringValue, fixture.configFile.path)
        XCTAssertEqual(write["overriddenMetadata"], .null)
        XCTAssertTrue(write["version"]?.stringValue?.hasPrefix("sha256:") == true)

        let read = try XCTUnwrap(result(for: 3, in: records))
        XCTAssertEqual(read["config"]?.objectValue?["model"]?.stringValue, "trustedrouter/new")
        XCTAssertEqual(
            read["origins"]?.objectValue?["model"]?.objectValue?["version"],
            write["version"]
        )
        let layer = try XCTUnwrap(read["layers"]?.arrayValue?.first?.objectValue)
        XCTAssertEqual(layer["config"]?.objectValue?["model"]?.stringValue, "trustedrouter/new")
        XCTAssertEqual(layer["version"], write["version"])
    }

    func testBatchWriteIsAtomicAndSupportsUpsertQuotedPathsAndDeletion() async throws {
        let fixture = try await makeSession(initialConfig: """
        [desktop.workspace]
        collapsed = false
        width = 280
        tabs = ["one"]

        [plugins."sample.catalog"]
        enabled = false
        """)

        try await fixture.request(id: 1, method: "config/batchWrite", params: [
            "edits": [
                [
                    "keyPath": "desktop.workspace",
                    "value": ["collapsed": true, "tabs": ["two"]],
                    "mergeStrategy": "upsert"
                ],
                [
                    "keyPath": "plugins.\"sample.catalog\".enabled",
                    "value": true,
                    "mergeStrategy": "replace"
                ],
                [
                    "keyPath": "desktop.workspace.width",
                    "value": NSNull(),
                    "mergeStrategy": "replace"
                ]
            ],
            "reloadUserConfig": true
        ])
        try await fixture.request(id: 2, method: "config/read")

        let records = try await fixture.output.records()
        XCTAssertEqual(result(for: 1, in: records)?["status"]?.stringValue, "ok")
        let config = try XCTUnwrap(result(for: 2, in: records)?["config"]?.objectValue)
        let workspace = try XCTUnwrap(config["desktop"]?.objectValue?["workspace"]?.objectValue)
        XCTAssertEqual(workspace["collapsed"]?.boolValue, true)
        XCTAssertEqual(workspace["tabs"]?.arrayValue, [.string("two")])
        XCTAssertNil(workspace["width"])
        XCTAssertEqual(
            config["plugins"]?.objectValue?["sample.catalog"]?.objectValue?["enabled"]?.boolValue,
            true
        )
    }

    func testVersionConflictAndReadonlyLayerReturnCodexErrorCodesWithoutWriting() async throws {
        let fixture = try await makeSession(initialConfig: "model = \"trustedrouter/old\"\n")
        try await fixture.request(id: 1, method: "config/read")
        var records = try await fixture.output.records()
        let version = try XCTUnwrap(
            result(for: 1, in: records)?["origins"]?.objectValue?["model"]?
                .objectValue?["version"]?.stringValue
        )

        try "model = \"trustedrouter/external\"\n".write(
            to: fixture.configFile,
            atomically: true,
            encoding: .utf8
        )
        try await fixture.request(id: 2, method: "config/value/write", params: [
            "keyPath": "model",
            "value": "trustedrouter/stale",
            "mergeStrategy": "replace",
            "expectedVersion": version
        ])
        try await fixture.request(id: 3, method: "config/value/write", params: [
            "keyPath": "model",
            "value": "trustedrouter/other",
            "mergeStrategy": "replace",
            "filePath": fixture.home.appendingPathComponent("other.toml").path
        ])

        records = try await fixture.output.records()
        XCTAssertEqual(configWriteErrorCode(for: 2, in: records), "configVersionConflict")
        XCTAssertEqual(configWriteErrorCode(for: 3, in: records), "configLayerReadonly")
        XCTAssertEqual(
            try ConfigDocumentStore(fileURL: fixture.configFile).load().values["model"],
            .string("trustedrouter/external")
        )
    }

    func testBatchRejectsLegacyProfilesAndLeavesEveryEditUnapplied() async throws {
        let fixture = try await makeSession(initialConfig: """
        [profiles."team.prod"]
        model = "trustedrouter/old"
        """)

        try await fixture.request(id: 1, method: "config/batchWrite", params: [
            "edits": [
                [
                    "keyPath": "items.sample.enabled",
                    "value": true,
                    "mergeStrategy": "replace"
                ],
                [
                    "keyPath": "profiles.\"team.prod\".model",
                    "value": "trustedrouter/new",
                    "mergeStrategy": "replace"
                ]
            ]
        ])

        let records = try await fixture.output.records()
        XCTAssertEqual(configWriteErrorCode(for: 1, in: records), "configValidationError")
        let document = try ConfigDocumentStore(fileURL: fixture.configFile).load()
        XCTAssertNil(document.values["items"])
        XCTAssertEqual(
            document.value(at: try ConfigKeyPath("profiles.\"team.prod\".model")),
            .string("trustedrouter/old")
        )
    }

    func testValidationRejectsMalformedPathsNestedNullAndInvalidKnownValues() async throws {
        let fixture = try await makeSession(initialConfig: "model = \"trustedrouter/original\"\n")

        try await fixture.request(id: 1, method: "config/value/write", params: [
            "keyPath": "desktop..theme",
            "value": "dark",
            "mergeStrategy": "replace"
        ])
        try await fixture.request(id: 2, method: "config/value/write", params: [
            "keyPath": "desktop",
            "value": ["theme": NSNull()],
            "mergeStrategy": "replace"
        ])
        try await fixture.request(id: 3, method: "config/value/write", params: [
            "keyPath": "mode",
            "value": "unbounded",
            "mergeStrategy": "replace"
        ])

        let records = try await fixture.output.records()
        for id in 1...3 {
            XCTAssertEqual(configWriteErrorCode(for: id, in: records), "configValidationError")
        }
        let document = try ConfigDocumentStore(fileURL: fixture.configFile).load()
        XCTAssertEqual(document.values["model"], .string("trustedrouter/original"))
        XCTAssertNil(document.values["desktop"])
        XCTAssertNil(document.values["mode"])
    }

    func testNoOpWritePreservesOriginalBytesAndRuntimeConfigReloadsAfterChange() async throws {
        let source = "# keep this comment\nmax_tool_steps = 42\n"
        let fixture = try await makeSession(initialConfig: source)

        try await fixture.request(id: 1, method: "config/value/write", params: [
            "keyPath": "max_tool_steps",
            "value": 42,
            "mergeStrategy": "replace"
        ])
        XCTAssertEqual(try String(contentsOf: fixture.configFile, encoding: .utf8), source)

        try await fixture.request(id: 2, method: "config/value/write", params: [
            "keyPath": "max_tool_steps",
            "value": 96,
            "mergeStrategy": "replace"
        ])
        let reloaded = await fixture.session.appConfig
        XCTAssertEqual(reloaded.maxToolSteps, 96)
    }

    func testWritePreservesTOMLTemporalValuesAndReadProjectsThemAsJSONStrings() async throws {
        let fixture = try await makeSession(initialConfig: """
        model = "trustedrouter/fast"
        release_at = 1979-05-27T07:32:00-08:00
        local_build_at = 1979-05-27T07:32:00.123
        release_day = 1979-05-27
        maintenance_time = 07:32:00.123
        """)

        try await fixture.request(id: 1, method: "config/value/write", params: [
            "keyPath": "desktop.theme",
            "value": "dark",
            "mergeStrategy": "replace"
        ])
        try await fixture.request(id: 2, method: "config/read", params: ["includeLayers": true])

        let records = try await fixture.output.records()
        XCTAssertEqual(result(for: 1, in: records)?["status"]?.stringValue, "ok")
        let config = try XCTUnwrap(result(for: 2, in: records)?["config"]?.objectValue)
        XCTAssertEqual(config["release_at"]?.stringValue, "1979-05-27T15:32:00.000Z")
        XCTAssertEqual(config["local_build_at"]?.stringValue, "1979-05-27T07:32:00.123")
        XCTAssertEqual(config["release_day"]?.stringValue, "1979-05-27")
        XCTAssertEqual(config["maintenance_time"]?.stringValue, "07:32:00.123")

        let layer = try XCTUnwrap(
            result(for: 2, in: records)?["layers"]?.arrayValue?.first?.objectValue?["config"]?
                .objectValue
        )
        XCTAssertEqual(layer["release_day"]?.stringValue, "1979-05-27")
        let persisted = try ConfigDocumentStore(fileURL: fixture.configFile).load()
        XCTAssertEqual(persisted.values["maintenance_time"]?.temporalStringValue, "07:32:00.123")
    }

    func testWritePreservesSpecialTOMLFloatsAndReadKeepsJSONFinite() async throws {
        let fixture = try await makeSession(initialConfig: """
        positive = inf
        negative = -inf
        undefined = nan
        """)

        try await fixture.request(id: 1, method: "config/value/write", params: [
            "keyPath": "desktop.theme",
            "value": "dark",
            "mergeStrategy": "replace"
        ])
        try await fixture.request(id: 2, method: "config/read", params: ["includeLayers": true])

        let records = try await fixture.output.records()
        XCTAssertEqual(result(for: 1, in: records)?["status"]?.stringValue, "ok")
        let config = try XCTUnwrap(result(for: 2, in: records)?["config"]?.objectValue)
        XCTAssertEqual(config["positive"]?.stringValue, "inf")
        XCTAssertEqual(config["negative"]?.stringValue, "-inf")
        XCTAssertEqual(config["undefined"]?.stringValue, "nan")

        let persisted = try ConfigDocumentStore(fileURL: fixture.configFile).load()
        XCTAssertEqual(persisted.values["undefined"]?.nonFiniteNumberStringValue, "nan")
    }

    private func makeSession(initialConfig: String) async throws -> ConfigMutationFixture {
        let home = try temporaryDirectory(prefix: "config-home")
        let workspace = try temporaryDirectory(prefix: "config-workspace")
        let paths = QuillCodePaths(home: home)
        try paths.ensure()
        try initialConfig.write(to: paths.configFile, atomically: true, encoding: .utf8)

        let output = ConfigMutationOutputCollector()
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
        let fixture = ConfigMutationFixture(
            session: session,
            output: output,
            home: home,
            configFile: paths.configFile
        )
        try await fixture.request(
            id: 100,
            method: "initialize",
            params: ["clientInfo": ["name": "ConfigMutationTests", "version": "1"]]
        )
        try await fixture.notify(method: "initialized")
        return fixture
    }

    private func result(
        for id: Int,
        in records: [[String: CLIJSONValue]]
    ) -> [String: CLIJSONValue]? {
        records.first { $0["id"]?.numberValue == Double(id) }?["result"]?.objectValue
    }

    private func configWriteErrorCode(
        for id: Int,
        in records: [[String: CLIJSONValue]]
    ) -> String? {
        records.first { $0["id"]?.numberValue == Double(id) }?["error"]?
            .objectValue?["data"]?.objectValue?["config_write_error_code"]?.stringValue
    }

    private func temporaryDirectory(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}

private struct ConfigMutationFixture {
    let session: AppServerSession
    let output: ConfigMutationOutputCollector
    let home: URL
    let configFile: URL

    func request(id: Int, method: String, params: [String: Any] = [:]) async throws {
        try await send(["id": id, "method": method, "params": params])
    }

    func notify(method: String, params: [String: Any] = [:]) async throws {
        try await send(["method": method, "params": params])
    }

    private func send(_ value: [String: Any]) async throws {
        await session.receive(try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]))
    }
}

private actor ConfigMutationOutputCollector {
    private var lines: [String] = []

    func append(_ line: String) {
        lines.append(line)
    }

    func records() throws -> [[String: CLIJSONValue]] {
        try lines.map { line in
            guard let object = try CLIJSONCodec.decode(line).objectValue else {
                throw ConfigMutationTestError.invalidRecord
            }
            return object
        }
    }
}

private enum ConfigMutationTestError: Error {
    case invalidRecord
}
