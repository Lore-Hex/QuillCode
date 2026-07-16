import Foundation
import QuillCodeAgent
@testable import QuillCodeCLI
import QuillCodeCore
import QuillCodeSafety
import XCTest

final class AppServerFuzzyFileSearchTests: XCTestCase {
    func testPathMatcherMatchesCodexScoresIndicesAndCaseInsensitivity() throws {
        XCTAssertEqual(
            AppServerFuzzyPathMatcher.match(query: "abe", path: "abexy"),
            .init(score: 84, indices: [0, 1, 2])
        )
        XCTAssertEqual(
            AppServerFuzzyPathMatcher.match(query: "abe", path: "sub/abce"),
            .init(score: 72, indices: [4, 5, 7])
        )
        XCTAssertEqual(
            AppServerFuzzyPathMatcher.match(query: "ABE", path: "abcde"),
            .init(score: 71, indices: [0, 1, 4])
        )
        XCTAssertNil(AppServerFuzzyPathMatcher.match(query: "missing", path: "abcde"))
    }

    func testOneShotSearchMatchesCodexWireShapeAndOrdering() async throws {
        let fixture = try await makeFixture()
        try writeSearchFixture(to: fixture.workspace)

        try await sendRequest(
            id: 2,
            method: "fuzzyFileSearch",
            params: ["query": "abe", "roots": [fixture.workspace.path]],
            to: fixture.session
        )

        let response = try await waitForResponse(id: 2, output: fixture.output)
        let files = try XCTUnwrap(response["result"]?.objectValue?["files"]?.arrayValue)
        XCTAssertEqual(files.count, 3)
        XCTAssertEqual(files.compactMap { $0.objectValue?["path"]?.stringValue }, [
            "abexy", "sub/abce", "abcde"
        ])
        XCTAssertEqual(files.compactMap { $0.objectValue?["score"]?.numberValue }, [84, 72, 71])
        XCTAssertEqual(
            files[1].objectValue?["indices"]?.arrayValue?.compactMap(\.numberValue),
            [4, 5, 7]
        )
        XCTAssertTrue(files.allSatisfy {
            $0.objectValue?["root"]?.stringValue == fixture.workspace.path
                && $0.objectValue?["match_type"]?.stringValue == "file"
                && $0.objectValue?["file_name"]?.stringValue != nil
        })
    }

    func testCancellationTokenSupersedesWorkWithoutStrandingEitherResponse() async throws {
        let fixture = try await makeFixture()
        for index in 0..<2_000 {
            try "contents".write(
                to: fixture.workspace.appendingPathComponent("alpha-\(index).txt"),
                atomically: true,
                encoding: .utf8
            )
        }

        let params: [String: Any] = [
            "query": "alpha",
            "roots": [fixture.workspace.path],
            "cancellationToken": "composer-search"
        ]
        try await sendRequest(id: 2, method: "fuzzyFileSearch", params: params, to: fixture.session)
        try await sendRequest(id: 3, method: "fuzzyFileSearch", params: params, to: fixture.session)

        _ = try await waitForResponse(id: 2, output: fixture.output)
        let second = try await waitForResponse(id: 3, output: fixture.output)
        XCTAssertEqual(try XCTUnwrap(second["result"]?.objectValue?["files"]?.arrayValue).count, 50)
    }

    func testSessionStreamsUpdatesCompletesAndClearsQuery() async throws {
        let fixture = try await makeFixture()
        try "contents".write(
            to: fixture.workspace.appendingPathComponent("alpha.txt"),
            atomically: true,
            encoding: .utf8
        )

        try await sendRequest(
            id: 2,
            method: "fuzzyFileSearch/sessionStart",
            params: ["sessionId": "composer", "roots": [fixture.workspace.path]],
            to: fixture.session
        )
        try await sendRequest(
            id: 3,
            method: "fuzzyFileSearch/sessionUpdate",
            params: ["sessionId": "composer", "query": "ALP"],
            to: fixture.session
        )

        let first = try await waitForNotification(
            method: "fuzzyFileSearch/sessionUpdated",
            count: 1,
            output: fixture.output
        ).last
        let firstParams = try XCTUnwrap(first?["params"]?.objectValue)
        XCTAssertEqual(firstParams["sessionId"]?.stringValue, "composer")
        XCTAssertEqual(firstParams["query"]?.stringValue, "ALP")
        XCTAssertEqual(firstParams["files"]?.arrayValue?.first?.objectValue?["path"]?.stringValue, "alpha.txt")
        _ = try await waitForNotification(
            method: "fuzzyFileSearch/sessionCompleted",
            count: 1,
            output: fixture.output
        )

        try await sendRequest(
            id: 4,
            method: "fuzzyFileSearch/sessionUpdate",
            params: ["sessionId": "composer", "query": ""],
            to: fixture.session
        )
        let records = try await waitForNotification(
            method: "fuzzyFileSearch/sessionUpdated",
            count: 2,
            output: fixture.output
        )
        let cleared = try XCTUnwrap(records.last?["params"]?.objectValue)
        XCTAssertEqual(cleared["query"]?.stringValue, "")
        XCTAssertEqual(cleared["files"]?.arrayValue, [])
    }

