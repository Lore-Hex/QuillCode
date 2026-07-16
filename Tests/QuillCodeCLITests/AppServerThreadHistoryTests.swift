import Foundation
import QuillCodeAgent
@testable import QuillCodeCLI
import QuillCodeCore
import QuillCodePersistence
import QuillCodeSafety
import XCTest

final class AppServerThreadHistoryTests: XCTestCase {
    func testTurnProjectionUsesDurableTranscriptOrderWhenTimestampsCollide() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let firstTurnID = "first-turn"
        let shellTurnID = "shell-turn"
        let secondTurnID = "second-turn"
        let thread = ChatThread(
            messages: [
                ChatMessage(
                    role: .user,
                    content: "First",
                    turnID: firstTurnID,
                    createdAt: timestamp
                ),
                ChatMessage(
                    role: .assistant,
                    content: "First answer",
                    turnID: firstTurnID,
                    createdAt: timestamp
                ),
                ChatMessage(
                    role: .tool,
                    content: "shell output",
                    turnID: shellTurnID,
                    createdAt: timestamp
                ),
                ChatMessage(
                    role: .user,
                    content: "Second",
                    turnID: secondTurnID,
                    createdAt: timestamp
                ),
                ChatMessage(
                    role: .assistant,
                    content: "Second answer",
                    turnID: secondTurnID,
                    createdAt: timestamp
                )
            ],
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let record = AppServerThreadRecord(
            thread: thread,
            settings: AppServerThreadSettings(
                cwd: URL(fileURLWithPath: "/tmp"),
                userShellTurns: [
                    AppServerUserShellTurnRecord(
                        id: shellTurnID,
                        startedAt: timestamp,
                        completedAt: timestamp
                    )
                ]
            )
        )

        let turnIDs = AppServerThreadHistoryProjection.turns(record).compactMap {
            $0.objectValue?["id"]?.stringValue
        }

        XCTAssertEqual(turnIDs, [firstTurnID, shellTurnID, secondTurnID])
    }

    func testPaginationLimitsMatchCodexUnsignedAndLoadedListSemantics() throws {
        XCTAssertEqual(try AppServerThreadPagination.boundedLimit(nil), 25)
        XCTAssertEqual(try AppServerThreadPagination.boundedLimit(0), 1)
        XCTAssertEqual(try AppServerThreadPagination.boundedLimit(101), 100)
        XCTAssertEqual(try AppServerThreadPagination.loadedLimit(nil, total: 150), 150)
        XCTAssertEqual(try AppServerThreadPagination.loadedLimit(0, total: 150), 1)
        XCTAssertEqual(try AppServerThreadPagination.loadedLimit(150, total: 150), 150)

        for invalid in [-1, Int(UInt32.max) + 1] {
            XCTAssertThrowsError(try AppServerThreadPagination.boundedLimit(invalid)) { error in
                XCTAssertEqual((error as? AppServerRPCError)?.code, -32_600)
            }
        }
    }

