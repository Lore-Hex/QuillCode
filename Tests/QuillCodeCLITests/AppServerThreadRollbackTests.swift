import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeSafety
import XCTest

@testable import QuillCodeCLI

final class AppServerThreadRollbackTests: XCTestCase {
    func testRollsBackTurnsWithoutNotificationsAndPersistsAcrossRestart() async throws {
        let fixture = try await makeStartedFixture(llm: RollbackEchoLLM())
        try await appendTurns(3, to: fixture)
        let baseline = try await fixture.output.records().count

        try await sendRequest(
            id: 20,
            method: "thread/rollback",
            params: ["threadId": fixture.threadID, "numTurns": 2],
            to: fixture.session
        )

        let records = Array(try await fixture.output.records().dropFirst(baseline))
        XCTAssertEqual(records.count, 1)
        XCTAssertNil(records.first?["method"])
        let rolledBack = try responseThread(for: 20, in: records)
        XCTAssertEqual(rolledBack["id"]?.stringValue, fixture.threadID)
        XCTAssertEqual(rolledBack["sessionId"]?.stringValue, fixture.sessionID)
        XCTAssertEqual(rolledBack["status"]?.objectValue?["type"]?.stringValue, "idle")
        XCTAssertEqual(rolledBack["turns"]?.arrayValue?.count, 1)
        XCTAssertEqual(rolledBack["name"], .null)

        let restartedOutput = RollbackOutputCollector()
        let restarted = try makeSession(
            home: fixture.home,
            workspace: fixture.workspace,
            llm: RollbackEchoLLM(),
            output: restartedOutput
        )
        try await initialize(restarted, output: restartedOutput)
        try await sendRequest(
            id: 30,
            method: "thread/read",
            params: ["threadId": fixture.threadID, "includeTurns": true],
            to: restarted
        )
        var restartedRecords = try await restartedOutput.records()
        XCTAssertEqual(try responseThread(for: 30, in: restartedRecords)["turns"]?.arrayValue?.count, 1)

        try await sendRequest(
            id: 31,
            method: "thread/rollback",
            params: ["threadId": fixture.threadID, "numTurns": 99],
            to: restarted
        )
        restartedRecords = try await restartedOutput.records()
        XCTAssertEqual(try responseThread(for: 31, in: restartedRecords)["turns"]?.arrayValue?.count, 0)

        try await sendRequest(
            id: 32,
            method: "thread/rollback",
            params: ["threadId": fixture.threadID, "numTurns": 0],
            to: restarted
        )
        restartedRecords = try await restartedOutput.records()
        XCTAssertEqual(errorCode(for: 32, in: restartedRecords), -32_600)
        XCTAssertEqual(errorMessage(for: 32, in: restartedRecords), "numTurns must be >= 1")
    }

    func testPersistsExplicitNameWhileGeneratedTitleRemainsProtocolNull() async throws {
        let fixture = try await makeStartedFixture(llm: RollbackEchoLLM())
        try await appendTurns(1, to: fixture)

        try await sendRequest(
            id: 20,
            method: "thread/read",
            params: ["threadId": fixture.threadID, "includeTurns": true],
            to: fixture.session
        )
        var records = try await fixture.output.records()
        XCTAssertEqual(try responseThread(for: 20, in: records)["name"], .null)

        try await sendRequest(
            id: 21,
            method: "thread/name/set",
            params: ["threadId": fixture.threadID, "name": "Explicit name"],
            to: fixture.session
        )
        try await sendRequest(
            id: 22,
            method: "thread/rollback",
            params: ["threadId": fixture.threadID, "numTurns": 1],
            to: fixture.session
        )
        records = try await fixture.output.records()
        XCTAssertEqual(try responseThread(for: 22, in: records)["name"]?.stringValue, "Explicit name")
    }

