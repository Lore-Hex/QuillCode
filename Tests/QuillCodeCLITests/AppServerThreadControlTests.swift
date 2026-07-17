import Foundation
import QuillCodeAgent
@testable import QuillCodeCLI
import QuillCodeCore
import QuillCodeSafety
import XCTest

final class AppServerThreadControlTests: XCTestCase {
    func testFirstOperationOnPersistedThreadSubscribesWithoutUndoingExplicitUnsubscribe() async throws {
        let fixture = try await makeFixture(llm: ThreadControlEchoLLM())
        try await initialize(fixture)
        let thread = ChatThread(mode: .readOnly, model: "trustedrouter/fast")
        try await fixture.session.repository.create(AppServerThreadRecord(
            thread: thread,
            settings: AppServerThreadSettings(cwd: fixture.workspace)
        ))
        let threadID = AppServerThreadProjection.identifier(thread.id)
        await fixture.output.reset()

        try await runTurn(fixture, requestID: 1, threadID: threadID, text: "first operation")
        var records = try await fixture.output.records()
        XCTAssertTrue(notificationMethods(records).contains("turn/completed"))

        try await request(fixture, id: 2, method: "thread/unsubscribe", params: ["threadId": threadID])
        await fixture.output.reset()
        try await runTurn(fixture, requestID: 3, threadID: threadID, text: "remain unsubscribed")
        records = try await fixture.output.records()
        XCTAssertFalse(notificationMethods(records).contains(where: {
            $0.hasPrefix("turn/") || $0.hasPrefix("item/")
        }))
    }

    func testUnsubscribeKeepsThreadLoadedAndFiltersOnlyDetailedEventsUntilResume() async throws {
        let fixture = try await makeFixture(llm: ThreadControlEchoLLM())
        try await initialize(fixture)
        let threadID = try await startThread(fixture, requestID: 1)
        await fixture.output.reset()

        try await request(fixture, id: 2, method: "thread/unsubscribe", params: ["threadId": threadID])
        try await request(fixture, id: 3, method: "thread/loaded/list")
        try await request(fixture, id: 4, method: "thread/unsubscribe", params: ["threadId": threadID])
        try await request(
            fixture,
            id: 5,
            method: "thread/unsubscribe",
            params: ["threadId": "00000000-0000-0000-0000-000000000001"]
        )
        try await request(fixture, id: 6, method: "thread/unsubscribe", params: ["threadId": "bad"])
        try await request(fixture, id: 7, method: "thread/unsubscribe")

        var records = try await fixture.output.records()
        XCTAssertEqual(result(2, records)?["status"]?.stringValue, "unsubscribed")
        XCTAssertEqual(result(3, records)?["data"]?.arrayValue?.compactMap(\.stringValue), [threadID])
        XCTAssertEqual(result(4, records)?["status"]?.stringValue, "notSubscribed")
        XCTAssertEqual(result(5, records)?["status"]?.stringValue, "notLoaded")
        XCTAssertEqual(
            error(6, records)?["message"]?.stringValue,
            "invalid thread id: invalid length: expected length 32 for simple format, found 3"
        )
        XCTAssertEqual(
            error(7, records)?["message"]?.stringValue,
            "Invalid request: missing field `threadId`"
        )

        await fixture.output.reset()
        try await request(
            fixture,
            id: 8,
            method: "thread/name/set",
            params: ["threadId": threadID, "name": "Still visible"]
        )
        try await runTurn(fixture, requestID: 9, threadID: threadID, text: "suppressed details")
        records = try await fixture.output.records()
        let methods = notificationMethods(records)
        XCTAssertTrue(methods.contains("thread/name/updated"))
        XCTAssertTrue(methods.contains("thread/status/changed"))
        XCTAssertFalse(methods.contains(where: { $0.hasPrefix("turn/") || $0.hasPrefix("item/") }))

        try await request(fixture, id: 10, method: "thread/resume", params: ["threadId": threadID])
        await fixture.output.reset()
        try await runTurn(fixture, requestID: 11, threadID: threadID, text: "details restored")
        records = try await fixture.output.records()
        let resumedMethods = notificationMethods(records)
        XCTAssertTrue(resumedMethods.contains("turn/started"))
        XCTAssertTrue(resumedMethods.contains("item/started"))
        XCTAssertTrue(resumedMethods.contains("turn/completed"))
    }