    func testThreadItemsListPagesFullItemsAcrossTurnFiltersAndDirections() async throws {
        let fixture = try await makeFixture(llm: ThreadHistoryScriptedLLM(actions: [
            .say("First answer"),
            .say("Second answer")
        ]))
        try await initialize(fixture)
        let threadID = try await startThread(fixture, requestID: 1)
        let firstTurnID = try await runTurn(
            fixture,
            requestID: 2,
            threadID: threadID,
            text: "First question"
        )
        let secondTurnID = try await runTurn(
            fixture,
            requestID: 3,
            threadID: threadID,
            text: "Second question"
        )

        try await request(
            fixture,
            id: 4,
            method: "thread/items/list",
            params: ["threadId": threadID]
        )
        try await request(
            fixture,
            id: 5,
            method: "thread/items/list",
            params: ["threadId": threadID, "limit": 1]
        )
        var records = try await fixture.output.records()
        let allItems = try XCTUnwrap(result(4, records)?["data"]?.arrayValue)
        XCTAssertEqual(allItems.compactMap(entryTurnID), [
            firstTurnID,
            firstTurnID,
            secondTurnID,
            secondTurnID
        ])
        XCTAssertEqual(allItems.compactMap(entryItemType), [
            "userMessage",
            "agentMessage",
            "userMessage",
            "agentMessage"
        ])
        XCTAssertEqual(entryItem(allItems[0])?["content"]?.arrayValue?.first?
            .objectValue?["text"]?.stringValue, "First question")
        XCTAssertEqual(entryItem(allItems[1])?["text"]?.stringValue, "First answer")

        let firstPage = try XCTUnwrap(result(5, records))
        let firstEntry = try XCTUnwrap(firstPage["data"]?.arrayValue?.first)
        let nextCursor = try XCTUnwrap(firstPage["nextCursor"]?.stringValue)
        XCTAssertEqual(entryTurnID(firstEntry), firstTurnID)
        XCTAssertNotNil(firstPage["backwardsCursor"]?.stringValue)

        try await request(
            fixture,
            id: 6,
            method: "thread/items/list",
            params: ["threadId": threadID, "limit": 1, "cursor": nextCursor]
        )
        try await request(
            fixture,
            id: 7,
            method: "thread/items/list",
            params: [
                "threadId": threadID,
                "turnId": secondTurnID,
                "cursor": nextCursor,
                "limit": 100
            ]
        )
        records = try await fixture.output.records()
        let secondPage = try XCTUnwrap(result(6, records))
        let secondEntry = try XCTUnwrap(secondPage["data"]?.arrayValue?.first)
        XCTAssertEqual(entryTurnID(secondEntry), firstTurnID)
        XCTAssertNotEqual(entryItemID(firstEntry), entryItemID(secondEntry))
        let backwardsCursor = try XCTUnwrap(secondPage["backwardsCursor"]?.stringValue)
        XCTAssertEqual(
            result(7, records)?["data"]?.arrayValue?.compactMap(entryTurnID),
            [secondTurnID, secondTurnID]
        )

        try await request(
            fixture,
            id: 8,
            method: "thread/items/list",
            params: [
                "threadId": threadID,
                "limit": 2,
                "cursor": backwardsCursor,
                "sortDirection": "desc"
            ]
        )
        try await request(
            fixture,
            id: 9,
            method: "thread/items/list",
            params: ["threadId": threadID, "turnId": "missing-turn"]
        )
        try await request(
            fixture,
            id: 10,
            method: "thread/items/list",
            params: ["threadId": threadID, "sortDirection": "sideways"]
        )
        try await request(
            fixture,
            id: 11,
            method: "thread/items/list",
            params: ["threadId": threadID, "limit": -1]
        )
        try await request(
            fixture,
            id: 12,
            method: "thread/items/list",
            params: ["threadId": threadID, "cursor": "malformed"]
        )
        records = try await fixture.output.records()
        XCTAssertEqual(
            result(8, records)?["data"]?.arrayValue?.compactMap(entryItemID),
            [entryItemID(secondEntry), entryItemID(firstEntry)].compactMap { $0 }
        )
        XCTAssertEqual(result(9, records)?["data"]?.arrayValue, [])
        XCTAssertEqual(error(10, records)?["code"]?.numberValue, -32_600)
        XCTAssertEqual(
            error(10, records)?["message"]?.stringValue,
            "Invalid request: unknown variant `sideways`, expected `asc` or `desc`"
        )
        XCTAssertEqual(error(11, records)?["code"]?.numberValue, -32_600)
        XCTAssertEqual(error(12, records)?["code"]?.numberValue, -32_600)

        let emptyThreadID = try await startThread(fixture, requestID: 13)
        try await request(
            fixture,
            id: 14,
            method: "thread/items/list",
            params: ["threadId": emptyThreadID, "cursor": "ignored-while-empty"]
        )
        records = try await fixture.output.records()
        XCTAssertEqual(result(14, records)?["data"]?.arrayValue, [])
        XCTAssertEqual(result(14, records)?["nextCursor"], .null)
        XCTAssertEqual(result(14, records)?["backwardsCursor"], .null)
    }

