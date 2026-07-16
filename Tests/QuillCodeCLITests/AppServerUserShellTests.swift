import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeSafety
import XCTest

@testable import QuillCodeCLI

final class AppServerUserShellTests: XCTestCase {
    func testStandaloneCommandRespondsBeforeLifecycleStreamsAndPersistsEmptyTurn() async throws {
        let fixture = try await makeStartedFixture()
        let baseline = try await fixture.output.records().count

        try await request(
            fixture,
            id: 10,
            method: "thread/shellCommand",
            params: [
                "threadId": fixture.threadID,
                "command": "printf 'hello shell'"
            ]
        )
        await fixture.session.waitForActiveTurns()

        let records = Array(try await fixture.output.records().dropFirst(baseline))
        XCTAssertEqual(result(for: 10, in: records), [:])
        let responseIndex = try XCTUnwrap(records.firstIndex { $0["id"]?.numberValue == 10 })
        let notificationIndex = try XCTUnwrap(records.firstIndex { $0["method"] != nil })
        XCTAssertLessThan(responseIndex, notificationIndex)

        let started = try notification("item/started", in: records)
        let completed = try notification("item/completed", in: records)
        let startedItem = try XCTUnwrap(started["item"]?.objectValue)
        let completedItem = try XCTUnwrap(completed["item"]?.objectValue)
        XCTAssertEqual(started["turnId"], completed["turnId"])
        XCTAssertEqual(startedItem["id"], completedItem["id"])
        XCTAssertEqual(startedItem["type"]?.stringValue, "commandExecution")
        XCTAssertEqual(startedItem["source"]?.stringValue, "userShell")
        XCTAssertEqual(startedItem["status"]?.stringValue, "inProgress")
        XCTAssertEqual(startedItem["cwd"]?.stringValue, fixture.workspace.path)
        XCTAssertTrue(startedItem["command"]?.stringValue?.hasPrefix("/bin/sh -lc ") == true)
        XCTAssertEqual(
            startedItem["commandActions"]?.arrayValue?.first?.objectValue?["command"]?.stringValue,
            "printf 'hello shell'"
        )
        XCTAssertEqual(completedItem["status"]?.stringValue, "completed")
        XCTAssertEqual(completedItem["aggregatedOutput"]?.stringValue, "hello shell")
        XCTAssertEqual(completedItem["exitCode"]?.numberValue, 0)
        XCTAssertEqual(
            try notification("item/commandExecution/outputDelta", in: records)["delta"]?.stringValue,
            "hello shell"
        )

        try await assertHistoryContainsOneEmptyTurn(fixture, startingRequestID: 20)
        let stored = try threadStore(for: fixture).load(try threadUUID(fixture))
        XCTAssertTrue(stored.messages.contains { $0.role == .tool && $0.content.contains("hello shell") })
    }

    func testConcurrentCommandsShareOneStandaloneTurn() async throws {
        let fixture = try await makeStartedFixture()
        let baseline = try await fixture.output.records().count

        try await request(
            fixture,
            id: 10,
            method: "thread/shellCommand",
            params: [
                "threadId": fixture.threadID,
                "command": "sleep 0.15; printf first"
            ]
        )
        try await request(
            fixture,
            id: 11,
            method: "thread/shellCommand",
            params: [
                "threadId": fixture.threadID,
                "command": "printf second"
            ]
        )
        await fixture.session.waitForActiveTurns()

        let records = Array(try await fixture.output.records().dropFirst(baseline))
        XCTAssertEqual(records.filter { $0["method"]?.stringValue == "turn/started" }.count, 1)
        XCTAssertEqual(records.filter { $0["method"]?.stringValue == "turn/completed" }.count, 1)
        let itemStarts = records.filter { $0["method"]?.stringValue == "item/started" }
        XCTAssertEqual(itemStarts.count, 2)
        XCTAssertEqual(Set(itemStarts.compactMap {
            $0["params"]?.objectValue?["turnId"]?.stringValue
        }).count, 1)
        let outputs: Set<String> = Set(records.compactMap { record -> String? in
            guard record["method"]?.stringValue == "item/completed" else { return nil }
            return record["params"]?.objectValue?["item"]?.objectValue?["aggregatedOutput"]?.stringValue
        })
        XCTAssertEqual(outputs, ["first", "second"])
        try await assertHistoryContainsOneEmptyTurn(fixture, startingRequestID: 20)
    }