    func testSessionStopPreventsFurtherUpdatesAndMissingSessionUsesCodexError() async throws {
        let fixture = try await makeFixture()
        try await sendRequest(
            id: 2,
            method: "fuzzyFileSearch/sessionStart",
            params: ["sessionId": "stopped", "roots": [fixture.workspace.path]],
            to: fixture.session
        )
        try await sendRequest(
            id: 3,
            method: "fuzzyFileSearch/sessionStop",
            params: ["sessionId": "stopped"],
            to: fixture.session
        )
        try await sendRequest(
            id: 4,
            method: "fuzzyFileSearch/sessionUpdate",
            params: ["sessionId": "stopped", "query": "alp"],
            to: fixture.session
        )

        let response = try await waitForResponse(id: 4, output: fixture.output)
        XCTAssertEqual(response["error"]?.objectValue?["code"]?.numberValue, -32_600)
        XCTAssertEqual(
            response["error"]?.objectValue?["message"]?.stringValue,
            "fuzzy file search session not found: stopped"
        )
        try await Task.sleep(nanoseconds: 100_000_000)
        let records = try await fixture.output.records()
        XCTAssertFalse(records.contains { record in
            record["method"]?.stringValue == "fuzzyFileSearch/sessionUpdated"
                && record["params"]?.objectValue?["sessionId"]?.stringValue == "stopped"
        })
    }