    func testThreadSearchUsesTranscriptContentAndHonorsArchiveAndSourceFilters() async throws {
        let fixture = try await makeFixture(llm: ThreadHistoryEchoLLM())
        try await initialize(fixture)
        let threadID = try await startThread(fixture, requestID: 1)
        try await request(
            fixture,
            id: 2,
            method: "thread/name/set",
            params: ["threadId": threadID, "name": "TitleOnlyNeedle"]
        )
        try await request(
            fixture,
            id: 3,
            method: "thread/search",
            params: ["searchTerm": "TitleOnlyNeedle"]
        )
        try await runTurn(
            fixture,
            requestID: 4,
            threadID: threadID,
            text: "Find this Transcript Search Needle"
        )
        try await request(
            fixture,
            id: 5,
            method: "thread/search",
            params: ["searchTerm": "transcript search needle"]
        )
        try await request(
            fixture,
            id: 6,
            method: "thread/search",
            params: ["searchTerm": "transcript", "sourceKinds": ["cli"]]
        )
        try await request(
            fixture,
            id: 7,
            method: "thread/search",
            params: ["searchTerm": "  \n "]
        )
        try await request(
            fixture,
            id: 8,
            method: "thread/archive",
            params: ["threadId": threadID]
        )
        try await request(
            fixture,
            id: 9,
            method: "thread/search",
            params: ["searchTerm": "transcript"]
        )
        try await request(
            fixture,
            id: 10,
            method: "thread/search",
            params: ["searchTerm": "transcript", "archived": true]
        )
        try await request(
            fixture,
            id: 11,
            method: "thread/search",
            params: ["searchTerm": "absent", "limit": -1]
        )
        try await request(
            fixture,
            id: 12,
            method: "thread/search",
            params: ["searchTerm": "x", "sortDirection": "bogus"]
        )
        try await request(
            fixture,
            id: 13,
            method: "thread/search",
            params: ["searchTerm": "x", "sortKey": "bogus"]
        )
        try await request(
            fixture,
            id: 14,
            method: "thread/search",
            params: ["searchTerm": "x", "sourceKinds": ["bogus"]]
        )
        try await request(
            fixture,
            id: 15,
            method: "thread/search",
            params: ["searchTerm": "x", "archived": "false"]
        )

        let records = try await fixture.output.records()
        XCTAssertEqual(result(3, records)?["data"]?.arrayValue, [])

        let match = try XCTUnwrap(result(5, records)?["data"]?.arrayValue?.first?.objectValue)
        XCTAssertEqual(match["thread"]?.objectValue?["id"]?.stringValue, threadID)
        XCTAssertEqual(match["snippet"]?.stringValue, "Find this Transcript Search Needle")
        XCTAssertEqual(result(6, records)?["data"]?.arrayValue, [])
        XCTAssertEqual(error(7, records)?["code"]?.numberValue, -32_600)
        XCTAssertEqual(
            error(7, records)?["message"]?.stringValue,
            "thread/search requires a non-empty searchTerm"
        )
        XCTAssertEqual(result(9, records)?["data"]?.arrayValue, [])
        XCTAssertEqual(
            result(10, records)?["data"]?.arrayValue?.first?.objectValue?["thread"]?
                .objectValue?["id"]?.stringValue,
            threadID
        )
        XCTAssertEqual(error(11, records)?["code"]?.numberValue, -32_600)
        for requestID in 12...15 {
            XCTAssertEqual(error(requestID, records)?["code"]?.numberValue, -32_600)
        }
        XCTAssertEqual(
            error(12, records)?["message"]?.stringValue,
            "Invalid request: unknown variant `bogus`, expected `asc` or `desc`"
        )
        XCTAssertEqual(
            error(13, records)?["message"]?.stringValue,
            "Invalid request: unknown variant `bogus`, expected one of `created_at`, "
                + "`updated_at`, `recency_at`"
        )
        XCTAssertEqual(
            error(14, records)?["message"]?.stringValue,
            "Invalid request: unknown variant `bogus`, expected "
                + AppServerThreadSourceKind.expectedValues
        )
        XCTAssertEqual(
            error(15, records)?["message"]?.stringValue,
            "Invalid request: invalid type: string \"false\", expected a boolean"
        )
    }

