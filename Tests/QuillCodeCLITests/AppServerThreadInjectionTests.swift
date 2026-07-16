import Foundation
import QuillCodeAgent
@testable import QuillCodeCLI
import QuillCodeCore
import QuillCodePersistence
import QuillCodeSafety
import XCTest

final class AppServerThreadInjectionTests: XCTestCase {
    func testInjectedItemsPersistAsModelOnlyHistoryAndStayOutOfThreadProjection() async throws {
        let fixture = try await makeFixture(llm: InjectionEchoLLM())
        let threadID = try await startThread(fixture)
        let items: [[String: Any]] = [
            responseMessage(role: "assistant", text: "Private prior answer"),
            ["type": "reasoning", "summary": []]
        ]

        try await request(
            fixture,
            id: 2,
            method: "thread/inject_items",
            params: ["threadId": threadID, "items": items]
        )
        try await request(
            fixture,
            id: 3,
            method: "thread/read",
            params: ["threadId": threadID]
        )

        let records = try await fixture.output.records()
        XCTAssertEqual(result(2, in: records), [:])
        XCTAssertEqual(
            result(3, in: records)?["thread"]?.objectValue?["turns"]?.arrayValue,
            []
        )
        let stored = try JSONThreadStore(
            directory: fixture.home.appendingPathComponent("threads")
        ).load(try XCTUnwrap(UUID(uuidString: threadID)))
        XCTAssertTrue(stored.messages.isEmpty)
        XCTAssertEqual(stored.modelContextItems.count, 2)
        XCTAssertNil(stored.modelContextItems.first?.afterMessageID)
        XCTAssertEqual(
            stored.modelContextItems.first?.responseItem.objectValue?["type"]?.stringValue,
            "message"
        )
    }

    func testInjectionValidationMatchesCodexRequestErrors() async throws {
        let fixture = try await makeFixture(llm: InjectionEchoLLM())
        let threadID = try await startThread(fixture)
        let cases: [(Int, [String: Any], String)] = [
            (2, ["threadId": threadID, "items": []], "items must not be empty"),
            (
                3,
                ["threadId": threadID, "items": "not-an-array"],
                "Invalid request: invalid type: string \"not-an-array\", expected a sequence"
            ),
            (
                4,
                ["threadId": threadID, "items": ["not-an-item"]],
                "items[0] is not a valid response item: invalid type: string \"not-an-item\", expected internally tagged enum ResponseItem"
            ),
            (
                5,
                ["threadId": threadID, "items": [["role": "assistant"]]],
                "items[0] is not a valid response item: missing field `type`"
            ),
            (
                6,
                [
                    "threadId": threadID,
                    "items": [responseImageMessage(url: "https://example.com/private.png")]
                ],
                "remote image URLs are not supported; use an inline data URL instead"
            )
        ]

        for (id, params, _) in cases {
            try await request(fixture, id: id, method: "thread/inject_items", params: params)
        }

        let records = try await fixture.output.records()
        for (id, _, expectedMessage) in cases {
            XCTAssertEqual(error(id, in: records)?["code"]?.numberValue, -32600)
            XCTAssertEqual(error(id, in: records)?["message"]?.stringValue, expectedMessage)
        }
    }

    func testInlineImageAndUnknownMessageRoleAreAccepted() async throws {
        let fixture = try await makeFixture(llm: InjectionEchoLLM())
        let threadID = try await startThread(fixture)

        try await request(
            fixture,
            id: 2,
            method: "thread/inject_items",
            params: [
                "threadId": threadID,
                "items": [responseImageMessage(url: "data:image/png;base64,aGVsbG8=")]
            ]
        )
        try await request(
            fixture,
            id: 3,
            method: "thread/inject_items",
            params: [
                "threadId": threadID,
                "items": [responseMessage(role: "future_role", text: "Forward compatible")]
            ]
        )

        let records = try await fixture.output.records()
        XCTAssertEqual(result(2, in: records), [:])
        XCTAssertEqual(result(3, in: records), [:])
    }

    func testArchivedAndUnknownThreadsAreUnavailableForInjection() async throws {
        let fixture = try await makeFixture(llm: InjectionEchoLLM())
        let threadID = try await startThread(fixture)
        try await request(
            fixture,
            id: 2,
            method: "thread/archive",
            params: ["threadId": threadID]
        )
        try await request(
            fixture,
            id: 3,
            method: "thread/inject_items",
            params: [
                "threadId": threadID,
                "items": [responseMessage(role: "assistant", text: "Hidden")]
            ]
        )
        let unknown = UUID().uuidString.lowercased()
        try await request(
            fixture,
            id: 4,
            method: "thread/inject_items",
            params: [
                "threadId": unknown,
                "items": [responseMessage(role: "assistant", text: "Hidden")]
            ]
        )

        let records = try await fixture.output.records()
        XCTAssertEqual(error(3, in: records)?["message"]?.stringValue, "thread not found: \(threadID)")
        XCTAssertEqual(error(4, in: records)?["message"]?.stringValue, "thread not found: \(unknown)")
    }