    func testStandaloneCommandDoesNotAlterThePreviousConversationProjection() async throws {
        let fixture = try await makeStartedFixture()
        try await request(
            fixture,
            id: 10,
            method: "turn/start",
            params: [
                "threadId": fixture.threadID,
                "input": [["type": "text", "text": "first conversation"]]
            ]
        )
        await fixture.session.waitForActiveTurns()
        try await request(
            fixture,
            id: 11,
            method: "thread/read",
            params: ["threadId": fixture.threadID, "includeTurns": true]
        )
        let beforeRecords = try await fixture.output.records()
        let before = try XCTUnwrap(
            result(for: 11, in: beforeRecords)?["thread"]?
                .objectValue?["turns"]?.arrayValue?.first
        )

        try await request(
            fixture,
            id: 12,
            method: "thread/shellCommand",
            params: ["threadId": fixture.threadID, "command": "printf standalone-output"]
        )
        await fixture.session.waitForActiveTurns()
        try await request(
            fixture,
            id: 13,
            method: "thread/read",
            params: ["threadId": fixture.threadID, "includeTurns": true]
        )
        let afterRecords = try await fixture.output.records()
        let read = try XCTUnwrap(result(for: 13, in: afterRecords)?["thread"]?.objectValue)
        let turns = try XCTUnwrap(read["turns"]?.arrayValue)
        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(turns[0], before)
        XCTAssertEqual(turnItems(turns[1]), [])
    }

    func testRollbackRemovesStandaloneTurnAndItsModelFeedback() async throws {
        let fixture = try await makeStartedFixture()
        try await request(
            fixture,
            id: 10,
            method: "thread/shellCommand",
            params: ["threadId": fixture.threadID, "command": "printf rollback-output"]
        )
        await fixture.session.waitForActiveTurns()

        try await request(
            fixture,
            id: 11,
            method: "thread/rollback",
            params: ["threadId": fixture.threadID, "numTurns": 1]
        )
        let records = try await fixture.output.records()
        let rolledBack = try XCTUnwrap(result(for: 11, in: records)?["thread"]?.objectValue)
        XCTAssertEqual(rolledBack["turns"]?.arrayValue, [])
        let stored = try threadStore(for: fixture).load(try threadUUID(fixture))
        XCTAssertFalse(stored.messages.contains { $0.content.contains("rollback-output") })

        try await request(
            fixture,
            id: 12,
            method: "thread/read",
            params: ["threadId": fixture.threadID, "includeTurns": true]
        )
        let readRecords = try await fixture.output.records()
        let restartedView = try XCTUnwrap(
            result(for: 12, in: readRecords)?["thread"]?.objectValue
        )
        XCTAssertEqual(restartedView["turns"]?.arrayValue, [])
    }

    func testEmptyCommandsAreRejectedWithoutLifecycle() async throws {
        let fixture = try await makeStartedFixture()
        let baseline = try await fixture.output.records().count

        try await request(
            fixture,
            id: 10,
            method: "thread/shellCommand",
            params: ["threadId": fixture.threadID, "command": ""]
        )
        try await request(
            fixture,
            id: 11,
            method: "thread/shellCommand",
            params: ["threadId": fixture.threadID, "command": "  \n\t "]
        )

        let records = Array(try await fixture.output.records().dropFirst(baseline))
        for id in [10, 11] {
            XCTAssertEqual(errorCode(for: id, in: records), -32_600)
            XCTAssertEqual(errorMessage(for: id, in: records), "command must not be empty")
        }
        XCTAssertFalse(records.contains { $0["method"] != nil })
    }