    func testLoadedThreadsAreConnectionScopedAndCursorPaged() async throws {
        let fixture = try await makeFixture(llm: ThreadHistoryEchoLLM())
        try await initialize(fixture)
        let firstID = try await startThread(fixture, requestID: 1)
        let secondID = try await startThread(fixture, requestID: 2)
        let expected = [firstID, secondID].sorted()

        try await request(fixture, id: 3, method: "thread/loaded/list", params: ["limit": 0])
        var records = try await fixture.output.records()
        let firstPage = try XCTUnwrap(result(3, records))
        XCTAssertEqual(firstPage["data"]?.arrayValue?.compactMap(\.stringValue), [expected[0]])
        XCTAssertEqual(firstPage["nextCursor"]?.stringValue, expected[0])

        try await request(
            fixture,
            id: 4,
            method: "thread/loaded/list",
            params: ["cursor": expected[0], "limit": 1]
        )
        records = try await fixture.output.records()
        XCTAssertEqual(result(4, records)?["data"]?.arrayValue?.compactMap(\.stringValue), [expected[1]])

        let fresh = try await makeFixture(
            home: fixture.home,
            workspace: fixture.workspace,
            llm: ThreadHistoryEchoLLM(),
            ownsDirectories: false
        )
        try await initialize(fresh)
        try await request(
            fresh,
            id: 5,
            method: "thread/loaded/list",
            params: ["cursor": "ignored-while-empty"]
        )
        var freshRecords = try await fresh.output.records()
        XCTAssertEqual(result(5, freshRecords)?["data"]?.arrayValue, [])

        try await request(
            fresh,
            id: 6,
            method: "thread/resume",
            params: ["threadId": firstID]
        )
        try await request(
            fresh,
            id: 7,
            method: "thread/loaded/list",
            params: ["cursor": "malformed"]
        )
        try await request(
            fresh,
            id: 8,
            method: "thread/delete",
            params: ["threadId": firstID]
        )
        try await request(fresh, id: 9, method: "thread/loaded/list", params: [:])
        try await request(
            fresh,
            id: 10,
            method: "thread/loaded/list",
            params: ["limit": -1]
        )

        freshRecords = try await fresh.output.records()
        XCTAssertEqual(error(7, freshRecords)?["code"]?.numberValue, -32_600)
        XCTAssertEqual(result(9, freshRecords)?["data"]?.arrayValue, [])
        XCTAssertEqual(error(10, freshRecords)?["code"]?.numberValue, -32_600)
    }

