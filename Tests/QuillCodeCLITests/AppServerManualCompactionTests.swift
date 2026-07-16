import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeSafety
import XCTest

@testable import QuillCodeCLI

final class AppServerManualCompactionTests: XCTestCase {
    func testRespondsBeforeLifecycleAndPersistsCompactedThread() async throws {
        let fixture = try await makeStartedFixture()
        try await appendTurns(4, to: fixture)
        let store = threadStore(for: fixture)
        let threadUUID = try XCTUnwrap(UUID(uuidString: fixture.threadID))
        let messageCountBefore = try store.load(threadUUID).messages.count
        let baseline = try await fixture.output.records().count

        try await sendRequest(
            id: 20,
            method: "thread/compact/start",
            params: ["threadId": fixture.threadID],
            to: fixture.session
        )
        await fixture.session.waitForActiveTurns()

        let lifecycle = Array(try await fixture.output.records().dropFirst(baseline))
        XCTAssertEqual(result(for: 20, in: lifecycle), [:])
        let responseIndex = try XCTUnwrap(lifecycle.firstIndex { $0["id"]?.numberValue == 20 })
        let notificationIndex = try XCTUnwrap(lifecycle.firstIndex { $0["method"] != nil })
        XCTAssertLessThan(responseIndex, notificationIndex)
        XCTAssertEqual(lifecycle.compactMap { $0["method"]?.stringValue }, [
            "thread/status/changed",
            "turn/started",
            "item/started",
            "item/completed",
            "turn/completed",
            "thread/status/changed"
        ])

        let started = try lifecycleParams(for: "item/started", in: lifecycle)
        let completed = try lifecycleParams(for: "item/completed", in: lifecycle)
        XCTAssertEqual(started["threadId"]?.stringValue, fixture.threadID)
        XCTAssertEqual(started["turnId"], completed["turnId"])
        XCTAssertEqual(started["item"], completed["item"])
        XCTAssertEqual(started["item"]?.objectValue?["type"]?.stringValue, "contextCompaction")

        let stored = try store.load(threadUUID)
        XCTAssertLessThan(stored.messages.count, messageCountBefore)
        XCTAssertTrue(stored.events.contains { $0.kind == .notice && $0.summary.contains("Compacted") })
        let completion = try lifecycleParams(for: "turn/completed", in: lifecycle)
        let turn = try XCTUnwrap(completion["turn"]?.objectValue)
        XCTAssertEqual(turn["status"]?.stringValue, "completed")
        XCTAssertEqual(
            turn["items"]?.arrayValue?.first?.objectValue?["type"]?.stringValue,
            "contextCompaction"
        )
    }

    func testRejectsMalformedAndUnknownThreadIDs() async throws {
        let fixture = try await makeStartedFixture()
        let baseline = try await fixture.output.records().count

        try await sendRequest(
            id: 20,
            method: "thread/compact/start",
            params: ["threadId": "not-a-thread-id"],
            to: fixture.session
        )
        try await sendRequest(
            id: 21,
            method: "thread/compact/start",
            params: ["threadId": "67e55044-10b1-426f-9247-bb680e5fe0c8"],
            to: fixture.session
        )

        let records = Array(try await fixture.output.records().dropFirst(baseline))
        XCTAssertEqual(errorCode(for: 20, in: records), -32_600)
        XCTAssertTrue(errorMessage(for: 20, in: records)?.contains("invalid thread id") == true)
        XCTAssertEqual(errorCode(for: 21, in: records), -32_600)
        XCTAssertTrue(errorMessage(for: 21, in: records)?.contains("thread not found") == true)
        XCTAssertFalse(records.contains { $0["method"] != nil })
    }