    func testRejectsMalformedUnknownAndInvalidCountsWithoutMutatingHistory() async throws {
        let fixture = try await makeStartedFixture(llm: RollbackEchoLLM())
        try await appendTurns(1, to: fixture)

        try await sendRequest(
            id: 20,
            method: "thread/rollback",
            params: ["threadId": "not-a-thread-id", "numTurns": 1],
            to: fixture.session
        )
        try await sendRequest(
            id: 21,
            method: "thread/rollback",
            params: [
                "threadId": "67e55044-10b1-426f-9247-bb680e5fe0c8",
                "numTurns": 1
            ],
            to: fixture.session
        )
        try await sendRequest(
            id: 22,
            method: "thread/rollback",
            params: ["threadId": fixture.threadID, "numTurns": -1],
            to: fixture.session
        )
        try await sendRequest(
            id: 23,
            method: "thread/read",
            params: ["threadId": fixture.threadID, "includeTurns": true],
            to: fixture.session
        )

        let records = try await fixture.output.records()
        XCTAssertEqual(errorCode(for: 20, in: records), -32_600)
        XCTAssertTrue(errorMessage(for: 20, in: records)?.contains("invalid thread id") == true)
        XCTAssertEqual(errorCode(for: 21, in: records), -32_600)
        XCTAssertTrue(errorMessage(for: 21, in: records)?.contains("thread not found") == true)
        XCTAssertEqual(errorCode(for: 22, in: records), -32_602)
        XCTAssertEqual(try responseThread(for: 23, in: records)["turns"]?.arrayValue?.count, 1)
    }

    func testRejectsActiveTurnAndTreatsSteeringAsOnePersistedTurn() async throws {
        let llm = FirstRollbackActionBlockingLLM()
        let fixture = try await makeStartedFixture(llm: llm)
        let baseline = try await fixture.output.records().count

        try await sendRequest(
            id: 10,
            method: "turn/start",
            params: [
                "threadId": fixture.threadID,
                "input": [["type": "text", "text": "first", "text_elements": []]],
                "clientUserMessageId": "client-first"
            ],
            to: fixture.session
        )
        await llm.waitUntilStarted()
        let activeRecords = Array(try await fixture.output.records().dropFirst(baseline))
        let turnID = try XCTUnwrap(result(for: 10, in: activeRecords)?["turn"]?.objectValue?["id"]?.stringValue)

        try await sendRequest(
            id: 11,
            method: "thread/rollback",
            params: ["threadId": fixture.threadID, "numTurns": 1],
            to: fixture.session
        )
        try await sendRequest(
            id: 12,
            method: "turn/steer",
            params: [
                "threadId": fixture.threadID,
                "expectedTurnId": turnID,
                "input": [["type": "text", "text": "steer", "text_elements": []]],
                "clientUserMessageId": "client-steer"
            ],
            to: fixture.session
        )
        await llm.release()
        await fixture.session.waitForActiveTurns()

        try await sendRequest(
            id: 13,
            method: "thread/read",
            params: ["threadId": fixture.threadID, "includeTurns": true],
            to: fixture.session
        )
        var records = try await fixture.output.records()
        XCTAssertEqual(errorCode(for: 11, in: records), -32_600)
        XCTAssertTrue(errorMessage(for: 11, in: records)?.contains("turn is in progress") == true)
        let beforeRollback = try responseThread(for: 13, in: records)
        let turns = try XCTUnwrap(beforeRollback["turns"]?.arrayValue)
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns.first?.objectValue?["id"]?.stringValue, turnID)
        let userItems = turns.first?.objectValue?["items"]?.arrayValue?.filter {
            $0.objectValue?["type"]?.stringValue == "userMessage"
        }
        XCTAssertEqual(userItems?.count, 2)
        XCTAssertEqual(userItems?.compactMap { $0.objectValue?["clientId"]?.stringValue }, [
            "client-first", "client-steer"
        ])