    func testElicitationCountersAreConnectionScopedAndMatchCodexErrors() async throws {
        let fixture = try await makeFixture(llm: ThreadControlEchoLLM())
        try await initialize(fixture)
        let threadID = try await startThread(fixture, requestID: 1)
        await fixture.output.reset()

        try await request(
            fixture,
            id: 2,
            method: "thread/increment_elicitation",
            params: ["threadId": threadID]
        )
        try await request(
            fixture,
            id: 3,
            method: "thread/increment_elicitation",
            params: ["threadId": threadID]
        )
        try await request(
            fixture,
            id: 4,
            method: "thread/decrement_elicitation",
            params: ["threadId": threadID]
        )
        try await request(
            fixture,
            id: 5,
            method: "thread/decrement_elicitation",
            params: ["threadId": threadID]
        )
        try await request(
            fixture,
            id: 6,
            method: "thread/decrement_elicitation",
            params: ["threadId": threadID]
        )
        try await request(
            fixture,
            id: 7,
            method: "thread/increment_elicitation",
            params: ["threadId": "00000000-0000-0000-0000-000000000001"]
        )

        let records = try await fixture.output.records()
        assertElicitation(result(2, records), count: 1, paused: true)
        assertElicitation(result(3, records), count: 2, paused: true)
        assertElicitation(result(4, records), count: 1, paused: true)
        assertElicitation(result(5, records), count: 0, paused: false)
        XCTAssertEqual(
            error(6, records)?["message"]?.stringValue,
            "out-of-band elicitation count is already zero"
        )
        XCTAssertEqual(
            error(7, records)?["message"]?.stringValue,
            "thread not found: 00000000-0000-0000-0000-000000000001"
        )

        let fresh = try await makeFixture(
            home: fixture.home,
            workspace: fixture.workspace,
            llm: ThreadControlEchoLLM(),
            ownsDirectories: false
        )
        try await initialize(fresh)
        try await request(fresh, id: 8, method: "thread/resume", params: ["threadId": threadID])
        try await request(
            fresh,
            id: 9,
            method: "thread/decrement_elicitation",
            params: ["threadId": threadID]
        )
        let freshRecords = try await fresh.output.records()
        XCTAssertEqual(
            error(9, freshRecords)?["message"]?.stringValue,
            "out-of-band elicitation count is already zero"
        )
    }

    func testGitMetadataPatchPersistsOmittedAndClearedFields() async throws {
        let fixture = try await makeFixture(llm: ThreadControlEchoLLM())
        try await initialize(fixture)
        let threadID = try await startThread(fixture, requestID: 1)
        await fixture.output.reset()

        try await request(
            fixture,
            id: 2,
            method: "thread/metadata/update",
            params: [
                "threadId": threadID,
                "gitInfo": [
                    "sha": "abc123",
                    "branch": "feature/probe",
                    "originUrl": "https://example.invalid/repo.git"
                ]
            ]
        )
        try await request(
            fixture,
            id: 3,
            method: "thread/metadata/update",
            params: ["threadId": threadID, "gitInfo": ["branch": NSNull()]]
        )
        try await request(fixture, id: 4, method: "thread/read", params: ["threadId": threadID])
        try await request(
            fixture,
            id: 5,
            method: "thread/metadata/update",
            params: ["threadId": threadID, "gitInfo": ["branch": ""]]
        )
        try await request(
            fixture,
            id: 6,
            method: "thread/metadata/update",
            params: ["threadId": threadID, "gitInfo": NSNull()]
        )
        try await request(
            fixture,
            id: 7,
            method: "thread/metadata/update",
            params: [
                "threadId": "00000000-0000-0000-0000-000000000001",
                "gitInfo": ["branch": "missing"]
            ]
        )

        var records = try await fixture.output.records()
        var gitInfo = try XCTUnwrap(
            result(3, records)?["thread"]?.objectValue?["gitInfo"]?.objectValue
        )
        XCTAssertEqual(gitInfo["sha"]?.stringValue, "abc123")
        XCTAssertEqual(gitInfo["originUrl"]?.stringValue, "https://example.invalid/repo.git")
        XCTAssertEqual(gitInfo["branch"], .null)
        gitInfo = try XCTUnwrap(result(4, records)?["thread"]?.objectValue?["gitInfo"]?.objectValue)
        XCTAssertEqual(gitInfo["branch"], .null)
        XCTAssertEqual(error(5, records)?["message"]?.stringValue, "gitInfo.branch must not be empty")
        XCTAssertEqual(
            error(6, records)?["message"]?.stringValue,
            "gitInfo must include at least one field"
        )
        XCTAssertEqual(
            error(7, records)?["message"]?.stringValue,
            "thread not found: 00000000-0000-0000-0000-000000000001"
        )

        let fresh = try await makeFixture(
            home: fixture.home,
            workspace: fixture.workspace,
            llm: ThreadControlEchoLLM(),
            ownsDirectories: false
        )
        try await initialize(fresh)
        try await request(fresh, id: 8, method: "thread/read", params: ["threadId": threadID])
        records = try await fresh.output.records()
        gitInfo = try XCTUnwrap(result(8, records)?["thread"]?.objectValue?["gitInfo"]?.objectValue)
        XCTAssertEqual(gitInfo["sha"]?.stringValue, "abc123")
        XCTAssertEqual(gitInfo["branch"], .null)
    }