    func testStandaloneCommandCanBeInterrupted() async throws {
        let fixture = try await makeStartedFixture()
        let baseline = try await fixture.output.records().count

        try await request(
            fixture,
            id: 10,
            method: "thread/shellCommand",
            params: ["threadId": fixture.threadID, "command": "exec sleep 5"]
        )
        let started = try await waitForNotification("item/started", fixture: fixture, after: baseline)
        let turnID = try XCTUnwrap(started["turnId"]?.stringValue)
        try await request(
            fixture,
            id: 11,
            method: "turn/interrupt",
            params: ["threadId": fixture.threadID, "turnId": turnID]
        )
        await fixture.session.waitForActiveTurns()

        let records = Array(try await fixture.output.records().dropFirst(baseline))
        let completedItem = try XCTUnwrap(
            try notification("item/completed", in: records)["item"]?.objectValue
        )
        XCTAssertEqual(completedItem["status"]?.stringValue, "failed")
        XCTAssertEqual(completedItem["exitCode"]?.numberValue, -1)
        let turn = try XCTUnwrap(
            try notification("turn/completed", in: records)["turn"]?.objectValue
        )
        XCTAssertEqual(turn["status"]?.stringValue, "interrupted")
        XCTAssertEqual(result(for: 11, in: records), [:])
    }

    func testBackgroundTerminalsListPaginatesTerminatesAndCleans() async throws {
        let fixture = try await makeStartedFixture()
        try await request(
            fixture,
            id: 10,
            method: "thread/shellCommand",
            params: ["threadId": fixture.threadID, "command": "exec sleep 30"]
        )
        try await request(
            fixture,
            id: 11,
            method: "thread/shellCommand",
            params: ["threadId": fixture.threadID, "command": "exec sleep 30"]
        )

        let terminals = try await waitForBackgroundTerminals(
            count: 2,
            fixture: fixture,
            startingRequestID: 20
        )
        let first = try XCTUnwrap(terminals.first?.objectValue)
        let second = try XCTUnwrap(terminals.last?.objectValue)
        let firstProcessID = try XCTUnwrap(first["processId"]?.stringValue)
        let secondProcessID = try XCTUnwrap(second["processId"]?.stringValue)
        XCTAssertLessThan(try XCTUnwrap(Int32(firstProcessID)), try XCTUnwrap(Int32(secondProcessID)))
        XCTAssertEqual(first["command"]?.stringValue, "exec sleep 30")
        XCTAssertEqual(first["cwd"]?.stringValue, fixture.workspace.path)
        XCTAssertEqual(first["osPid"]?.numberValue, Double(try XCTUnwrap(Int32(firstProcessID))))
        XCTAssertEqual(first["cpuPercent"], .null)
        XCTAssertEqual(first["rssKb"], .null)
        XCTAssertNotNil(first["itemId"]?.stringValue)

        try await request(
            fixture,
            id: 100,
            method: "thread/backgroundTerminals/list",
            params: ["threadId": fixture.threadID, "limit": 1]
        )
        var records = try await fixture.output.records()
        let firstPage = try XCTUnwrap(result(for: 100, in: records))
        XCTAssertEqual(firstPage["data"]?.arrayValue?.count, 1)
        XCTAssertEqual(firstPage["nextCursor"]?.stringValue, firstProcessID)

        try await request(
            fixture,
            id: 101,
            method: "thread/backgroundTerminals/list",
            params: ["threadId": fixture.threadID, "cursor": firstProcessID, "limit": 1]
        )
        records = try await fixture.output.records()
        let secondPage = try XCTUnwrap(result(for: 101, in: records))
        XCTAssertEqual(secondPage["data"]?.arrayValue, [.object(second)])
        XCTAssertEqual(secondPage["nextCursor"], .null)

        try await request(
            fixture,
            id: 102,
            method: "thread/backgroundTerminals/terminate",
            params: ["threadId": fixture.threadID, "processId": firstProcessID]
        )
        try await request(
            fixture,
            id: 103,
            method: "thread/backgroundTerminals/terminate",
            params: ["threadId": fixture.threadID, "processId": firstProcessID]
        )
        records = try await fixture.output.records()
        XCTAssertEqual(result(for: 102, in: records)?["terminated"]?.boolValue, true)
        XCTAssertEqual(result(for: 103, in: records)?["terminated"]?.boolValue, false)

        try await request(
            fixture,
            id: 104,
            method: "thread/backgroundTerminals/list",
            params: ["threadId": fixture.threadID]
        )
        records = try await fixture.output.records()
        let afterTerminate = try XCTUnwrap(result(for: 104, in: records)?["data"]?.arrayValue)
        XCTAssertEqual(afterTerminate.count, 1)
        XCTAssertEqual(afterTerminate.first?.objectValue?["processId"]?.stringValue, secondProcessID)

        try await request(
            fixture,
            id: 105,
            method: "thread/backgroundTerminals/clean",
            params: ["threadId": fixture.threadID]
        )
        try await request(
            fixture,
            id: 106,
            method: "thread/backgroundTerminals/list",
            params: ["threadId": fixture.threadID]
        )
        records = try await fixture.output.records()
        XCTAssertEqual(result(for: 105, in: records), [:])
        XCTAssertEqual(result(for: 106, in: records)?["data"]?.arrayValue, [])
        XCTAssertEqual(result(for: 106, in: records)?["nextCursor"], .null)
        await fixture.session.waitForActiveTurns()
    }