    func testIsNonSteerableAndInterruptibleWithoutMutatingHistory() async throws {
        let summarizer = BlockingCompactionSummarizer()
        let fixture = try await makeStartedFixture(compactor: ThreadCompactor(
            keepRecentMessages: 2,
            perMessageTokenFloor: 0,
            summarizer: summarizer
        ))
        try await appendTurns(4, to: fixture)
        let store = threadStore(for: fixture)
        let threadUUID = try XCTUnwrap(UUID(uuidString: fixture.threadID))
        let messagesBefore = try store.load(threadUUID).messages
        let baseline = try await fixture.output.records().count

        try await sendRequest(
            id: 20,
            method: "thread/compact/start",
            params: ["threadId": fixture.threadID],
            to: fixture.session
        )
        await summarizer.waitUntilStarted()
        let activeRecords = Array(try await fixture.output.records().dropFirst(baseline))
        let started = try lifecycleParams(for: "turn/started", in: activeRecords)
        let turnID = try XCTUnwrap(started["turn"]?.objectValue?["id"]?.stringValue)

        try await sendRequest(
            id: 21,
            method: "turn/steer",
            params: [
                "threadId": fixture.threadID,
                "expectedTurnId": turnID,
                "input": [["type": "text", "text": "steer"]]
            ],
            to: fixture.session
        )
        try await sendRequest(
            id: 22,
            method: "turn/start",
            params: [
                "threadId": fixture.threadID,
                "input": [["type": "text", "text": "new turn"]]
            ],
            to: fixture.session
        )
        try await sendRequest(
            id: 23,
            method: "turn/interrupt",
            params: ["threadId": fixture.threadID, "turnId": turnID],
            to: fixture.session
        )
        await fixture.session.waitForActiveTurns()

        let records = Array(try await fixture.output.records().dropFirst(baseline))
        XCTAssertEqual(errorCode(for: 21, in: records), -32_600)
        XCTAssertTrue(errorMessage(for: 21, in: records)?.contains("not steerable") == true)
        XCTAssertEqual(errorCode(for: 22, in: records), -32_602)
        XCTAssertNotNil(result(for: 23, in: records))
        let completion = try lifecycleParams(for: "turn/completed", in: records, takingLast: true)
        XCTAssertEqual(completion["turn"]?.objectValue?["status"]?.stringValue, "interrupted")
        XCTAssertEqual(try store.load(threadUUID).messages, messagesBefore)
    }

    func testUserShellCommandSharesActiveCompactionTurnAndSurvivesInterruption() async throws {
        let summarizer = BlockingCompactionSummarizer()
        let fixture = try await makeStartedFixture(compactor: ThreadCompactor(
            keepRecentMessages: 2,
            perMessageTokenFloor: 0,
            summarizer: summarizer
        ))
        try await appendTurns(4, to: fixture)
        let baseline = try await fixture.output.records().count

        try await sendRequest(
            id: 20,
            method: "thread/compact/start",
            params: ["threadId": fixture.threadID],
            to: fixture.session
        )
        await summarizer.waitUntilStarted()
        let activeRecords = Array(try await fixture.output.records().dropFirst(baseline))
        let turnID = try XCTUnwrap(
            try lifecycleParams(for: "turn/started", in: activeRecords)["turn"]?
                .objectValue?["id"]?.stringValue
        )

        try await sendRequest(
            id: 21,
            method: "thread/shellCommand",
            params: ["threadId": fixture.threadID, "command": "printf compaction-shell"],
            to: fixture.session
        )
        let commandCompletion = try await waitForUserShellCompletion(
            fixture: fixture,
            after: baseline
        )
        XCTAssertEqual(commandCompletion["turnId"]?.stringValue, turnID)

        try await sendRequest(
            id: 22,
            method: "turn/interrupt",
            params: ["threadId": fixture.threadID, "turnId": turnID],
            to: fixture.session
        )
        await fixture.session.waitForActiveTurns()

        let records = Array(try await fixture.output.records().dropFirst(baseline))
        XCTAssertEqual(result(for: 21, in: records), [:])
        XCTAssertEqual(
            try lifecycleParams(for: "turn/completed", in: records, takingLast: true)["turn"]?
                .objectValue?["status"]?.stringValue,
            "interrupted"
        )
        let stored = try threadStore(for: fixture).load(try XCTUnwrap(UUID(uuidString: fixture.threadID)))
        XCTAssertTrue(stored.messages.contains {
            $0.role == .tool && $0.content.contains("compaction-shell")
        })
    }