    func testTurnHistorySupportsViewsStableCursorsAndValidation() async throws {
        let llm = ThreadHistoryScriptedLLM(actions: [
            .tool(ToolCall(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: #"{"cmd":"printf history-tool"}"#
            )),
            .say("First answer"),
            .say("Second answer"),
            .say("Third answer")
        ])
        let fixture = try await makeFixture(llm: llm)
        try await initialize(fixture)
        let threadID = try await startThread(fixture, requestID: 1, sandbox: "workspace-write")
        let firstTurn = try await runTurn(
            fixture,
            requestID: 2,
            threadID: threadID,
            text: "Run the history command"
        )
        let secondTurn = try await runTurn(
            fixture,
            requestID: 3,
            threadID: threadID,
            text: "Second question"
        )
        let thirdTurn = try await runTurn(
            fixture,
            requestID: 4,
            threadID: threadID,
            text: "Third question"
        )

        try await request(
            fixture,
            id: 5,
            method: "thread/turns/list",
            params: ["threadId": threadID, "limit": 2]
        )
        var records = try await fixture.output.records()
        let firstPage = try XCTUnwrap(result(5, records))
        let firstPageTurns = try XCTUnwrap(firstPage["data"]?.arrayValue)
        XCTAssertEqual(turnIDs(firstPageTurns), [thirdTurn, secondTurn])
        XCTAssertTrue(firstPageTurns.allSatisfy { turn in
            turn.objectValue?["itemsView"]?.stringValue == "summary"
                && itemTypes(turn) == ["userMessage", "agentMessage"]
        })
        let nextCursor = try XCTUnwrap(firstPage["nextCursor"]?.stringValue)

        try await request(
            fixture,
            id: 6,
            method: "thread/turns/list",
            params: ["threadId": threadID, "limit": 2, "cursor": nextCursor]
        )
        records = try await fixture.output.records()
        let secondPage = try XCTUnwrap(result(6, records))
        XCTAssertEqual(turnIDs(secondPage["data"]?.arrayValue ?? []), [firstTurn])
        let backwardsCursor = try XCTUnwrap(secondPage["backwardsCursor"]?.stringValue)

        try await request(
            fixture,
            id: 7,
            method: "thread/turns/list",
            params: [
                "threadId": threadID,
                "limit": 2,
                "cursor": backwardsCursor,
                "sortDirection": "asc"
            ]
        )
        try await request(
            fixture,
            id: 8,
            method: "thread/turns/list",
            params: [
                "threadId": threadID,
                "limit": 1,
                "sortDirection": "asc",
                "itemsView": "full"
            ]
        )
        try await request(
            fixture,
            id: 9,
            method: "thread/turns/list",
            params: ["threadId": threadID, "itemsView": "notLoaded"]
        )
        try await request(
            fixture,
            id: 10,
            method: "thread/turns/list",
            params: ["threadId": threadID, "itemsView": "bogus"]
        )
        try await request(
            fixture,
            id: 11,
            method: "thread/turns/list",
            params: ["threadId": threadID, "sortDirection": "sideways"]
        )
        try await request(
            fixture,
            id: 12,
            method: "thread/turns/list",
            params: ["threadId": threadID, "limit": -1]
        )
        try await request(
            fixture,
            id: 13,
            method: "thread/turns/list",
            params: ["threadId": threadID, "cursor": "malformed"]
        )
        try await request(
            fixture,
            id: 14,
            method: "thread/turns/items/list",
            params: ["threadId": threadID, "turnId": firstTurn]
        )

        records = try await fixture.output.records()
        XCTAssertEqual(
            turnIDs(result(7, records)?["data"]?.arrayValue ?? []),
            [firstTurn, secondTurn]
        )
        let fullTurn = try XCTUnwrap(result(8, records)?["data"]?.arrayValue?.first)
        XCTAssertEqual(fullTurn.objectValue?["id"]?.stringValue, firstTurn)
        XCTAssertTrue(
            itemTypes(fullTurn).contains("commandExecution"),
            "Expected persisted shell history, got \(itemTypes(fullTurn))"
        )
        XCTAssertTrue((result(9, records)?["data"]?.arrayValue ?? []).allSatisfy {
            $0.objectValue?["items"]?.arrayValue == []
        })
        XCTAssertEqual(error(10, records)?["code"]?.numberValue, -32_600)
        XCTAssertEqual(
            error(10, records)?["message"]?.stringValue,
            "Invalid request: unknown variant `bogus`, expected one of "
                + "`notLoaded`, `summary`, `full`"
        )
        XCTAssertEqual(error(11, records)?["code"]?.numberValue, -32_600)
        XCTAssertEqual(
            error(11, records)?["message"]?.stringValue,
            "Invalid request: unknown variant `sideways`, expected `asc` or `desc`"
        )
        XCTAssertEqual(error(12, records)?["code"]?.numberValue, -32_600)
        XCTAssertEqual(
            error(12, records)?["message"]?.stringValue,
            "Invalid request: invalid value: integer `-1`, expected u32"
        )
        XCTAssertEqual(error(13, records)?["code"]?.numberValue, -32_600)
        XCTAssertEqual(error(14, records)?["code"]?.numberValue, -32_601)
        XCTAssertEqual(
            error(14, records)?["message"]?.stringValue,
            "thread/turns/items/list is not supported yet"
        )

        let emptyID = try await startThread(fixture, requestID: 15)
        try await request(
            fixture,
            id: 16,
            method: "thread/turns/list",
            params: ["threadId": emptyID, "cursor": "ignored-while-empty"]
        )
        records = try await fixture.output.records()
        XCTAssertEqual(result(16, records)?["data"]?.arrayValue, [])
    }

    func testPersistedTurnHistoryReconstructsShellOutputAfterReconnect() async throws {
        let fixture = try await makeFixture(llm: ThreadHistoryScriptedLLM(actions: [
            .tool(ToolCall(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: #"{"cmd":"printf persisted-history"}"#
            )),
            .say("Persisted answer")
        ]))
        try await initialize(fixture)
        let threadID = try await startThread(fixture, requestID: 1, sandbox: "workspace-write")
        _ = try await runTurn(
            fixture,
            requestID: 2,
            threadID: threadID,
            text: "Run persisted history"
        )

        let reconnected = try await makeFixture(
            home: fixture.home,
            workspace: fixture.workspace,
            llm: ThreadHistoryEchoLLM(),
            ownsDirectories: false
        )
        try await initialize(reconnected)
        try await request(
            reconnected,
            id: 3,
            method: "thread/resume",
            params: ["threadId": threadID]
        )
        try await request(
            reconnected,
            id: 4,
            method: "thread/turns/list",
            params: ["threadId": threadID, "itemsView": "full"]
        )

        let records = try await reconnected.output.records()
        let turn = try XCTUnwrap(result(4, records)?["data"]?.arrayValue?.first)
        let command = try XCTUnwrap(turn.objectValue?["items"]?.arrayValue?.first {
            $0.objectValue?["type"]?.stringValue == "commandExecution"
        }?.objectValue)
        XCTAssertEqual(command["status"]?.stringValue, "completed")
        XCTAssertEqual(command["aggregatedOutput"]?.stringValue, "persisted-history")
    }