    func testBackgroundTerminalRequestsRejectInvalidInputsAndUnknownThreads() async throws {
        let fixture = try await makeStartedFixture()
        try await request(
            fixture,
            id: 10,
            method: "thread/backgroundTerminals/list",
            params: ["threadId": fixture.threadID, "cursor": "not-a-pid"]
        )
        try await request(
            fixture,
            id: 11,
            method: "thread/backgroundTerminals/list",
            params: ["threadId": fixture.threadID, "limit": -1]
        )
        try await request(
            fixture,
            id: 12,
            method: "thread/backgroundTerminals/terminate",
            params: ["threadId": fixture.threadID, "processId": "not-a-pid"]
        )
        try await request(
            fixture,
            id: 13,
            method: "thread/backgroundTerminals/clean",
            params: ["threadId": UUID().uuidString.lowercased()]
        )

        let records = try await fixture.output.records()
        XCTAssertEqual(errorCode(for: 10, in: records), -32_600)
        XCTAssertEqual(
            errorMessage(for: 10, in: records),
            "invalid cursor: expected a 32-bit signed integer"
        )
        XCTAssertEqual(errorCode(for: 11, in: records), -32_602)
        XCTAssertEqual(
            errorMessage(for: 11, in: records),
            "Invalid params: limit must be an unsigned 32-bit integer or null"
        )
        XCTAssertEqual(errorCode(for: 12, in: records), -32_600)
        XCTAssertEqual(
            errorMessage(for: 12, in: records),
            "invalid background terminal process id: expected a 32-bit signed integer"
        )
        XCTAssertEqual(errorCode(for: 13, in: records), -32_602)
        XCTAssertTrue(errorMessage(for: 13, in: records)?.contains("was not found") == true)
    }

    func testCommandUsesActiveTurnAndFeedbackReentersModelContext() async throws {
        let llm = ShellAwareBlockingLLM()
        let fixture = try await makeStartedFixture(llm: llm)
        let baseline = try await fixture.output.records().count

        try await request(
            fixture,
            id: 10,
            method: "turn/start",
            params: [
                "threadId": fixture.threadID,
                "input": [["type": "text", "text": "work while I inspect"]]
            ]
        )
        let turnRecords = try await fixture.output.records()
        let turnResponse = try XCTUnwrap(result(for: 10, in: turnRecords)?["turn"]?.objectValue)
        let turnID = try XCTUnwrap(turnResponse["id"]?.stringValue)
        await llm.waitUntilFirstInvocation()

        try await request(
            fixture,
            id: 11,
            method: "thread/shellCommand",
            params: ["threadId": fixture.threadID, "command": "printf active-output"]
        )
        _ = try await waitForNotification(
            "item/completed",
            fixture: fixture,
            after: baseline
        ) { params in
            params["item"]?.objectValue?["source"]?.stringValue == "userShell"
        }
        await llm.releaseFirstInvocation()
        await fixture.session.waitForActiveTurns()

        let observations = await llm.observations()
        XCTAssertEqual(observations.invocationCount, 2)
        XCTAssertTrue(observations.sawToolFeedback)
        let records = Array(try await fixture.output.records().dropFirst(baseline))
        XCTAssertEqual(records.filter { $0["method"]?.stringValue == "turn/started" }.count, 1)
        XCTAssertEqual(records.filter { $0["method"]?.stringValue == "turn/completed" }.count, 1)
        let commandStarted = try notification("item/started", in: records) { params in
            params["item"]?.objectValue?["source"]?.stringValue == "userShell"
        }
        XCTAssertEqual(commandStarted["turnId"]?.stringValue, turnID)

        try await request(
            fixture,
            id: 20,
            method: "thread/read",
            params: ["threadId": fixture.threadID, "includeTurns": true]
        )
        let readRecords = try await fixture.output.records()
        let read = try XCTUnwrap(result(for: 20, in: readRecords)?["thread"]?.objectValue)
        let turns = try XCTUnwrap(read["turns"]?.arrayValue)
        XCTAssertEqual(turns.count, 1)
        XCTAssertFalse(turnItems(turns[0]).contains { item in
            item.objectValue?["type"]?.stringValue == "commandExecution"
        })
    }