    func testSettingsUpdatePersistsFullProjectionAndNotifiesAfterResponseOnlyOnChange() async throws {
        let otherWorkspace = try temporaryDirectory(prefix: "thread-controls-other-workspace")
        addTeardownBlock { try? FileManager.default.removeItem(at: otherWorkspace) }
        let fixture = try await makeFixture(llm: ThreadControlEchoLLM())
        try await initialize(fixture)
        let threadID = try await startThread(fixture, requestID: 1)
        await fixture.output.reset()

        let settingsPatch: [String: Any] = [
            "threadId": threadID,
            "model": "trustedrouter/socrates",
            "effort": "low",
            "personality": "friendly",
            "serviceTier": "priority",
            "summary": "detailed",
            "cwd": otherWorkspace.path,
            "approvalPolicy": "never",
            "approvalsReviewer": "guardian_subagent",
            "sandboxPolicy": ["type": "workspaceWrite", "networkAccess": true],
            "collaborationMode": [
                "mode": "plan",
                "settings": [
                    "model": "trustedrouter/socrates",
                    "reasoning_effort": "medium",
                    "developer_instructions": "Plan before editing."
                ]
            ]
        ]
        try await request(
            fixture,
            id: 2,
            method: "thread/settings/update",
            params: settingsPatch
        )

        var records = try await fixture.output.records()
        XCTAssertEqual(result(2, records), [:])
        let responseIndex = try XCTUnwrap(records.firstIndex { $0["id"]?.numberValue == 2 })
        let notificationIndex = try XCTUnwrap(records.firstIndex {
            $0["method"]?.stringValue == "thread/settings/updated"
        })
        XCTAssertGreaterThan(notificationIndex, responseIndex)
        let settings = try XCTUnwrap(records[notificationIndex]["params"]?.objectValue?["threadSettings"]?.objectValue)
        XCTAssertEqual(settings["model"]?.stringValue, "trustedrouter/socrates")
        XCTAssertEqual(settings["effort"]?.stringValue, "medium")
        XCTAssertEqual(settings["cwd"]?.stringValue, otherWorkspace.standardizedFileURL.path)
        XCTAssertEqual(settings["approvalPolicy"]?.stringValue, "never")
        XCTAssertEqual(settings["approvalsReviewer"]?.stringValue, "auto_review")
        XCTAssertEqual(settings["personality"]?.stringValue, "friendly")
        XCTAssertEqual(settings["serviceTier"]?.stringValue, "priority")
        XCTAssertEqual(settings["summary"]?.stringValue, "detailed")
        XCTAssertEqual(settings["activePermissionProfile"], .null)
        let sandbox = try XCTUnwrap(settings["sandboxPolicy"]?.objectValue)
        XCTAssertEqual(sandbox["type"]?.stringValue, "workspaceWrite")
        XCTAssertEqual(sandbox["networkAccess"]?.boolValue, true)
        XCTAssertEqual(sandbox["writableRoots"]?.arrayValue, [])
        let collaboration = try XCTUnwrap(settings["collaborationMode"]?.objectValue)
        XCTAssertEqual(collaboration["mode"]?.stringValue, "plan")
        XCTAssertEqual(
            collaboration["settings"]?.objectValue?["reasoning_effort"]?.stringValue,
            "medium"
        )

        await fixture.output.reset()
        try await request(
            fixture,
            id: 3,
            method: "thread/settings/update",
            params: [
                "threadId": threadID,
                "model": NSNull(),
                "effort": NSNull(),
                "personality": NSNull(),
                "summary": NSNull(),
                "cwd": NSNull(),
                "approvalPolicy": NSNull(),
                "approvalsReviewer": NSNull(),
                "sandboxPolicy": NSNull(),
                "collaborationMode": NSNull(),
                "permissions": NSNull()
            ]
        )
        records = try await fixture.output.records()
        XCTAssertEqual(result(3, records), [:])
        XCTAssertFalse(notificationMethods(records).contains("thread/settings/updated"))

        await fixture.output.reset()
        try await request(
            fixture,
            id: 4,
            method: "thread/settings/update",
            params: ["threadId": threadID, "serviceTier": NSNull()]
        )
        records = try await fixture.output.records()
        let clearedSettings = try XCTUnwrap(records.first {
            $0["method"]?.stringValue == "thread/settings/updated"
        }?["params"]?.objectValue?["threadSettings"]?.objectValue)
        XCTAssertEqual(clearedSettings["serviceTier"]?.stringValue, "default")

        let fresh = try await makeFixture(
            home: fixture.home,
            workspace: fixture.workspace,
            llm: ThreadControlEchoLLM(),
            ownsDirectories: false
        )
        try await initialize(fresh)
        try await request(fresh, id: 5, method: "thread/resume", params: ["threadId": threadID])
        records = try await fresh.output.records()
        XCTAssertEqual(result(5, records)?["model"]?.stringValue, "trustedrouter/socrates")
        XCTAssertEqual(result(5, records)?["reasoningEffort"]?.stringValue, "medium")
        XCTAssertEqual(result(5, records)?["serviceTier"]?.stringValue, "default")
        XCTAssertEqual(result(5, records)?["cwd"]?.stringValue, otherWorkspace.standardizedFileURL.path)

        await fresh.output.reset()
        try await request(
            fresh,
            id: 6,
            method: "thread/settings/update",
            params: ["threadId": threadID, "effort": ""]
        )
        try await request(
            fresh,
            id: 7,
            method: "thread/settings/update",
            params: ["threadId": threadID, "personality": "bogus"]
        )
        try await request(
            fresh,
            id: 8,
            method: "thread/settings/update",
            params: [
                "threadId": threadID,
                "sandboxPolicy": ["type": "readOnly"],
                "permissions": ":read-only"
            ]
        )
        try await request(
            fresh,
            id: 9,
            method: "thread/settings/update",
            params: ["threadId": threadID, "permissions": ":does-not-exist"]
        )
        records = try await fresh.output.records()
        XCTAssertEqual(
            error(6, records)?["message"]?.stringValue,
            "Invalid request: reasoning_effort must not be empty"
        )
        XCTAssertEqual(
            error(7, records)?["message"]?.stringValue,
            "Invalid request: unknown variant `bogus`, expected one of `none`, `friendly`, `pragmatic`"
        )
        XCTAssertEqual(
            error(8, records)?["message"]?.stringValue,
            "`permissions` cannot be combined with `sandboxPolicy`"
        )
        XCTAssertEqual(
            error(9, records)?["message"]?.stringValue,
            "failed to load configuration: default_permissions refers to unknown built-in profile `:does-not-exist`"
        )
    }