        try await sendRequest(
            id: 14,
            method: "thread/rollback",
            params: ["threadId": fixture.threadID, "numTurns": 1],
            to: fixture.session
        )
        records = try await fixture.output.records()
        XCTAssertEqual(try responseThread(for: 14, in: records)["turns"]?.arrayValue?.count, 0)
    }

    private func makeStartedFixture(llm: any LLMClient) async throws -> RollbackFixture {
        let home = try temporaryDirectory(prefix: "app-server-rollback-home")
        let workspace = try temporaryDirectory(prefix: "app-server-rollback-workspace")
        let output = RollbackOutputCollector()
        let session = try makeSession(home: home, workspace: workspace, llm: llm, output: output)
        try await initialize(session, output: output)
        try await sendRequest(
            id: 2,
            method: "thread/start",
            params: [
                "cwd": workspace.path,
                "model": "trustedrouter/fast",
                "sandbox": "read-only"
            ],
            to: session
        )
        let records = try await output.records()
        let thread = try responseThread(for: 2, in: records)
        return RollbackFixture(
            session: session,
            output: output,
            home: home,
            workspace: workspace,
            threadID: try XCTUnwrap(thread["id"]?.stringValue),
            sessionID: try XCTUnwrap(thread["sessionId"]?.stringValue)
        )
    }

    private func makeSession(
        home: URL,
        workspace: URL,
        llm: any LLMClient,
        output: RollbackOutputCollector
    ) throws -> AppServerSession {
        try AppServerSession(
            request: CLIAppServerRequest(live: false, home: home),
            environment: [:],
            currentDirectory: workspace,
            runnerFactory: { configuration in
                AgentRunner(
                    llm: llm,
                    safety: StaticSafetyReviewer(),
                    maxToolSteps: configuration.appConfig.maxToolSteps,
                    enablesImmediateActionPreflight: false
                )
            },
            sink: { line in await output.append(line) }
        )
    }

    private func initialize(
        _ session: AppServerSession,
        output: RollbackOutputCollector
    ) async throws {
        try await sendRequest(
            id: 1,
            method: "initialize",
            params: ["clientInfo": ["name": "QuillCodeTests", "version": "1"]],
            to: session
        )
        try await sendNotification(method: "initialized", params: [:], to: session)
        let records = try await output.records()
        XCTAssertNotNil(result(for: 1, in: records))
    }

    private func appendTurns(_ count: Int, to fixture: RollbackFixture) async throws {
        for index in 0..<count {
            try await sendRequest(
                id: 10 + index,
                method: "turn/start",
                params: [
                    "threadId": fixture.threadID,
                    "input": [["type": "text", "text": "turn \(index)", "text_elements": []]]
                ],
                to: fixture.session
            )
            await fixture.session.waitForActiveTurns()
        }
    }

    private func sendRequest(
        id: Int,
        method: String,
        params: [String: Any],
        to session: AppServerSession
    ) async throws {
        try await send(["id": id, "method": method, "params": params], to: session)
    }

    private func sendNotification(
        method: String,
        params: [String: Any],
        to session: AppServerSession
    ) async throws {
        try await send(["method": method, "params": params], to: session)
    }

    private func send(_ object: [String: Any], to session: AppServerSession) async throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        await session.receive(data)
    }

    private func responseThread(
        for id: Int,
        in records: [[String: CLIJSONValue]]
    ) throws -> [String: CLIJSONValue] {
        try XCTUnwrap(result(for: id, in: records)?["thread"]?.objectValue)
    }

    private func result(
        for id: Int,
        in records: [[String: CLIJSONValue]]
    ) -> [String: CLIJSONValue]? {
        records.first { $0["id"]?.numberValue == Double(id) }?["result"]?.objectValue
    }

    private func errorCode(for id: Int, in records: [[String: CLIJSONValue]]) -> Double? {
        records.first { $0["id"]?.numberValue == Double(id) }?["error"]?.objectValue?["code"]?.numberValue
    }

    private func errorMessage(for id: Int, in records: [[String: CLIJSONValue]]) -> String? {
        records.first { $0["id"]?.numberValue == Double(id) }?["error"]?.objectValue?["message"]?.stringValue
    }

    private func temporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

private struct RollbackFixture {
    var session: AppServerSession
    var output: RollbackOutputCollector
    var home: URL
    var workspace: URL
    var threadID: String
    var sessionID: String
}

private actor RollbackOutputCollector {
    private var lines: [String] = []

    func append(_ line: String) {
        lines.append(line)
    }

    func records() throws -> [[String: CLIJSONValue]] {
        try lines.map { line in
            guard let record = try CLIJSONCodec.decode(line).objectValue else {
                throw RollbackTestError.invalidRecord
            }
            return record
        }
    }
}

private enum RollbackTestError: Error {
    case invalidRecord
}

private struct RollbackEchoLLM: LLMClient {
    func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AgentAction {
        _ = (thread, tools)
        return .say("answer: \(userMessage)")
    }
}

private actor FirstRollbackActionBlockingLLM: LLMClient {
    private var callCount = 0
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AgentAction {
        _ = (thread, tools)
        callCount += 1
        if callCount == 1 {
            started = true
            startWaiters.forEach { $0.resume() }
            startWaiters.removeAll()
            await withCheckedContinuation { releaseContinuation = $0 }
        }
        return .say("answer: \(userMessage)")
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