    private func makeStartedFixture(
        llm: any LLMClient = UserShellEchoLLM()
    ) async throws -> UserShellFixture {
        let home = try temporaryDirectory(prefix: "app-server-user-shell-home")
        let workspace = try temporaryDirectory(prefix: "app-server-user-shell-workspace")
        let output = UserShellOutputCollector()
        let session = try AppServerSession(
            request: CLIAppServerRequest(live: false, home: home),
            environment: ["SHELL": "/bin/sh"],
            currentDirectory: workspace,
            runnerFactory: { configuration in
                AgentRunner(
                    llm: llm,
                    safety: StaticSafetyReviewer(),
                    maxToolSteps: configuration.appConfig.maxToolSteps,
                    enablesImmediateActionPreflight: false,
                    compaction: AgentCompactionPolicy(compactor: ThreadCompactor())
                )
            },
            sink: { line in await output.append(line) }
        )
        let fixture = UserShellFixture(
            session: session,
            output: output,
            home: home,
            workspace: workspace,
            threadID: ""
        )
        try await request(
            fixture,
            id: 1,
            method: "initialize",
            params: ["clientInfo": ["name": "QuillCodeTests", "version": "1"]]
        )
        try await send(
            ["method": "initialized", "params": [:]],
            to: session
        )
        try await request(
            fixture,
            id: 2,
            method: "thread/start",
            params: [
                "cwd": workspace.path,
                "model": "trustedrouter/fast",
                "sandbox": "read-only"
            ]
        )
        let records = try await output.records()
        let thread = try XCTUnwrap(result(for: 2, in: records)?["thread"]?.objectValue)
        return UserShellFixture(
            session: session,
            output: output,
            home: home,
            workspace: workspace,
            threadID: try XCTUnwrap(thread["id"]?.stringValue)
        )
    }

    private func assertHistoryContainsOneEmptyTurn(
        _ fixture: UserShellFixture,
        startingRequestID: Int
    ) async throws {
        try await request(
            fixture,
            id: startingRequestID,
            method: "thread/read",
            params: ["threadId": fixture.threadID, "includeTurns": true]
        )
        try await request(
            fixture,
            id: startingRequestID + 1,
            method: "thread/turns/list",
            params: [
                "threadId": fixture.threadID,
                "sortDirection": "asc",
                "itemsView": "full"
            ]
        )
        try await request(
            fixture,
            id: startingRequestID + 2,
            method: "thread/fork",
            params: ["threadId": fixture.threadID]
        )
        let records = try await fixture.output.records()
        let read = try XCTUnwrap(result(for: startingRequestID, in: records)?["thread"]?.objectValue)
        let readTurns = try XCTUnwrap(read["turns"]?.arrayValue)
        XCTAssertEqual(readTurns.count, 1)
        XCTAssertEqual(turnItems(readTurns[0]), [])

        let listed = try XCTUnwrap(result(for: startingRequestID + 1, in: records)?["data"]?.arrayValue)
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(turnItems(listed[0]), [])

        let fork = try XCTUnwrap(result(for: startingRequestID + 2, in: records)?["thread"]?.objectValue)
        let forkTurns = try XCTUnwrap(fork["turns"]?.arrayValue)
        XCTAssertEqual(forkTurns.count, 1)
        XCTAssertEqual(turnItems(forkTurns[0]), [])
    }

    private func request(
        _ fixture: UserShellFixture,
        id: Int,
        method: String,
        params: [String: Any]
    ) async throws {
        try await send(["id": id, "method": method, "params": params], to: fixture.session)
    }