    func testThreadSettingsReconstructionPreservesMetadataAndDefaultsGranularFields() async throws {
        let fixture = try await makeFixture(llm: ThreadControlEchoLLM())
        let base = AppServerThreadSettings(
            cwd: fixture.workspace,
            runtimeAppConfig: AppConfig(defaultModel: "trustedrouter/aristotle"),
            compactPrompt: "Keep the durable context.",
            name: "Preserved name",
            gitInfo: .init(sha: "abc", branch: "main", originURL: nil),
            reasoningEffort: "high",
            reasoningSummary: "concise",
            serviceTier: "priority",
            collaborationMode: .init(
                mode: .plan,
                settings: .init(model: "trustedrouter/aristotle", reasoningEffort: "high", developerInstructions: nil)
            ),
            memoryMode: .disabled,
            permissionProfileID: ":workspace",
            permissionProfileIsExplicit: true
        )
        let updated = try await fixture.session.threadSettings(
            from: AppServerParams(.object(["ephemeral": .bool(true)])),
            base: base,
            requirements: nil
        )
        XCTAssertEqual(updated.runtimeAppConfig, base.runtimeAppConfig)
        XCTAssertEqual(updated.compactPrompt, base.compactPrompt)
        XCTAssertEqual(updated.name, base.name)
        XCTAssertEqual(updated.gitInfo, base.gitInfo)
        XCTAssertEqual(updated.collaborationMode, base.collaborationMode)
        XCTAssertEqual(updated.memoryMode, .disabled)
        XCTAssertEqual(updated.permissionProfileID, ":workspace")

        let normalized = try await fixture.session.approvalPolicy(.object([
            "granular": .object([
                "sandbox_approval": .bool(true),
                "rules": .bool(false),
                "mcp_elicitations": .bool(true)
            ])
        ]))
        let granular = try XCTUnwrap(normalized?.objectValue?["granular"]?.objectValue)
        XCTAssertEqual(granular["skill_approval"]?.boolValue, false)
        XCTAssertEqual(granular["request_permissions"]?.boolValue, false)
    }