    func testCompletedCompactionWaitsForAttachedUserShellCommand() async throws {
        let summarizer = ControlledCompactionSummarizer()
        let fixture = try await makeStartedFixture(compactor: ThreadCompactor(
            keepRecentMessages: 2,
            perMessageTokenFloor: 0,
            summarizer: summarizer
        ))
        try await appendTurns(4, to: fixture)
        let baseline = try await fixture.output.records().count

        try await sendRequest(
            id: 20,
            method: "thread/compact/start",
            params: ["threadId": fixture.threadID],
            to: fixture.session
        )
        await summarizer.waitUntilStarted()
        try await sendRequest(
            id: 21,
            method: "thread/shellCommand",
            params: [
                "threadId": fixture.threadID,
                "command": "sleep 0.2; printf compaction-waited"
            ],
            to: fixture.session
        )
        await summarizer.release()
        await fixture.session.waitForActiveTurns()

        let records = Array(try await fixture.output.records().dropFirst(baseline))
        let shellCompletionIndex = try XCTUnwrap(records.firstIndex { record in
            record["method"]?.stringValue == "item/completed"
                && record["params"]?.objectValue?["item"]?
                    .objectValue?["source"]?.stringValue == "userShell"
        })
        let turnCompletionIndex = try XCTUnwrap(records.lastIndex {
            $0["method"]?.stringValue == "turn/completed"
        })
        XCTAssertLessThan(shellCompletionIndex, turnCompletionIndex)
        let stored = try threadStore(for: fixture).load(
            try XCTUnwrap(UUID(uuidString: fixture.threadID))
        )
        XCTAssertTrue(stored.messages.contains {
            $0.role == .tool && $0.content.contains("compaction-waited")
        })
    }

    func testReportsPersistenceFailureInsteadOfInterruption() async throws {
        let summarizer = ControlledCompactionSummarizer()
        let fixture = try await makeStartedFixture(compactor: ThreadCompactor(
            keepRecentMessages: 2,
            perMessageTokenFloor: 0,
            summarizer: summarizer
        ))
        try await appendTurns(4, to: fixture)
        let baseline = try await fixture.output.records().count

        try await sendRequest(
            id: 20,
            method: "thread/compact/start",
            params: ["threadId": fixture.threadID],
            to: fixture.session
        )
        await summarizer.waitUntilStarted()
        let backup = try replaceThreadDirectoryWithFile(in: fixture.home)
        defer { restoreThreadDirectory(backup: backup, in: fixture.home) }

        await summarizer.release()
        await fixture.session.waitForActiveTurns()

        let records = Array(try await fixture.output.records().dropFirst(baseline))
        let completion = try lifecycleParams(for: "turn/completed", in: records, takingLast: true)
        let turn = try XCTUnwrap(completion["turn"]?.objectValue)
        XCTAssertEqual(turn["status"]?.stringValue, "failed")
        let message = turn["error"]?.objectValue?["message"]?.stringValue
        XCTAssertTrue(message?.localizedCaseInsensitiveContains("persistence") == true)
    }

    private func makeStartedFixture(
        compactor: ThreadCompactor = ThreadCompactor()
    ) async throws -> CompactionFixture {
        let home = try temporaryDirectory(prefix: "app-server-compaction-home")
        let workspace = try temporaryDirectory(prefix: "app-server-compaction-workspace")
        let output = CompactionOutputCollector()
        let session = try AppServerSession(
            request: CLIAppServerRequest(live: false, home: home),
            environment: [:],
            currentDirectory: workspace,
            runnerFactory: { configuration in
                AgentRunner(
                    llm: CompactionEchoLLM(),
                    safety: StaticSafetyReviewer(),
                    maxToolSteps: configuration.appConfig.maxToolSteps,
                    enablesImmediateActionPreflight: false,
                    compaction: AgentCompactionPolicy(compactor: compactor)
                )
            },
            sink: { line in await output.append(line) }
        )
        try await sendRequest(
            id: 1,
            method: "initialize",
            params: ["clientInfo": ["name": "QuillCodeTests", "version": "1"]],
            to: session
        )
        try await sendNotification(method: "initialized", params: [:], to: session)
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
        let thread = try XCTUnwrap(result(for: 2, in: records)?["thread"]?.objectValue)
        let threadID = try XCTUnwrap(thread["id"]?.stringValue)
        return CompactionFixture(
            session: session,
            output: output,
            home: home,
            threadID: threadID
        )
    }

