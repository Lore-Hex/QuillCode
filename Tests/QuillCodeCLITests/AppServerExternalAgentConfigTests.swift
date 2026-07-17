import Foundation
import QuillCodeAgent
@testable import QuillCodeCLI
import QuillCodeCore
import QuillCodePersistence
import QuillCodeSafety
import XCTest

final class AppServerExternalAgentConfigTests: XCTestCase {
    func testRequestParsingRejectsRelativeAndNULPaths() throws {
        XCTAssertThrowsError(try AppServerExternalAgentConfigDetectRequest(.object([
            "cwds": .array([.string("relative/path")]),
        ])))
        XCTAssertThrowsError(try AppServerExternalAgentConfigDetectRequest(.object([
            "cwds": .array([.string("/tmp/unsafe\0path")]),
        ])))

        let relativeSession = ExternalAgentConfigMigrationItem(
            itemType: .sessions,
            description: "Import sessions",
            details: .init(sessions: [.init(path: "relative.jsonl", cwd: "")])
        )
        XCTAssertThrowsError(try AppServerExternalAgentConfigImportRequest(.object([
            "migrationItems": .array([relativeSession.appServerJSONValue]),
        ])))
    }

    func testDetectDefaultsEmptyAndScopesHomeAndRepository() async throws {
        let fixture = try await makeFixture()
        try fixture.write(#"{"sandbox":{"enabled":true}}"#, to: fixture.sourceHomeSettings)
        try fixture.write("ref: refs/heads/main\n", to: fixture.workspace.appendingPathComponent(".git/HEAD"))
        try fixture.write(
            #"{"sandbox":{"enabled":true}}"#,
            to: fixture.workspace.appendingPathComponent(".claude/settings.json")
        )

        try await fixture.request(id: 1, method: "externalAgentConfig/detect")
        var records = try await fixture.output.records()
        XCTAssertEqual(try items(responseID: 1, records: records), [])

        try await fixture.request(
            id: 2,
            method: "externalAgentConfig/detect",
            params: .object(["includeHome": .bool(true)])
        )
        records = try await fixture.output.records()
        let homeItems = try items(responseID: 2, records: records)
        XCTAssertEqual(homeItems.map { $0["itemType"]?.stringValue }, ["CONFIG"])
        XCTAssertEqual(homeItems[0]["cwd"], .null)
        XCTAssertEqual(homeItems[0]["details"], .null)

        let nested = fixture.workspace.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try await fixture.request(
            id: 3,
            method: "externalAgentConfig/detect",
            params: .object(["cwds": .array([.string(nested.path)])])
        )
        records = try await fixture.output.records()
        let projectItems = try items(responseID: 3, records: records)
        XCTAssertEqual(projectItems.map { $0["itemType"]?.stringValue }, ["CONFIG"])
        XCTAssertEqual(
            projectItems[0]["cwd"]?.stringValue,
            fixture.workspace.standardizedFileURL.resolvingSymlinksInPath().path
        )
    }

    func testEmptyImportReturnsIDWithoutNotificationsOrHistory() async throws {
        let fixture = try await makeFixture()

        try await fixture.request(
            id: 1,
            method: "externalAgentConfig/import",
            params: .object(["migrationItems": .array([])])
        )
        await fixture.session.waitForActiveTurns()

        let records = try await fixture.output.records()
        XCTAssertNotNil(records.first { $0["id"]?.numberValue == 1 }?["result"]?
            .objectValue?["importId"]?.stringValue)
        XCTAssertFalse(records.contains { $0["method"]?.stringValue?.hasPrefix(
            "externalAgentConfig/import/"
        ) == true })

        try await fixture.request(id: 2, method: "externalAgentConfig/import/readHistories")
        let historyResult = try await fixture.output.result(id: 2)
        XCTAssertEqual(historyResult?["data"]?.arrayValue, [])
    }

    func testImportRespondsBeforeProgressContinuesAfterFailureAndPersistsHistory() async throws {
        let fixture = try await makeFixture()
        try fixture.write(#"{"sandbox":{"enabled":true}}"#, to: fixture.sourceHomeSettings)
        try fixture.write(
            "---\nname: explain\ndescription: Explain code\n---\n",
            to: fixture.sourceHome.appendingPathComponent(".claude/skills/explain/SKILL.md")
        )

        try await fixture.request(
            id: 1,
            method: "externalAgentConfig/detect",
            params: .object(["includeHome": .bool(true)])
        )
        let detected = try items(responseID: 1, records: await fixture.output.records())
        let skill = try XCTUnwrap(detected.first { $0["itemType"]?.stringValue == "SKILLS" })
        var forgedConfig = try XCTUnwrap(
            detected.first { $0["itemType"]?.stringValue == "CONFIG" }
        )
        forgedConfig["cwd"] = .string(fixture.workspace.path)

        try await fixture.request(
            id: 2,
            method: "externalAgentConfig/import",
            params: .object([
                "migrationItems": .array([.object(skill), .object(forgedConfig)]),
                "source": .string("claude-code"),
            ])
        )
        await fixture.session.waitForActiveTurns()

        let records = try await fixture.output.records()
        let responseIndex = try XCTUnwrap(records.firstIndex { $0["id"]?.numberValue == 2 })
        let progressIndices = records.indices.filter {
            records[$0]["method"]?.stringValue == "externalAgentConfig/import/progress"
        }
        let completionIndex = try XCTUnwrap(records.firstIndex {
            $0["method"]?.stringValue == "externalAgentConfig/import/completed"
        })
        XCTAssertEqual(progressIndices.count, 2)
        XCTAssertLessThan(responseIndex, try XCTUnwrap(progressIndices.first))
        XCTAssertLessThan(try XCTUnwrap(progressIndices.last), completionIndex)

        let importID = try XCTUnwrap(
            records[responseIndex]["result"]?.objectValue?["importId"]?.stringValue
        )
        let progressTypes = try progressIndices.map { index in
            try XCTUnwrap(records[index]["params"]?.objectValue?["itemTypeResults"]?.arrayValue?.first?
                .objectValue?["itemType"]?.stringValue)
        }
        XCTAssertEqual(progressTypes, ["SKILLS", "CONFIG"])

        let completed = try XCTUnwrap(records[completionIndex]["params"]?.objectValue)
        XCTAssertEqual(completed["importId"]?.stringValue, importID)
        let grouped = try XCTUnwrap(completed["itemTypeResults"]?.arrayValue)
        XCTAssertEqual(
            grouped.compactMap { $0.objectValue?["itemType"]?.stringValue },
            ["CONFIG", "SKILLS"]
        )
        XCTAssertEqual(grouped[0].objectValue?["failures"]?.arrayValue?.count, 1)
        XCTAssertEqual(grouped[1].objectValue?["successes"]?.arrayValue?.count, 1)

        let reloaded = try await makeSession(
            appHome: fixture.appHome,
            sourceHome: fixture.sourceHome,
            workspace: fixture.workspace
        )
        try await reloaded.request(
            id: 3,
            method: "externalAgentConfig/import/readHistories"
        )
        let historyResult = try await reloaded.output.result(id: 3)
        let histories = try XCTUnwrap(historyResult?["data"]?.arrayValue)
        XCTAssertEqual(histories.count, 1)
        XCTAssertEqual(histories[0].objectValue?["importId"]?.stringValue, importID)
        XCTAssertEqual(histories[0].objectValue?["successes"]?.arrayValue?.count, 1)
        XCTAssertEqual(histories[0].objectValue?["failures"]?.arrayValue?.count, 1)
    }

    func testSessionImportCreatesDurableProjectThreadAndSuppressesRedetection() async throws {
        let fixture = try await makeFixture()
        let transcript = fixture.sourceHome.appendingPathComponent(
            ".claude/projects/workspace/session-1.jsonl"
        )
        try fixture.write(
            "{\"sessionId\":\"session-1\","
                + "\"timestamp\":\"2026-07-16T12:00:00Z\",\"type\":\"user\","
                + "\"message\":{\"role\":\"user\",\"content\":\"Repair the build\"}}\n",
            to: transcript
        )

        try await fixture.request(
            id: 1,
            method: "externalAgentConfig/detect",
            params: .object(["includeHome": .bool(true)])
        )
        let detected = try items(responseID: 1, records: await fixture.output.records())
        let sessions = try XCTUnwrap(
            detected.first { $0["itemType"]?.stringValue == "SESSIONS" }
        )
        try await fixture.request(
            id: 2,
            method: "externalAgentConfig/import",
            params: .object(["migrationItems": .array([.object(sessions)])])
        )
        await fixture.session.waitForActiveTurns()

        let threads = try JSONThreadStore(directory: fixture.paths.threadsDirectory).list()
        let thread = try XCTUnwrap(threads.first)
        XCTAssertEqual(thread.title, "Repair the build")
        XCTAssertEqual(thread.messages.first?.content, "Repair the build")
        let projects = try JSONProjectStore(fileURL: fixture.paths.projectsFile).load()
        XCTAssertEqual(projects.first?.path, fixture.workspace.path)
        XCTAssertEqual(thread.projectID, projects.first?.id)

        try await fixture.request(
            id: 3,
            method: "externalAgentConfig/detect",
            params: .object(["includeHome": .bool(true)])
        )
        let remaining = try items(responseID: 3, records: await fixture.output.records())
        XCTAssertFalse(remaining.contains { $0["itemType"]?.stringValue == "SESSIONS" })
    }

    func testEndOfInputCancelsImportBeforeProgressOrCompletion() async throws {
        let fixture = try await makeFixture()
        try fixture.write(#"{"sandbox":{"enabled":true}}"#, to: fixture.sourceHomeSettings)
        let item = ExternalAgentConfigMigrationItem(
            itemType: .config,
            description: "Migrate Claude Code settings"
        )
        let launch = try await fixture.session.prepareExternalAgentConfigImport(.object([
            "migrationItems": .array([item.appServerJSONValue]),
        ]))

        await fixture.session.finishInput()
        await fixture.session.launchExternalAgentConfigImport(launch)
        await fixture.session.waitForActiveTurns()

        let methods = try await fixture.output.records().compactMap { $0["method"]?.stringValue }
        XCTAssertFalse(methods.contains("externalAgentConfig/import/progress"))
        XCTAssertFalse(methods.contains("externalAgentConfig/import/completed"))
    }
}

private extension AppServerExternalAgentConfigTests {
    func makeFixture() async throws -> ExternalAgentConfigAppServerFixture {
        let root = try temporaryDirectory()
        let appHome = root.appendingPathComponent("quillcode-home")
        let sourceHome = root.appendingPathComponent("source-home")
        let workspace = root.appendingPathComponent("workspace")
        try FileManager.default.createDirectory(at: sourceHome, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        return try await makeSession(
            appHome: appHome,
            sourceHome: sourceHome,
            workspace: workspace,
            root: root
        )
    }

    func makeSession(
        appHome: URL,
        sourceHome: URL,
        workspace: URL,
        root: URL? = nil
    ) async throws -> ExternalAgentConfigAppServerFixture {
        let paths = QuillCodePaths(home: appHome)
        try paths.ensure()
        let output = ExternalAgentConfigOutputCollector()
        let session = try AppServerSession(
            request: CLIAppServerRequest(live: false, home: appHome),
            environment: ["HOME": sourceHome.path],
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
        let fixture = ExternalAgentConfigAppServerFixture(
            session: session,
            output: output,
            root: root ?? appHome.deletingLastPathComponent(),
            appHome: appHome,
            sourceHome: sourceHome,
            workspace: workspace,
            paths: paths
        )
        try await fixture.request(
            id: 100,
            method: "initialize",
            params: .object([
                "clientInfo": .object([
                    "name": .string("ExternalAgentConfigTests"),
                    "version": .string("1"),
                ]),
            ])
        )
        try await fixture.notify(method: "initialized")
        await output.removeAll()
        return fixture
    }

    func items(
        responseID: Int,
        records: [[String: CLIJSONValue]]
    ) throws -> [[String: CLIJSONValue]] {
        let response = try XCTUnwrap(
            records.first { $0["id"]?.numberValue == Double(responseID) }
        )
        return try XCTUnwrap(response["result"]?.objectValue?["items"]?.arrayValue).map {
            try XCTUnwrap($0.objectValue)
        }
    }

    func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "quillcode-external-agent-app-server-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

private struct ExternalAgentConfigAppServerFixture {
    let session: AppServerSession
    let output: ExternalAgentConfigOutputCollector
    let root: URL
    let appHome: URL
    let sourceHome: URL
    let workspace: URL
    let paths: QuillCodePaths

    var sourceHomeSettings: URL {
        sourceHome.appendingPathComponent(".claude/settings.json")
    }

    func request(
        id: Int,
        method: String,
        params: CLIJSONValue = .object([:])
    ) async throws {
        await session.receive(try CLIJSONCodec.encode(.object([
            "id": .number(Double(id)),
            "method": .string(method),
            "params": params,
        ])))
    }

    func notify(method: String, params: CLIJSONValue = .object([:])) async throws {
        await session.receive(try CLIJSONCodec.encode(.object([
            "method": .string(method),
            "params": params,
        ])))
    }

    func write(_ contents: String, to file: URL) throws {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: file, atomically: true, encoding: .utf8)
    }
}

private actor ExternalAgentConfigOutputCollector {
    private var lines: [String] = []

    func append(_ line: String) {
        lines.append(line)
    }

    func removeAll() {
        lines.removeAll(keepingCapacity: true)
    }

    func records() throws -> [[String: CLIJSONValue]] {
        try lines.map { line in
            guard let object = try CLIJSONCodec.decode(line).objectValue else {
                throw ExternalAgentConfigTestError.invalidRecord
            }
            return object
        }
    }

    func result(id: Int) throws -> [String: CLIJSONValue]? {
        try records().first { $0["id"]?.numberValue == Double(id) }?["result"]?.objectValue
    }
}

private enum ExternalAgentConfigTestError: Error {
    case invalidRecord
}