    func testDisabledMemoryIsHiddenFromModelWithoutDeletingStoredNotes() async throws {
        let observer = ThreadControlMemoryObserver()
        let fixture = try await makeFixture(llm: observer)
        try await initialize(fixture)
        let threadID = try await startThread(fixture, requestID: 1)
        let uuid = try XCTUnwrap(UUID(uuidString: threadID))
        var record = try await fixture.session.repository.load(uuid)
        record.thread.memories = [MemoryNote(
            id: "memory-1",
            scope: .project,
            title: "Private durable note",
            content: "Do not expose while memory mode is disabled.",
            relativePath: "MEMORY.md",
            byteCount: 41
        )]
        try await fixture.session.repository.save(record)

        try await request(
            fixture,
            id: 2,
            method: "thread/memoryMode/set",
            params: ["threadId": threadID, "mode": "disabled"]
        )
        try await runTurn(fixture, requestID: 3, threadID: threadID, text: "Inspect context")
        let firstObservedCounts = await observer.observedMemoryCounts()
        XCTAssertEqual(firstObservedCounts, [0])
        record = try await fixture.session.repository.load(uuid)
        XCTAssertEqual(record.settings.effectiveMemoryMode, .disabled)
        XCTAssertEqual(record.thread.memories.map(\.id), ["memory-1"])

        let fresh = try await makeFixture(
            home: fixture.home,
            workspace: fixture.workspace,
            llm: observer,
            ownsDirectories: false
        )
        try await initialize(fresh)
        try await request(fresh, id: 4, method: "thread/resume", params: ["threadId": threadID])
        try await runTurn(fresh, requestID: 5, threadID: threadID, text: "Inspect after reconnect")
        let reconnectedObservedCounts = await observer.observedMemoryCounts()
        XCTAssertEqual(reconnectedObservedCounts, [0, 0])
        record = try await fresh.session.repository.load(uuid)
        XCTAssertEqual(record.thread.memories.map(\.id), ["memory-1"])

        await fresh.output.reset()
        try await request(
            fresh,
            id: 6,
            method: "thread/memoryMode/set",
            params: ["threadId": threadID, "mode": "bogus"]
        )
        try await request(
            fresh,
            id: 7,
            method: "thread/memoryMode/set",
            params: [
                "threadId": "00000000-0000-0000-0000-000000000001",
                "mode": "disabled"
            ]
        )
        let records = try await fresh.output.records()
        XCTAssertEqual(
            error(6, records)?["message"]?.stringValue,
            "Invalid request: unknown variant `bogus`, expected `enabled` or `disabled`"
        )
        XCTAssertEqual(
            error(7, records)?["message"]?.stringValue,
            "thread not found: 00000000-0000-0000-0000-000000000001"
        )
    }