    func testInjectionDuringActiveTurnSurvivesCompletionAndReachesNextModelRequest() async throws {
        let llm = InjectionBlockingLLM()
        let fixture = try await makeFixture(llm: llm)
        let threadID = try await startThread(fixture)
        try await request(
            fixture,
            id: 2,
            method: "turn/start",
            params: [
                "threadId": threadID,
                "input": [["type": "text", "text": "Hold the first turn"]]
            ]
        )
        await llm.waitUntilFirstRequestStarts()

        try await request(
            fixture,
            id: 3,
            method: "thread/inject_items",
            params: [
                "threadId": threadID,
                "items": [responseMessage(role: "assistant", text: "Concurrent hidden context")]
            ]
        )
        await llm.releaseFirstRequest()
        await fixture.session.waitForActiveTurns()

        let storedAfterFirst = try JSONThreadStore(
            directory: fixture.home.appendingPathComponent("threads")
        ).load(try XCTUnwrap(UUID(uuidString: threadID)))
        XCTAssertEqual(storedAfterFirst.modelContextItems.count, 1)

        try await request(
            fixture,
            id: 4,
            method: "turn/start",
            params: [
                "threadId": threadID,
                "input": [["type": "text", "text": "Read the hidden context"]]
            ]
        )
        await fixture.session.waitForActiveTurns()

        let observedContextCounts = await llm.modelContextCounts()
        XCTAssertEqual(observedContextCounts, [0, 1])
        let records = try await fixture.output.records()
        XCTAssertEqual(result(3, in: records), [:])
    }
}

private extension AppServerThreadInjectionTests {
    func makeFixture(llm: any LLMClient) async throws -> InjectionFixture {
        let home = try temporaryDirectory(prefix: "thread-injection-home")
        let workspace = try temporaryDirectory(prefix: "thread-injection-workspace")
        let output = InjectionOutputCollector()
        let session = try AppServerSession(
            request: CLIAppServerRequest(live: false, home: home),
            environment: [:],
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
        return InjectionFixture(session: session, output: output, home: home, workspace: workspace)
    }

    func startThread(_ fixture: InjectionFixture) async throws -> String {
        try await request(
            fixture,
            id: 100,
            method: "initialize",
            params: ["clientInfo": ["name": "ThreadInjectionTests", "version": "1"]]
        )
        try await notify(fixture, method: "initialized", params: [:])
        try await request(
            fixture,
            id: 1,
            method: "thread/start",
            params: [
                "cwd": fixture.workspace.path,
                "model": "trustedrouter/fast",
                "sandbox": "read-only"
            ]
        )
        let records = try await fixture.output.records()
        return try XCTUnwrap(
            result(1, in: records)?["thread"]?.objectValue?["id"]?.stringValue
        )
    }

    func request(
        _ fixture: InjectionFixture,
        id: Int,
        method: String,
        params: [String: Any]
    ) async throws {
        try await send(["id": id, "method": method, "params": params], to: fixture.session)
    }

    func notify(
        _ fixture: InjectionFixture,
        method: String,
        params: [String: Any]
    ) async throws {
        try await send(["method": method, "params": params], to: fixture.session)
    }

    func send(_ object: [String: Any], to session: AppServerSession) async throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        await session.receive(data)
    }

    func result(
        _ id: Int,
        in records: [[String: CLIJSONValue]]
    ) -> [String: CLIJSONValue]? {
        records.first { $0["id"]?.numberValue == Double(id) }?["result"]?.objectValue
    }

    func error(
        _ id: Int,
        in records: [[String: CLIJSONValue]]
    ) -> [String: CLIJSONValue]? {
        records.first { $0["id"]?.numberValue == Double(id) }?["error"]?.objectValue
    }

    func responseMessage(role: String, text: String) -> [String: Any] {
        [
            "type": "message",
            "role": role,
            "content": [["type": "output_text", "text": text]]
        ]
    }

    func responseImageMessage(url: String) -> [String: Any] {
        [
            "type": "message",
            "role": "user",
            "content": [["type": "input_image", "image_url": url, "detail": "high"]]
        ]
    }

    func temporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

private struct InjectionFixture {
    let session: AppServerSession
    let output: InjectionOutputCollector
    let home: URL
    let workspace: URL
}

private actor InjectionOutputCollector {
    private var lines: [String] = []

    func append(_ line: String) {
        lines.append(line)
    }

    func records() throws -> [[String: CLIJSONValue]] {
        try lines.map { line in
            guard let object = try CLIJSONCodec.decode(line).objectValue else {
                throw InjectionTestError.invalidRecord
            }
            return object
        }
    }
}

private enum InjectionTestError: Error {
    case invalidRecord
}

private struct InjectionEchoLLM: LLMClient {
    func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AgentAction {
        .say("Echo: \(userMessage)")
    }
}

private actor InjectionBlockingLLM: LLMClient {
    private var invocationCount = 0
    private var observedModelContextCounts: [Int] = []
    private var firstStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstRelease: CheckedContinuation<Void, Never>?

    func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AgentAction {
        invocationCount += 1
        observedModelContextCounts.append(thread.modelContextItems.count)
        if invocationCount == 1 {
            firstStarted = true
            startWaiters.forEach { $0.resume() }
            startWaiters.removeAll()
            await withCheckedContinuation { firstRelease = $0 }
        }
        return .say("Completed request \(invocationCount)")
    }

    func waitUntilFirstRequestStarts() async {
        guard !firstStarted else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func releaseFirstRequest() {
        firstRelease?.resume()
        firstRelease = nil
    }

    func modelContextCounts() -> [Int] {
        observedModelContextCounts
    }
}