    func testPersistedHistoryKeepsRepeatedMessagesInTheirOriginalTurns() async throws {
        let fixture = try await makeFixture(llm: ThreadHistoryScriptedLLM(actions: [
            .say("Repeated answer"),
            .say("Repeated answer")
        ]))
        try await initialize(fixture)
        let threadID = try await startThread(fixture, requestID: 1)
        let firstTurnID = try await runTurn(
            fixture,
            requestID: 2,
            threadID: threadID,
            text: "Repeated question"
        )
        let secondTurnID = try await runTurn(
            fixture,
            requestID: 3,
            threadID: threadID,
            text: "Repeated question"
        )

        let reconnected = try await makeFixture(
            home: fixture.home,
            workspace: fixture.workspace,
            llm: ThreadHistoryEchoLLM(),
            ownsDirectories: false
        )
        try await initialize(reconnected)
        try await request(
            reconnected,
            id: 4,
            method: "thread/turns/list",
            params: [
                "threadId": threadID,
                "itemsView": "full",
                "sortDirection": "asc"
            ]
        )

        let records = try await reconnected.output.records()
        let turns = try XCTUnwrap(result(4, records)?["data"]?.arrayValue)
        XCTAssertEqual(turnIDs(turns), [firstTurnID, secondTurnID])
        XCTAssertEqual(turns.map(itemTypes), [
            ["userMessage", "agentMessage"],
            ["userMessage", "agentMessage"]
        ])
        XCTAssertTrue(turns.allSatisfy { turn in
            turn.objectValue?["items"]?.arrayValue?.last?.objectValue?["text"]?.stringValue
                == "Repeated answer"
        })
    }

    func testActiveTurnHistoryUsesTheLiveInProgressProjection() async throws {
        let llm = ThreadHistoryBlockingLLM()
        let fixture = try await makeFixture(llm: llm)
        try await initialize(fixture)
        let threadID = try await startThread(fixture, requestID: 1)
        try await request(
            fixture,
            id: 2,
            method: "turn/start",
            params: [
                "threadId": threadID,
                "input": [["type": "text", "text": "Hold this turn open"]]
            ]
        )
        await llm.waitUntilStarted()
        let startRecords = try await fixture.output.records()
        let turnID = try XCTUnwrap(
            result(2, startRecords)?["turn"]?.objectValue?["id"]?.stringValue
        )

        try await request(
            fixture,
            id: 3,
            method: "thread/turns/list",
            params: ["threadId": threadID, "itemsView": "full"]
        )
        let records = try await fixture.output.records()
        let activeTurn = try XCTUnwrap(result(3, records)?["data"]?.arrayValue?.first)
        XCTAssertEqual(activeTurn.objectValue?["id"]?.stringValue, turnID)
        XCTAssertEqual(activeTurn.objectValue?["status"]?.stringValue, "inProgress")
        XCTAssertEqual(itemTypes(activeTurn), ["userMessage"])

        try await request(
            fixture,
            id: 4,
            method: "thread/items/list",
            params: ["threadId": threadID, "turnId": turnID]
        )
        let itemRecords = try await fixture.output.records()
        let activeItems = try XCTUnwrap(result(4, itemRecords)?["data"]?.arrayValue)
        XCTAssertEqual(activeItems.compactMap(entryTurnID), [turnID])
        XCTAssertEqual(activeItems.compactMap(entryItemType), ["userMessage"])

        try await request(
            fixture,
            id: 5,
            method: "turn/interrupt",
            params: ["threadId": threadID, "turnId": turnID]
        )
        await fixture.session.waitForActiveTurns()
    }
}

private func entryTurnID(_ value: CLIJSONValue) -> String? {
    value.objectValue?["turnId"]?.stringValue
}

private func entryItem(_ value: CLIJSONValue) -> [String: CLIJSONValue]? {
    value.objectValue?["item"]?.objectValue
}

private func entryItemID(_ value: CLIJSONValue) -> String? {
    entryItem(value)?["id"]?.stringValue
}

private func entryItemType(_ value: CLIJSONValue) -> String? {
    entryItem(value)?["type"]?.stringValue
}