    func testRuntimeMemoryFeatureChangesModelContextWithoutDeletingNotes() async throws {
        let observer = ThreadControlMemoryObserver()
        let fixture = try await makeFixture(llm: observer)
        try await initialize(fixture)
        let threadID = try await startThread(fixture, requestID: 1)
        let uuid = try XCTUnwrap(UUID(uuidString: threadID))
        var record = try await fixture.session.repository.load(uuid)
        record.thread.memories = [MemoryNote(
            id: "runtime-memory",
            scope: .project,
            title: "Durable note",
            content: "Keep this note while runtime memory is disabled.",
            relativePath: "MEMORY.md",
            byteCount: 48
        )]
        try await fixture.session.repository.save(record)

        try await request(
            fixture,
            id: 2,
            method: "experimentalFeature/enablement/set",
            params: ["enablement": ["memories": false]]
        )
        try await runTurn(fixture, requestID: 3, threadID: threadID, text: "Inspect disabled context")
        try await request(
            fixture,
            id: 4,
            method: "experimentalFeature/enablement/set",
            params: ["enablement": ["memories": true]]
        )
        try await runTurn(fixture, requestID: 5, threadID: threadID, text: "Inspect enabled context")

        let observedCounts = await observer.observedMemoryCounts()
        XCTAssertEqual(observedCounts, [0, 1])
        record = try await fixture.session.repository.load(uuid)
        XCTAssertEqual(record.thread.memories.map(\.id), ["runtime-memory"])
    }
}

private extension AppServerThreadControlTests {
    func makeFixture(
        home: URL? = nil,
        workspace: URL? = nil,
        llm: any LLMClient,
        ownsDirectories: Bool = true
    ) async throws -> ThreadControlFixture {
        let home = try home ?? temporaryDirectory(prefix: "thread-controls-home")
        let workspace = try workspace ?? temporaryDirectory(prefix: "thread-controls-workspace")
        if ownsDirectories {
            addTeardownBlock {
                try? FileManager.default.removeItem(at: home)
                try? FileManager.default.removeItem(at: workspace)
            }
        }
        let output = ThreadControlOutputCollector()
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
        return ThreadControlFixture(
            session: session,
            output: output,
            home: home,
            workspace: workspace
        )
    }

    func initialize(_ fixture: ThreadControlFixture) async throws {
        try await request(
            fixture,
            id: 100,
            method: "initialize",
            params: ["clientInfo": ["name": "ThreadControlTests", "version": "1"]]
        )
        try await send(["method": "initialized", "params": [:]], to: fixture.session)
    }

    func startThread(_ fixture: ThreadControlFixture, requestID: Int) async throws -> String {
        try await request(
            fixture,
            id: requestID,
            method: "thread/start",
            params: [
                "cwd": fixture.workspace.path,
                "model": "trustedrouter/fast",
                "sandbox": "read-only"
            ]
        )
        let records = try await fixture.output.records()
        return try XCTUnwrap(
            result(requestID, records)?["thread"]?
                .objectValue?["id"]?.stringValue
        )
    }

    func runTurn(
        _ fixture: ThreadControlFixture,
        requestID: Int,
        threadID: String,
        text: String
    ) async throws {
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
    }

    func request(
        _ fixture: ThreadControlFixture,
        id: Int,
        method: String,
        params: [String: Any] = [:]
    ) async throws {
        try await send(["id": id, "method": method, "params": params], to: fixture.session)
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

    func notificationMethods(_ records: [[String: CLIJSONValue]]) -> [String] {
        records.compactMap { $0["method"]?.stringValue }
    }

    func assertElicitation(
        _ result: [String: CLIJSONValue]?,
        count: Double,
        paused: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(result?["count"]?.numberValue, count, file: file, line: line)
        XCTAssertEqual(result?["paused"]?.boolValue, paused, file: file, line: line)
    }

    func temporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private struct ThreadControlFixture {
    var session: AppServerSession
    var output: ThreadControlOutputCollector
    var home: URL
    var workspace: URL
}

private actor ThreadControlOutputCollector {
    private var lines: [String] = []

    func append(_ line: String) {
        lines.append(line)
    }

    func reset() {
        lines.removeAll(keepingCapacity: true)
    }

    func records() throws -> [[String: CLIJSONValue]] {
        try lines.map { line in
            guard let record = try CLIJSONCodec.decode(line).objectValue else {
                throw ThreadControlTestError.invalidRecord
            }
            return record
        }
    }
}

private enum ThreadControlTestError: Error {
    case invalidRecord
}

private struct ThreadControlEchoLLM: LLMClient {
    func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AgentAction {
        .say(userMessage)
    }
}

private actor ThreadControlMemoryObserver: LLMClient {
    private var counts: [Int] = []

    func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AgentAction {
        counts.append(thread.memories.count)
        return .say("Observed memory context.")
    }

    func observedMemoryCounts() -> [Int] {
        counts
    }
}