    private func appendTurns(_ count: Int, to fixture: CompactionFixture) async throws {
        for index in 0..<count {
            try await sendRequest(
                id: 10 + index,
                method: "turn/start",
                params: [
                    "threadId": fixture.threadID,
                    "input": [["type": "text", "text": "turn \(index)"]]
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

    private func result(
        for id: Int,
        in records: [[String: CLIJSONValue]]
    ) -> [String: CLIJSONValue]? {
        records.first { $0["id"]?.numberValue == Double(id) }?["result"]?.objectValue
    }

    private func errorCode(for id: Int, in records: [[String: CLIJSONValue]]) -> Double? {
        let record = records.first { $0["id"]?.numberValue == Double(id) }
        return record?["error"]?.objectValue?["code"]?.numberValue
    }

    private func errorMessage(for id: Int, in records: [[String: CLIJSONValue]]) -> String? {
        let record = records.first { $0["id"]?.numberValue == Double(id) }
        return record?["error"]?.objectValue?["message"]?.stringValue
    }

    private func lifecycleParams(
        for method: String,
        in records: [[String: CLIJSONValue]],
        takingLast: Bool = false
    ) throws -> [String: CLIJSONValue] {
        let matching = records.filter { $0["method"]?.stringValue == method }
        let record = takingLast ? matching.last : matching.first
        return try XCTUnwrap(record?["params"]?.objectValue)
    }

    private func waitForUserShellCompletion(
        fixture: CompactionFixture,
        after baseline: Int
    ) async throws -> [String: CLIJSONValue] {
        for _ in 0..<400 {
            let records = Array(try await fixture.output.records().dropFirst(baseline))
            if let params = records.first(where: { record in
                record["method"]?.stringValue == "item/completed"
                    && record["params"]?.objectValue?["item"]?
                        .objectValue?["source"]?.stringValue == "userShell"
            })?["params"]?.objectValue {
                return params
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw CompactionTestError.missingUserShellCompletion
    }

    private func threadStore(for fixture: CompactionFixture) -> JSONThreadStore {
        JSONThreadStore(directory: fixture.home.appendingPathComponent("threads"))
    }

    private func temporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func replaceThreadDirectoryWithFile(in home: URL) throws -> URL {
        let threads = home.appendingPathComponent("threads", isDirectory: true)
        let backup = home.appendingPathComponent("threads-backup", isDirectory: true)
        try FileManager.default.moveItem(at: threads, to: backup)
        try Data("not a directory".utf8).write(to: threads)
        return backup
    }

    private func restoreThreadDirectory(backup: URL, in home: URL) {
        let threads = home.appendingPathComponent("threads", isDirectory: true)
        try? FileManager.default.removeItem(at: threads)
        try? FileManager.default.moveItem(at: backup, to: threads)
    }
}

private struct CompactionFixture {
    var session: AppServerSession
    var output: CompactionOutputCollector
    var home: URL
    var threadID: String
}

private actor CompactionOutputCollector {
    private var lines: [String] = []

    func append(_ line: String) {
        lines.append(line)
    }

    func records() throws -> [[String: CLIJSONValue]] {
        try lines.map { line in
            guard let record = try CLIJSONCodec.decode(line).objectValue else {
                throw CompactionTestError.invalidRecord
            }
            return record
        }
    }
}

private enum CompactionTestError: Error {
    case invalidRecord
    case missingUserShellCompletion
}

private struct CompactionEchoLLM: LLMClient {
    func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AgentAction {
        .say(userMessage)
    }
}

private actor BlockingCompactionSummarizer: ThreadCompactionSummarizing {
    private var started = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func summarize(
        sourceTitle: String,
        olderMessages: [ChatMessage],
        recentMessages: [ChatMessage]
    ) async throws -> String {
        _ = (sourceTitle, olderMessages, recentMessages)
        started = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
        try await Task.sleep(for: .seconds(60))
        return "must not be persisted"
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

private actor ControlledCompactionSummarizer: ThreadCompactionSummarizing {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func summarize(
        sourceTitle: String,
        olderMessages: [ChatMessage],
        recentMessages: [ChatMessage]
    ) async throws -> String {
        _ = (sourceTitle, olderMessages, recentMessages)
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        await withCheckedContinuation { releaseContinuation = $0 }
        return "controlled summary"
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