private extension AppServerThreadHistoryTests {
    func makeFixture(
        home: URL? = nil,
        workspace: URL? = nil,
        llm: any LLMClient,
        ownsDirectories: Bool = true
    ) async throws -> ThreadHistoryFixture {
        let home = try home ?? temporaryDirectory(prefix: "thread-history-home")
        let workspace = try workspace ?? temporaryDirectory(prefix: "thread-history-workspace")
        if ownsDirectories {
            addTeardownBlock {
                try? FileManager.default.removeItem(at: home)
                try? FileManager.default.removeItem(at: workspace)
            }
        }
        let output = ThreadHistoryOutputCollector()
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
        return ThreadHistoryFixture(
            session: session,
            output: output,
            home: home,
            workspace: workspace
        )
    }

    func initialize(_ fixture: ThreadHistoryFixture) async throws {
        try await request(
            fixture,
            id: 100,
            method: "initialize",
            params: ["clientInfo": ["name": "ThreadHistoryTests", "version": "1"]]
        )
        try await notify(fixture, method: "initialized", params: [:])
    }

    func startThread(
        _ fixture: ThreadHistoryFixture,
        requestID: Int,
        sandbox: String = "read-only"
    ) async throws -> String {
        try await request(
            fixture,
            id: requestID,
            method: "thread/start",
            params: [
                "cwd": fixture.workspace.path,
                "model": "trustedrouter/fast",
                "sandbox": sandbox
            ]
        )
        let records = try await fixture.output.records()
        return try XCTUnwrap(
            result(requestID, records)?["thread"]?.objectValue?["id"]?.stringValue
        )
    }

    @discardableResult
    func runTurn(
        _ fixture: ThreadHistoryFixture,
        requestID: Int,
        threadID: String,
        text: String
    ) async throws -> String {
        try await request(
            fixture,
            id: requestID,
            method: "turn/start",
            params: [
                "threadId": threadID,
                "input": [["type": "text", "text": text]]
            ]
        )
        await fixture.session.waitForActiveTurns()
        let records = try await fixture.output.records()
        return try XCTUnwrap(
            result(requestID, records)?["turn"]?.objectValue?["id"]?.stringValue
        )
    }

    func request(
        _ fixture: ThreadHistoryFixture,
        id: Int,
        method: String,
        params: [String: Any]
    ) async throws {
        try await send(
            ["id": id, "method": method, "params": params],
            to: fixture.session
        )
    }

    func notify(
        _ fixture: ThreadHistoryFixture,
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
        _ records: [[String: CLIJSONValue]]
    ) -> [String: CLIJSONValue]? {
        records.first { $0["id"]?.numberValue == Double(id) }?["result"]?.objectValue
    }

    func error(
        _ id: Int,
        _ records: [[String: CLIJSONValue]]
    ) -> [String: CLIJSONValue]? {
        records.first { $0["id"]?.numberValue == Double(id) }?["error"]?.objectValue
    }

    func turnIDs(_ turns: [CLIJSONValue]) -> [String] {
        turns.compactMap { $0.objectValue?["id"]?.stringValue }
    }

    func itemTypes(_ turn: CLIJSONValue) -> [String] {
        turn.objectValue?["items"]?.arrayValue?.compactMap {
            $0.objectValue?["type"]?.stringValue
        } ?? []
    }

    func temporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private struct ThreadHistoryFixture {
    var session: AppServerSession
    var output: ThreadHistoryOutputCollector
    var home: URL
    var workspace: URL
}

private actor ThreadHistoryOutputCollector {
    private var lines: [String] = []

    func append(_ line: String) {
        lines.append(line)
    }

    func records() throws -> [[String: CLIJSONValue]] {
        try lines.map { line in
            guard let record = try CLIJSONCodec.decode(line).objectValue else {
                throw ThreadHistoryTestError.invalidRecord
            }
            return record
        }
    }
}

private enum ThreadHistoryTestError: Error {
    case invalidRecord
}

private struct ThreadHistoryEchoLLM: LLMClient {
    func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AgentAction {
        .say(userMessage)
    }
}

private actor ThreadHistoryScriptedLLM: LLMClient {
    private var actions: [AgentAction]

    init(actions: [AgentAction]) {
        self.actions = actions
    }

    func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AgentAction {
        guard !actions.isEmpty else { return .say("No scripted action remains.") }
        return actions.removeFirst()
    }
}

private actor ThreadHistoryBlockingLLM: LLMClient {
    private var started = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AgentAction {
        started = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
        try await Task.sleep(for: .seconds(30))
        return .say("Unexpected completion")
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}
