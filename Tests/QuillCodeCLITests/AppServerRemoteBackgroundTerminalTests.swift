@testable import QuillCodeCLI
import XCTest

final class AppServerRemoteBackgroundTerminalTests: AppServerEnvironmentSessionTestCase {
    func testRemoteUserShellStreamsListsTerminatesAndCleansThroughUnifiedRegistry() async throws {
        let client = AppServerFakeExecServerClient(
            info: remoteInfo,
            processDelay: .seconds(30),
            processResults: [
                .init(
                    stdout: "first-live\n",
                    stderr: "",
                    exitCode: 0,
                    failure: nil,
                    sandboxDenied: false
                ),
                .init(
                    stdout: "second-live\n",
                    stderr: "",
                    exitCode: 0,
                    failure: nil,
                    sandboxDenied: false
                )
            ]
        )
        let factory = AppServerFakeExecServerFactory(clients: [client])
        let registry = makeRegistry(factory: factory)
        _ = try await registry.add(registration(id: "remote"))
        let fixture = try makeSession(llm: EnvironmentEchoLLM(), registry: registry)
        try await initialize(fixture.session)

        try await sendRequest(
            id: 2,
            method: "thread/start",
            params: threadParameters(
                environments: [["environmentId": "remote", "cwd": "/workspace"]],
                workspace: fixture.workspace
            ),
            to: fixture.session
        )
        var records = try await fixture.output.records()
        let threadID = try XCTUnwrap(
            result(for: 2, in: records)?["thread"]?.objectValue?["id"]?.stringValue
        )

        try await sendRequest(
            id: 3,
            method: "thread/shellCommand",
            params: ["threadId": threadID, "command": "printf first-live"],
            to: fixture.session
        )
        try await sendRequest(
            id: 4,
            method: "thread/shellCommand",
            params: ["threadId": threadID, "command": "printf second-live"],
            to: fixture.session
        )
        try await waitUntil {
            let records = try? await fixture.output.records()
            return records?.filter {
                $0["method"]?.stringValue == "item/commandExecution/outputDelta"
            }.count == 2
        }
        records = try await fixture.output.records()
        XCTAssertFalse(
            records.contains { $0["method"]?.stringValue == "item/completed" },
            "Remote output must stream while the process is still active."
        )

        try await sendRequest(
            id: 5,
            method: "thread/backgroundTerminals/list",
            params: ["threadId": threadID],
            to: fixture.session
        )
        records = try await fixture.output.records()
        let terminals = try XCTUnwrap(result(for: 5, in: records)?["data"]?.arrayValue)
        XCTAssertEqual(terminals.count, 2)
        let terminalObjects = try terminals.map { try XCTUnwrap($0.objectValue) }
        XCTAssertTrue(terminalObjects.allSatisfy { $0["osPid"] == .null })
        XCTAssertEqual(
            Set(terminalObjects.compactMap { $0["command"]?.stringValue }),
            ["printf first-live", "printf second-live"]
        )
        XCTAssertTrue(terminalObjects.allSatisfy {
            $0["cwd"]?.stringValue == "/workspace" && $0["itemId"]?.stringValue != nil
        })
        let processIDs = try terminalObjects.map {
            try XCTUnwrap($0["processId"]?.stringValue)
        }
        let snapshot = await client.snapshot()
        XCTAssertEqual(Set(snapshot.processRequests.compactMap(\.processID)), Set(processIDs))

        try await sendRequest(
            id: 6,
            method: "thread/backgroundTerminals/terminate",
            params: ["threadId": threadID, "processId": processIDs[0]],
            to: fixture.session
        )
        records = try await fixture.output.records()
        XCTAssertEqual(result(for: 6, in: records)?["terminated"]?.boolValue, true)
        try await waitUntil {
            await client.snapshot().terminatedProcessIDs.contains(processIDs[0])
        }

        try await sendRequest(
            id: 7,
            method: "thread/backgroundTerminals/list",
            params: ["threadId": threadID],
            to: fixture.session
        )
        records = try await fixture.output.records()
        let remaining = try XCTUnwrap(result(for: 7, in: records)?["data"]?.arrayValue)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.objectValue?["processId"]?.stringValue, processIDs[1])

        try await sendRequest(
            id: 8,
            method: "thread/backgroundTerminals/clean",
            params: ["threadId": threadID],
            to: fixture.session
        )
        try await waitUntil {
            Set(await client.snapshot().terminatedProcessIDs) == Set(processIDs)
        }
        try await sendRequest(
            id: 9,
            method: "thread/backgroundTerminals/list",
            params: ["threadId": threadID],
            to: fixture.session
        )
        records = try await fixture.output.records()
        XCTAssertEqual(result(for: 9, in: records)?["data"]?.arrayValue, [])
        await fixture.session.waitForActiveTurns()
        await registry.closeAll()
    }
}