    private func send(_ object: [String: Any], to session: AppServerSession) async throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        await session.receive(data)
    }

    private func notification(
        _ method: String,
        in records: [[String: CLIJSONValue]],
        where predicate: ([String: CLIJSONValue]) -> Bool = { _ in true }
    ) throws -> [String: CLIJSONValue] {
        let record = try XCTUnwrap(records.first { record in
            guard record["method"]?.stringValue == method,
                  let params = record["params"]?.objectValue else { return false }
            return predicate(params)
        })
        return try XCTUnwrap(record["params"]?.objectValue)
    }

    private func waitForNotification(
        _ method: String,
        fixture: UserShellFixture,
        after baseline: Int,
        where predicate: ([String: CLIJSONValue]) -> Bool = { _ in true }
    ) async throws -> [String: CLIJSONValue] {
        for _ in 0..<400 {
            let records = Array(try await fixture.output.records().dropFirst(baseline))
            if let record = records.first(where: { record in
                guard record["method"]?.stringValue == method,
                      let params = record["params"]?.objectValue else { return false }
                return predicate(params)
            }), let params = record["params"]?.objectValue {
                return params
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw UserShellTestError.timedOut
    }

    private func waitForBackgroundTerminals(
        count: Int,
        fixture: UserShellFixture,
        startingRequestID: Int
    ) async throws -> [CLIJSONValue] {
        for offset in 0..<400 {
            let requestID = startingRequestID + offset
            try await request(
                fixture,
                id: requestID,
                method: "thread/backgroundTerminals/list",
                params: ["threadId": fixture.threadID]
            )
            let records = try await fixture.output.records()
            if let data = result(for: requestID, in: records)?["data"]?.arrayValue,
               data.count == count {
                return data
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw UserShellTestError.timedOut
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
        records.first { $0["id"]?.numberValue == Double(id) }?["error"]?.objectValue?["code"]?.numberValue
    }

    private func errorMessage(
        for id: Int,
        in records: [[String: CLIJSONValue]]
    ) -> String? {
        records.first { $0["id"]?.numberValue == Double(id) }?["error"]?.objectValue?["message"]?.stringValue
    }

    private func turnItems(_ turn: CLIJSONValue) -> [CLIJSONValue] {
        turn.objectValue?["items"]?.arrayValue ?? []
    }

    private func threadUUID(_ fixture: UserShellFixture) throws -> UUID {
        try XCTUnwrap(UUID(uuidString: fixture.threadID))
    }

    private func threadStore(for fixture: UserShellFixture) -> JSONThreadStore {
        JSONThreadStore(directory: fixture.home.appendingPathComponent("threads"))
    }

    private func temporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

private struct UserShellFixture {
    var session: AppServerSession
    var output: UserShellOutputCollector
    var home: URL
    var workspace: URL
    var threadID: String
}

private actor UserShellOutputCollector {
    private var lines: [String] = []

    func append(_ line: String) {
        lines.append(line)
    }

    func records() throws -> [[String: CLIJSONValue]] {
        try lines.map { line in
            guard let record = try CLIJSONCodec.decode(line).objectValue else {
                throw UserShellTestError.invalidRecord
            }
            return record
        }
    }
}

private struct UserShellEchoLLM: LLMClient {
    func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AgentAction {
        .say(userMessage)
    }
}

private actor ShellAwareBlockingLLM: LLMClient {
    private var invocationCount = 0
    private var sawToolFeedback = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AgentAction {
        invocationCount += 1
        if invocationCount == 1 {
            let waiters = startWaiters
            startWaiters.removeAll()
            waiters.forEach { $0.resume() }
            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
            }
            return .say("first pass")
        }
        sawToolFeedback = thread.messages.contains { message in
            message.role == .tool && message.content.contains("active-output")
        }
        return .say(sawToolFeedback ? "saw shell output" : "missed shell output")
    }

    func waitUntilFirstInvocation() async {
        guard invocationCount == 0 else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func releaseFirstInvocation() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func observations() -> (invocationCount: Int, sawToolFeedback: Bool) {
        (invocationCount, sawToolFeedback)
    }
}

private enum UserShellTestError: Error {
    case invalidRecord
    case timedOut
}
