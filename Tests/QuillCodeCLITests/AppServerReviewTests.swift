import Foundation
import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeReview
import QuillCodeSafety
@testable import QuillCodeCLI

final class AppServerReviewTests: XCTestCase {
    func testInlineReviewStreamsReviewModeAndPersistsOnlyValidatedReport() async throws {
        let llm = AppServerReviewLLM(actions: [
            .say("Historical answer."),
            .tool(ToolCall(
                name: WorkspaceCodeReviewSubmitTool.name,
                argumentsJSON: #"{"summary":"One issue found.","findings":[{"priority":"P2","title":"Validate the state","body":"The new path skips required validation.","path":"Sources/Feature.swift","line":12}]}"#
            )),
            .say("Internal reviewer chatter that must not enter the transcript.")
        ])
        let fixture = try await makeSession(llm: llm)
        let sourceID = try await startThread(in: fixture)

        try await fixture.request(
            id: 3,
            method: "turn/start",
            params: [
                "threadId": sourceID,
                "input": [["type": "text", "text": "Earlier question"]]
            ]
        )
        await fixture.session.waitForActiveTurns()

        try await fixture.request(
            id: 4,
            method: "review/start",
            params: [
                "threadId": sourceID,
                "target": ["type": "uncommittedChanges"]
            ]
        )
        await fixture.session.waitForActiveTurns()

        let records = try await fixture.output.records()
        let response = try XCTUnwrap(result(for: 4, in: records))
        XCTAssertEqual(response["reviewThreadId"]?.stringValue, sourceID)
        let responseTurn = try XCTUnwrap(response["turn"]?.objectValue)
        XCTAssertEqual(responseTurn["status"]?.stringValue, "inProgress")
        XCTAssertEqual(responseTurn["itemsView"]?.stringValue, "notLoaded")
        let responseItems = try XCTUnwrap(responseTurn["items"]?.arrayValue?.compactMap(\.objectValue))
        XCTAssertEqual(responseItems.count, 1)
        XCTAssertEqual(responseItems[0]["type"]?.stringValue, "userMessage")
        XCTAssertEqual(responseItems[0]["id"]?.stringValue, responseTurn["id"]?.stringValue)
        XCTAssertEqual(
            responseItems[0]["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue,
            "Review the current uncommitted changes."
        )

        let responseIndex = try XCTUnwrap(records.firstIndex { $0["id"]?.numberValue == 4 })
        let activeIndex = try XCTUnwrap(records.indices.first {
            $0 > responseIndex
                && records[$0]["method"]?.stringValue == "thread/status/changed"
        })
        XCTAssertLessThan(responseIndex, activeIndex)
        XCTAssertEqual(itemLifecycleCount("enteredReviewMode", in: records), 2)
        XCTAssertEqual(itemLifecycleCount("exitedReviewMode", in: records), 2)

        let completion = try XCTUnwrap(records.last {
            $0["method"]?.stringValue == "turn/completed"
        })
        let completedTurn = try XCTUnwrap(completion["params"]?.objectValue?["turn"]?.objectValue)
        XCTAssertEqual(completedTurn["status"]?.stringValue, "completed")
        let completedItems = try XCTUnwrap(
            completedTurn["items"]?.arrayValue?.compactMap(\.objectValue)
        )
        XCTAssertEqual(completedItems.last?["type"]?.stringValue, "agentMessage")
        XCTAssertTrue(completedItems.last?["text"]?.stringValue?.contains("[P2] Validate the state") == true)

        let stored = try XCTUnwrap(
            JSONThreadStore(directory: fixture.home.appendingPathComponent("threads")).list().first
        )
        XCTAssertEqual(stored.messages.filter { $0.role == .user }.map(\.content), [
            "Earlier question",
            "Review the current uncommitted changes."
        ])
        let assistantMessages = stored.messages.filter { $0.role == .assistant }.map(\.content)
        XCTAssertEqual(assistantMessages.count, 2)
        XCTAssertEqual(assistantMessages[0], "Historical answer.")
        XCTAssertTrue(assistantMessages[1].contains("One issue found."))
        XCTAssertFalse(assistantMessages[1].contains("Internal reviewer chatter"))

        let offeredTools = await llm.offeredToolNames()
        XCTAssertEqual(
            offeredTools,
            WorkspaceCodeReviewRunner.readableToolNames.union([WorkspaceCodeReviewSubmitTool.name])
        )
    }

    func testDetachedReviewForksDurableThreadBeforeResponding() async throws {
        let llm = AppServerReviewLLM(actions: [
            .tool(ToolCall(
                name: WorkspaceCodeReviewSubmitTool.name,
                argumentsJSON: #"{"summary":"No issues found.","findings":[]}"#
            )),
            .say("Done.")
        ])
        let fixture = try await makeSession(llm: llm)
        let sourceID = try await startThread(in: fixture)

        try await fixture.request(
            id: 3,
            method: "review/start",
            params: [
                "threadId": sourceID,
                "delivery": "detached",
                "target": ["type": "commit", "sha": "HEAD", "title": "Review fixture"]
            ]
        )
        await fixture.session.waitForActiveTurns()

        var records = try await fixture.output.records()
        let response = try XCTUnwrap(result(for: 3, in: records))
        let reviewID = try XCTUnwrap(response["reviewThreadId"]?.stringValue)
        XCTAssertNotEqual(reviewID, sourceID)
        let responseIndex = try XCTUnwrap(records.firstIndex { $0["id"]?.numberValue == 3 })
        let detachedStartedIndex = try XCTUnwrap(records.lastIndex {
            $0["method"]?.stringValue == "thread/started"
        })
        XCTAssertLessThan(detachedStartedIndex, responseIndex)
        XCTAssertEqual(itemLifecycleCount("enteredReviewMode", in: records), 0)
        XCTAssertEqual(itemLifecycleCount("exitedReviewMode", in: records), 0)

        try await fixture.request(
            id: 4,
            method: "thread/read",
            params: ["threadId": reviewID, "includeTurns": true]
        )
        records = try await fixture.output.records()
        let detached = try XCTUnwrap(result(for: 4, in: records)?["thread"]?.objectValue)
        XCTAssertEqual(detached["forkedFromId"]?.stringValue, sourceID)
        XCTAssertEqual(detached["ephemeral"]?.boolValue, false)
        XCTAssertEqual(detached["turns"]?.arrayValue?.count, 1)

        let stored = try JSONThreadStore(
            directory: fixture.home.appendingPathComponent("threads")
        ).list()
        XCTAssertEqual(stored.count, 2)
        let source = try XCTUnwrap(stored.first { $0.id.uuidString.lowercased() == sourceID })
        XCTAssertTrue(source.messages.isEmpty)
        let review = try XCTUnwrap(stored.first { $0.id.uuidString.lowercased() == reviewID })
        XCTAssertEqual(review.forkParentThreadID?.uuidString.lowercased(), sourceID)
        XCTAssertEqual(review.messages.filter { $0.role == .user }.first?.content, "Review commit HEAD: Review fixture")
    }

    func testReviewCanBeInterruptedThroughTurnInterrupt() async throws {
        let llm = AppServerBlockingReviewLLM()
        let fixture = try await makeSession(llm: llm)
        let threadID = try await startThread(in: fixture)

        try await fixture.request(
            id: 3,
            method: "review/start",
            params: [
                "threadId": threadID,
                "target": ["type": "custom", "instructions": "Focus on cancellation."]
            ]
        )
        await llm.waitUntilStarted()
        let records = try await fixture.output.records()
        let turnID = try XCTUnwrap(result(for: 3, in: records)?["turn"]?.objectValue?["id"]?.stringValue)
        try await fixture.request(
            id: 4,
            method: "turn/interrupt",
            params: ["threadId": threadID, "turnId": turnID]
        )
        await fixture.session.waitForActiveTurns()

        let completedRecords = try await fixture.output.records()
        let completed = try XCTUnwrap(completedRecords.last {
            $0["method"]?.stringValue == "turn/completed"
        })
        XCTAssertEqual(
            completed["params"]?.objectValue?["turn"]?.objectValue?["status"]?.stringValue,
            "interrupted"
        )
        XCTAssertEqual(itemLifecycleCount("enteredReviewMode", in: completedRecords), 2)
        XCTAssertEqual(itemLifecycleCount("exitedReviewMode", in: completedRecords), 2)
    }

    func testUserShellCommandSharesActiveReviewTurnAndSurvivesInterruption() async throws {
        let llm = AppServerBlockingReviewLLM()
        let fixture = try await makeSession(llm: llm)
        let threadID = try await startThread(in: fixture)
        let baseline = try await fixture.output.records().count

        try await fixture.request(
            id: 3,
            method: "review/start",
            params: [
                "threadId": threadID,
                "target": ["type": "custom", "instructions": "Wait for an inspection command."]
            ]
        )
        await llm.waitUntilStarted()
        let activeRecords = Array(try await fixture.output.records().dropFirst(baseline))
        let turnID = try XCTUnwrap(
            result(for: 3, in: activeRecords)?["turn"]?.objectValue?["id"]?.stringValue
        )

        try await fixture.request(
            id: 4,
            method: "thread/shellCommand",
            params: ["threadId": threadID, "command": "printf review-shell"]
        )
        let commandCompletion = try await waitForUserShellCompletion(
            fixture: fixture,
            after: baseline
        )
        XCTAssertEqual(commandCompletion["turnId"]?.stringValue, turnID)

        try await fixture.request(
            id: 5,
            method: "turn/interrupt",
            params: ["threadId": threadID, "turnId": turnID]
        )
        await fixture.session.waitForActiveTurns()

        let records = Array(try await fixture.output.records().dropFirst(baseline))
        XCTAssertEqual(result(for: 4, in: records), [:])
        let stored = try XCTUnwrap(
            JSONThreadStore(directory: fixture.home.appendingPathComponent("threads"))
                .listing().threads.first { $0.id.uuidString.lowercased() == threadID }
        )
        XCTAssertTrue(stored.messages.contains {
            $0.role == .tool && $0.content.contains("review-shell")
        })
    }

    func testCompletedReviewWaitsForAttachedUserShellCommand() async throws {
        let llm = ControlledReviewLLM(actions: [
            .tool(ToolCall(
                name: WorkspaceCodeReviewSubmitTool.name,
                argumentsJSON: #"{"summary":"No issues found.","findings":[]}"#
            )),
            .say("Done.")
        ])
        let fixture = try await makeSession(llm: llm)
        let threadID = try await startThread(in: fixture)
        let baseline = try await fixture.output.records().count

        try await fixture.request(
            id: 3,
            method: "review/start",
            params: [
                "threadId": threadID,
                "target": ["type": "custom", "instructions": "Wait for an inspection command."]
            ]
        )
        await llm.waitUntilStarted()
        try await fixture.request(
            id: 4,
            method: "thread/shellCommand",
            params: [
                "threadId": threadID,
                "command": "sleep 0.2; printf review-waited"
            ]
        )
        await llm.release()
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
        let stored = try XCTUnwrap(
            JSONThreadStore(directory: fixture.home.appendingPathComponent("threads"))
                .listing().threads.first { $0.id.uuidString.lowercased() == threadID }
        )
        XCTAssertTrue(stored.messages.contains {
            $0.role == .tool && $0.content.contains("review-waited")
        })
    }

    func testReviewRejectsMalformedTargetWithoutMutatingThread() async throws {
        let fixture = try await makeSession(llm: AppServerReviewLLM(actions: []))
        let threadID = try await startThread(in: fixture)

        try await fixture.request(
            id: 3,
            method: "review/start",
            params: [
                "threadId": threadID,
                "target": ["type": "baseBranch", "branch": "../main"]
            ]
        )

        let records = try await fixture.output.records()
        XCTAssertEqual(errorCode(for: 3, in: records), -32_602)
        let stored = try XCTUnwrap(
            JSONThreadStore(directory: fixture.home.appendingPathComponent("threads")).list().first
        )
        XCTAssertTrue(stored.messages.isEmpty)
    }

    private func makeSession(llm: any LLMClient) async throws -> AppServerReviewFixture {
        let home = try temporaryDirectory(prefix: "app-server-review-home")
        let workspace = try temporaryDirectory(prefix: "app-server-review-workspace")
        let output = AppServerReviewOutput()
        let session = try AppServerSession(
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
        return AppServerReviewFixture(
            session: session,
            output: output,
            home: home,
            workspace: workspace
        )
    }

    private func startThread(in fixture: AppServerReviewFixture) async throws -> String {
        try await fixture.request(
            id: 1,
            method: "initialize",
            params: ["clientInfo": ["name": "QuillCodeTests", "version": "1"]]
        )
        try await fixture.notify(method: "initialized")
        try await fixture.request(
            id: 2,
            method: "thread/start",
            params: [
                "cwd": fixture.workspace.path,
                "model": "trustedrouter/fast",
                "sandbox": "read-only"
            ]
        )
        let records = try await fixture.output.records()
        return try XCTUnwrap(
            result(for: 2, in: records)?["thread"]?.objectValue?["id"]?.stringValue
        )
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

    private func itemLifecycleCount(
        _ type: String,
        in records: [[String: CLIJSONValue]]
    ) -> Int {
        records.filter {
            ($0["method"]?.stringValue == "item/started"
                || $0["method"]?.stringValue == "item/completed")
                && $0["params"]?.objectValue?["item"]?.objectValue?["type"]?.stringValue == type
        }.count
    }

    private func waitForUserShellCompletion(
        fixture: AppServerReviewFixture,
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
        throw AppServerReviewTestError.missingUserShellCompletion
    }

    private func temporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

private struct AppServerReviewFixture {
    var session: AppServerSession
    var output: AppServerReviewOutput
    var home: URL
    var workspace: URL

    func request(id: Int, method: String, params: [String: Any]) async throws {
        try await send(["id": id, "method": method, "params": params])
    }

    func notify(method: String, params: [String: Any] = [:]) async throws {
        try await send(["method": method, "params": params])
    }

    private func send(_ object: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        await session.receive(data)
    }
}

private actor AppServerReviewOutput {
    private var lines: [String] = []

    func append(_ line: String) {
        lines.append(line)
    }

    func records() throws -> [[String: CLIJSONValue]] {
        try lines.map { line in
            guard let record = try CLIJSONCodec.decode(line).objectValue else {
                throw AppServerReviewTestError.invalidRecord
            }
            return record
        }
    }
}

private actor AppServerReviewLLM: LLMClient {
    private var actions: [AgentAction]
    private var toolNames: Set<String> = []

    init(actions: [AgentAction]) {
        self.actions = actions
    }

    func nextAction(
        thread _: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) -> AgentAction {
        if userMessage.contains("Perform a focused code review") {
            toolNames.formUnion(tools.map(\.name))
        }
        guard !actions.isEmpty else { return .say("Done.") }
        return actions.removeFirst()
    }

    func offeredToolNames() -> Set<String> { toolNames }
}

private actor AppServerBlockingReviewLLM: LLMClient {
    private var started = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func nextAction(
        thread _: ChatThread,
        userMessage _: String,
        tools _: [ToolDefinition]
    ) async throws -> AgentAction {
        started = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
        try await Task.sleep(for: .seconds(30))
        return .say("Unexpected completion.")
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private actor ControlledReviewLLM: LLMClient {
    private var actions: [AgentAction]
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(actions: [AgentAction]) {
        self.actions = actions
    }

    func nextAction(
        thread _: ChatThread,
        userMessage _: String,
        tools _: [ToolDefinition]
    ) async -> AgentAction {
        if !started {
            started = true
            startWaiters.forEach { $0.resume() }
            startWaiters.removeAll()
            await withCheckedContinuation { releaseContinuation = $0 }
        }
        return actions.isEmpty ? .say("Done.") : actions.removeFirst()
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

private enum AppServerReviewTestError: Error {
    case invalidRecord
    case missingUserShellCompletion
}