    func testTwoSessionsKeepRootsAndQueriesIndependent() async throws {
        let fixture = try await makeFixture()
        let secondRoot = try temporaryDirectory(prefix: "app-server-fuzzy-second-root")
        try "a".write(
            to: fixture.workspace.appendingPathComponent("alpha.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "b".write(
            to: secondRoot.appendingPathComponent("beta.txt"),
            atomically: true,
            encoding: .utf8
        )

        try await sendRequest(
            id: 2,
            method: "fuzzyFileSearch/sessionStart",
            params: ["sessionId": "a", "roots": [fixture.workspace.path]],
            to: fixture.session
        )
        try await sendRequest(
            id: 3,
            method: "fuzzyFileSearch/sessionStart",
            params: ["sessionId": "b", "roots": [secondRoot.path]],
            to: fixture.session
        )
        try await sendRequest(
            id: 4,
            method: "fuzzyFileSearch/sessionUpdate",
            params: ["sessionId": "a", "query": "alp"],
            to: fixture.session
        )
        try await sendRequest(
            id: 5,
            method: "fuzzyFileSearch/sessionUpdate",
            params: ["sessionId": "b", "query": "bet"],
            to: fixture.session
        )

        let records = try await waitForNotification(
            method: "fuzzyFileSearch/sessionUpdated",
            count: 2,
            output: fixture.output
        )
        let updates = Dictionary(uniqueKeysWithValues: try records.map { record in
            let params = try XCTUnwrap(record["params"]?.objectValue)
            let sessionID = try XCTUnwrap(params["sessionId"]?.stringValue)
            let firstFile = try XCTUnwrap(params["files"]?.arrayValue?.first?.objectValue)
            return (sessionID, firstFile)
        })
        XCTAssertEqual(updates["a"]?["root"]?.stringValue, fixture.workspace.path)
        XCTAssertEqual(updates["a"]?["path"]?.stringValue, "alpha.txt")
        XCTAssertEqual(updates["b"]?["root"]?.stringValue, secondRoot.path)
        XCTAssertEqual(updates["b"]?["path"]?.stringValue, "beta.txt")
    }

    func testInputBoundsFailBeforeStartingSearchWork() async throws {
        let fixture = try await makeFixture()
        try await sendRequest(
            id: 2,
            method: "fuzzyFileSearch",
            params: [
                "query": String(repeating: "x", count: 257),
                "roots": [fixture.workspace.path]
            ],
            to: fixture.session
        )
        try await sendRequest(
            id: 3,
            method: "fuzzyFileSearch",
            params: [
                "query": "x",
                "roots": Array(repeating: fixture.workspace.path, count: 33)
            ],
            to: fixture.session
        )

        let queryError = try await waitForResponse(id: 2, output: fixture.output)
        let rootsError = try await waitForResponse(id: 3, output: fixture.output)
        XCTAssertEqual(queryError["error"]?.objectValue?["code"]?.numberValue, -32_602)
        XCTAssertEqual(rootsError["error"]?.objectValue?["code"]?.numberValue, -32_602)
    }

    func testSessionMethodsRequireExperimentalCapability() async throws {
        let fixture = try await makeFixture(experimentalAPI: false)
        try await sendRequest(
            id: 2,
            method: "fuzzyFileSearch/sessionStart",
            params: ["sessionId": "disabled", "roots": [fixture.workspace.path]],
            to: fixture.session
        )
        let response = try await waitForResponse(id: 2, output: fixture.output)
        XCTAssertEqual(
            response["error"]?.objectValue?["message"]?.stringValue,
            "fuzzyFileSearch/sessionStart requires capabilities.experimentalApi: true"
        )
    }

    private func makeFixture(experimentalAPI: Bool = true) async throws -> FuzzySearchFixture {
        let home = try temporaryDirectory(prefix: "app-server-fuzzy-home")
        let workspace = try temporaryDirectory(prefix: "app-server-fuzzy-workspace")
        let output = FuzzySearchOutputCollector()
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
        try await sendRequest(
            id: 1,
            method: "initialize",
            params: [
                "clientInfo": ["name": "FuzzySearchTests", "version": "1"],
                "capabilities": ["experimentalApi": experimentalAPI]
            ],
            to: session
        )
        try await send(["method": "initialized", "params": [:]], to: session)
        return FuzzySearchFixture(session: session, output: output, workspace: workspace)
    }

    private func writeSearchFixture(to root: URL) throws {
        try "x".write(to: root.appendingPathComponent("abc"), atomically: true, encoding: .utf8)
        try "x".write(to: root.appendingPathComponent("abcde"), atomically: true, encoding: .utf8)
        try "x".write(to: root.appendingPathComponent("abexy"), atomically: true, encoding: .utf8)
        try "x".write(to: root.appendingPathComponent("zzz.txt"), atomically: true, encoding: .utf8)
        let subdirectory = root.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
        try "x".write(to: subdirectory.appendingPathComponent("abce"), atomically: true, encoding: .utf8)
    }

    private func sendRequest(
        id: Int,
        method: String,
        params: [String: Any],
        to session: AppServerSession
    ) async throws {
        try await send(["id": id, "method": method, "params": params], to: session)
    }

    private func send(_ object: [String: Any], to session: AppServerSession) async throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        await session.receive(data)
    }

    private func waitForResponse(
        id: Int,
        output: FuzzySearchOutputCollector
    ) async throws -> [String: CLIJSONValue] {
        for _ in 0..<400 {
            if let record = try await output.records().first(where: { $0["id"]?.numberValue == Double(id) }) {
                return record
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw FuzzySearchTestError.timedOut
    }

    private func waitForNotification(
        method: String,
        count: Int,
        output: FuzzySearchOutputCollector
    ) async throws -> [[String: CLIJSONValue]] {
        for _ in 0..<400 {
            let matches = try await output.records().filter { $0["method"]?.stringValue == method }
            if matches.count >= count { return matches }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw FuzzySearchTestError.timedOut
    }

    private func temporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

private struct FuzzySearchFixture {
    var session: AppServerSession
    var output: FuzzySearchOutputCollector
    var workspace: URL
}

private actor FuzzySearchOutputCollector {
    private var lines: [String] = []

    func append(_ line: String) {
        lines.append(line)
    }

    func records() throws -> [[String: CLIJSONValue]] {
        try lines.map { line in
            guard let record = try CLIJSONCodec.decode(line).objectValue else {
                throw FuzzySearchTestError.invalidRecord
            }
            return record
        }
    }
}

private enum FuzzySearchTestError: Error {
    case invalidRecord
    case timedOut
}
