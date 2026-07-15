import Foundation
import QuillCodeAgent
@testable import QuillCodeCLI
import QuillCodeCore
import QuillCodeSafety
import XCTest

final class AppServerProcessTests: XCTestCase {
    func testSpawnParserAppliesCodexDefaultsNullOverridesAndPTYImplications() throws {
        let base: [String: CLIJSONValue] = [
            "command": .array([.string("/bin/echo")]),
            "cwd": .string(FileManager.default.currentDirectoryPath),
            "processHandle": .string("defaults")
        ]
        let defaults = try AppServerProcessSpawnRequest(
            params: .object(base),
            inheritedEnvironment: ["PATH": defaultPath]
        )
        XCTAssertEqual(defaults.outputBytesCap, 1_048_576)
        XCTAssertEqual(defaults.timeoutMilliseconds, 10_000)
        XCTAssertFalse(defaults.streamsStdin)
        XCTAssertFalse(defaults.streamsOutput)

        var overrides = base
        overrides["outputBytesCap"] = .null
        overrides["timeoutMs"] = .null
        overrides["tty"] = .bool(true)
        let unboundedPTY = try AppServerProcessSpawnRequest(
            params: .object(overrides),
            inheritedEnvironment: ["PATH": defaultPath]
        )
        XCTAssertNil(unboundedPTY.outputBytesCap)
        XCTAssertNil(unboundedPTY.timeoutMilliseconds)
        XCTAssertTrue(unboundedPTY.streamsStdin)
        XCTAssertTrue(unboundedPTY.streamsOutput)
    }

    func testProcessMethodsRequireExperimentalCapabilityAndStrictBoolean() async throws {
        let disabled = try await makeFixture(experimentalAPI: false)
        try await sendRequest(
            id: 2,
            method: "process/spawn",
            params: spawnParams(handle: "disabled", command: ["/bin/echo", "no"]),
            to: disabled.session
        )
        let disabledResponse = try await waitForResponse(id: 2, output: disabled.output)
        XCTAssertEqual(
            disabledResponse["error"]?.objectValue?["message"]?.stringValue,
            "process/spawn requires capabilities.experimentalApi: true"
        )

        let malformed = try await makeFixture(initialize: false)
        try await sendRequest(
            id: 1,
            method: "initialize",
            params: [
                "clientInfo": ["name": "ProcessTests", "version": "1"],
                "capabilities": ["experimentalApi": "yes"]
            ],
            to: malformed.session
        )
        let malformedResponse = try await waitForResponse(id: 1, output: malformed.output)
        XCTAssertEqual(errorCode(in: malformedResponse), -32_602)
    }

    func testBufferedProcessResponsePrecedesExitAndAppliesEnvironmentOverrides() async throws {
        let fixture = try await makeFixture(
            environment: ["PATH": defaultPath, "REMOVE_ME": "inherited"]
        )
        var params = spawnParams(
            handle: "buffered",
            command: [
                "/bin/sh", "-c",
                "printf '%s' \"$QC_VALUE\"; printf '%s' \"${REMOVE_ME-unset}\" >&2"
            ]
        )
        params["env"] = ["QC_VALUE": "stdout-value", "REMOVE_ME": NSNull()]
        try await sendRequest(id: 2, method: "process/spawn", params: params, to: fixture.session)

        let records = try await waitForNotification("process/exited", output: fixture.output)
        let responseIndex = try XCTUnwrap(records.firstIndex { $0["id"]?.numberValue == 2 })
        let exitIndex = try XCTUnwrap(records.firstIndex { $0["method"]?.stringValue == "process/exited" })
        XCTAssertLessThan(responseIndex, exitIndex)
        XCTAssertEqual(records[responseIndex]["result"]?.objectValue, [:])
        let exit = try XCTUnwrap(records[exitIndex]["params"]?.objectValue)
        XCTAssertEqual(exit["exitCode"]?.numberValue, 0)
        XCTAssertEqual(exit["stdout"]?.stringValue, "stdout-value")
        XCTAssertEqual(exit["stderr"]?.stringValue, "unset")
        XCTAssertEqual(exit["stdoutCapReached"]?.boolValue, false)
        XCTAssertEqual(exit["stderrCapReached"]?.boolValue, false)
    }

    func testStreamingOutputUsesBase64CapAndIsNotDuplicatedAtExit() async throws {
        let fixture = try await makeFixture()
        var params = spawnParams(
            handle: "streaming",
            command: ["/bin/sh", "-c", "printf abcdef; printf 123456 >&2"]
        )
        params["streamStdoutStderr"] = true
        params["outputBytesCap"] = 3
        try await sendRequest(id: 2, method: "process/spawn", params: params, to: fixture.session)

        let records = try await waitForNotification("process/exited", output: fixture.output)
        let deltas = records.filter { $0["method"]?.stringValue == "process/outputDelta" }
        XCTAssertEqual(deltas.count, 2)
        let decoded = Dictionary(uniqueKeysWithValues: try deltas.map { record in
            let params = try XCTUnwrap(record["params"]?.objectValue)
            let stream = try XCTUnwrap(params["stream"]?.stringValue)
            let encoded = try XCTUnwrap(params["deltaBase64"]?.stringValue)
            return (stream, String(decoding: try XCTUnwrap(Data(base64Encoded: encoded)), as: UTF8.self))
        })
        XCTAssertEqual(decoded["stdout"], "abc")
        XCTAssertEqual(decoded["stderr"], "123")
        XCTAssertTrue(deltas.allSatisfy {
            $0["params"]?.objectValue?["capReached"]?.boolValue == true
        })
        let exit = try XCTUnwrap(
            records.last { $0["method"]?.stringValue == "process/exited" }?["params"]?.objectValue
        )
        XCTAssertEqual(exit["stdout"]?.stringValue, "")
        XCTAssertEqual(exit["stderr"]?.stringValue, "")
        XCTAssertEqual(exit["stdoutCapReached"]?.boolValue, true)
        XCTAssertEqual(exit["stderrCapReached"]?.boolValue, true)
    }

    func testWriteStdinAndCloseDrainsBytesBeforeExit() async throws {
        let fixture = try await makeFixture()
        var params = spawnParams(handle: "stdin", command: ["/bin/cat"])
        params["streamStdin"] = true
        params["timeoutMs"] = NSNull()
        try await sendRequest(id: 2, method: "process/spawn", params: params, to: fixture.session)
        _ = try await waitForResponse(id: 2, output: fixture.output)

        try await sendRequest(
            id: 3,
            method: "process/writeStdin",
            params: [
                "processHandle": "stdin",
                "deltaBase64": Data("hello\n".utf8).base64EncodedString(),
                "closeStdin": true
            ],
            to: fixture.session
        )

        let records = try await waitForNotification("process/exited", output: fixture.output)
        XCTAssertNotNil(response(id: 3, in: records)["result"])
        let exit = try XCTUnwrap(
            records.last { $0["method"]?.stringValue == "process/exited" }?["params"]?.objectValue
        )
        XCTAssertEqual(exit["stdout"]?.stringValue, "hello\n")
        XCTAssertEqual(exit["exitCode"]?.numberValue, 0)
    }

    func testTimeoutUsesExitCode124() async throws {
        let fixture = try await makeFixture()
        var params = spawnParams(handle: "timeout", command: ["/bin/sleep", "5"])
        params["timeoutMs"] = 20
        try await sendRequest(id: 2, method: "process/spawn", params: params, to: fixture.session)

        let records = try await waitForNotification("process/exited", output: fixture.output)
        let exit = try XCTUnwrap(
            records.last { $0["method"]?.stringValue == "process/exited" }?["params"]?.objectValue
        )
        XCTAssertEqual(exit["exitCode"]?.numberValue, 124)
    }

    func testDuplicateHandleIsRejectedAndReusableAfterExit() async throws {
        let fixture = try await makeFixture()
        var first = spawnParams(handle: "reusable", command: ["/bin/sleep", "0.1"])
        first["timeoutMs"] = NSNull()
        try await sendRequest(id: 2, method: "process/spawn", params: first, to: fixture.session)
        try await sendRequest(
            id: 3,
            method: "process/spawn",
            params: spawnParams(handle: "reusable", command: ["/bin/echo", "duplicate"]),
            to: fixture.session
        )
        let duplicate = try await waitForResponse(id: 3, output: fixture.output)
        XCTAssertEqual(errorCode(in: duplicate), -32_600)
        _ = try await waitForNotification("process/exited", count: 1, output: fixture.output)

        try await sendRequest(
            id: 4,
            method: "process/spawn",
            params: spawnParams(handle: "reusable", command: ["/bin/echo", "reused"]),
            to: fixture.session
        )
        let records = try await waitForNotification("process/exited", count: 2, output: fixture.output)
        let exits = records.filter { $0["method"]?.stringValue == "process/exited" }
        XCTAssertEqual(exits.last?["params"]?.objectValue?["stdout"]?.stringValue, "reused\n")
    }

    func testPTYStreamsInitialResizeAndInteractiveInput() async throws {
        let fixture = try await makeFixture()
        var params = spawnParams(
            handle: "pty",
            command: [
                "/bin/sh", "-c",
                "stty size; IFS= read -r line; printf 'got:%s\\n' \"$line\"; stty size"
            ]
        )
        params["tty"] = true
        params["size"] = ["rows": 24, "cols": 80]
        params["timeoutMs"] = NSNull()
        try await sendRequest(id: 2, method: "process/spawn", params: params, to: fixture.session)
        _ = try await waitForNotification("process/outputDelta", output: fixture.output)

        try await sendRequest(
            id: 3,
            method: "process/resizePty",
            params: ["processHandle": "pty", "size": ["rows": 40, "cols": 100]],
            to: fixture.session
        )
        try await sendRequest(
            id: 4,
            method: "process/writeStdin",
            params: [
                "processHandle": "pty",
                "deltaBase64": Data("hello\n".utf8).base64EncodedString()
            ],
            to: fixture.session
        )

        let records = try await waitForNotification("process/exited", output: fixture.output)
        let output = try records
            .filter { $0["method"]?.stringValue == "process/outputDelta" }
            .map { record -> String in
                let encoded = try XCTUnwrap(record["params"]?.objectValue?["deltaBase64"]?.stringValue)
                return String(decoding: try XCTUnwrap(Data(base64Encoded: encoded)), as: UTF8.self)
            }
            .joined()
        XCTAssertTrue(output.contains("24 80"), output)
        XCTAssertTrue(output.contains("got:hello"), output)
        XCTAssertTrue(output.contains("40 100"), output)
        XCTAssertNotNil(response(id: 3, in: records)["result"])
        XCTAssertNotNil(response(id: 4, in: records)["result"])
    }

    func testKillTerminatesRunningProcess() async throws {
        let fixture = try await makeFixture()
        var params = spawnParams(handle: "kill", command: ["/bin/sleep", "30"])
        params["timeoutMs"] = NSNull()
        try await sendRequest(id: 2, method: "process/spawn", params: params, to: fixture.session)
        _ = try await waitForResponse(id: 2, output: fixture.output)
        try await sendRequest(
            id: 3,
            method: "process/kill",
            params: ["processHandle": "kill"],
            to: fixture.session
        )

        let records = try await waitForNotification("process/exited", output: fixture.output)
        XCTAssertNotNil(response(id: 3, in: records)["result"])
        XCTAssertNotEqual(
            records.last { $0["method"]?.stringValue == "process/exited" }?["params"]?
                .objectValue?["exitCode"]?.numberValue,
            0
        )
    }

    func testValidationRejectsMalformedProcessRequests() async throws {
        let fixture = try await makeFixture()
        let invalid: [(String, [String: Any])] = [
            ("process/spawn", spawnParams(handle: "", command: ["/bin/echo"])),
            ("process/spawn", spawnParams(handle: "empty", command: [])),
            ("process/spawn", spawnParams(handle: "relative", command: ["/bin/echo"], cwd: "relative")),
            ("process/spawn", spawnParams(handle: "size", command: ["/bin/echo"], extra: [
                "size": ["rows": 24, "cols": 80]
            ])),
            ("process/writeStdin", ["processHandle": "missing"]),
            ("process/writeStdin", ["processHandle": "missing", "deltaBase64": "***"]),
            ("process/resizePty", ["processHandle": "missing", "size": ["rows": 0, "cols": 80]])
        ]
        for (offset, item) in invalid.enumerated() {
            try await sendRequest(
                id: 10 + offset,
                method: item.0,
                params: item.1,
                to: fixture.session
            )
        }
        for id in 10..<(10 + invalid.count) {
            let record = try await waitForResponse(id: id, output: fixture.output)
            XCTAssertNotNil(record["error"], "request \(id) should fail")
        }
    }

    func testDisconnectTerminatesUnboundedProcessAndSuppressesExitNotification() async throws {
        let fixture = try await makeFixture()
        var params = spawnParams(handle: "disconnect", command: ["/bin/sleep", "30"])
        params["timeoutMs"] = NSNull()
        try await sendRequest(id: 2, method: "process/spawn", params: params, to: fixture.session)
        _ = try await waitForResponse(id: 2, output: fixture.output)

        let started = Date()
        await fixture.session.finishInput()
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
        let records = try await fixture.output.records()
        XCTAssertFalse(records.contains { $0["method"]?.stringValue == "process/exited" })
    }

    private var defaultPath: String { ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin" }

    private func makeFixture(
        initialize: Bool = true,
        experimentalAPI: Bool = true,
        environment: [String: String]? = nil
    ) async throws -> ProcessFixture {
        let home = try temporaryDirectory(prefix: "process-home")
        let workspace = try temporaryDirectory(prefix: "process-workspace")
        let output = ProcessOutputCollector()
        let session = try AppServerSession(
            request: CLIAppServerRequest(live: false, home: home),
            environment: environment ?? ProcessInfo.processInfo.environment,
            currentDirectory: workspace,
            runnerFactory: { configuration in
                AgentRunner(
                    llm: ProcessEchoLLM(),
                    safety: StaticSafetyReviewer(),
                    maxToolSteps: configuration.appConfig.maxToolSteps
                )
            },
            sink: { line in await output.append(line) }
        )
        let fixture = ProcessFixture(session: session, output: output, workspace: workspace)
        if initialize {
            try await sendRequest(
                id: 1,
                method: "initialize",
                params: [
                    "clientInfo": ["name": "ProcessTests", "version": "1"],
                    "capabilities": ["experimentalApi": experimentalAPI]
                ],
                to: session
            )
            try await sendNotification(method: "initialized", params: [:], to: session)
        }
        return fixture
    }

    private func spawnParams(
        handle: String,
        command: [String],
        cwd: String? = nil,
        extra: [String: Any] = [:]
    ) -> [String: Any] {
        var result: [String: Any] = [
            "processHandle": handle,
            "command": command,
            "cwd": cwd ?? FileManager.default.currentDirectoryPath
        ]
        result.merge(extra) { _, new in new }
        return result
    }

    private func waitForResponse(
        id: Int,
        output: ProcessOutputCollector
    ) async throws -> [String: CLIJSONValue] {
        for _ in 0..<400 {
            if let record = try await output.records().first(where: { $0["id"]?.numberValue == Double(id) }) {
                return record
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw ProcessTestError.timedOut
    }

    private func waitForNotification(
        _ method: String,
        count: Int = 1,
        output: ProcessOutputCollector
    ) async throws -> [[String: CLIJSONValue]] {
        for _ in 0..<800 {
            let records = try await output.records()
            if records.filter({ $0["method"]?.stringValue == method }).count >= count { return records }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw ProcessTestError.timedOut
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

    private func send(_ value: [String: Any], to session: AppServerSession) async throws {
        await session.receive(try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]))
    }

    private func response(
        id: Int,
        in records: [[String: CLIJSONValue]]
    ) -> [String: CLIJSONValue] {
        records.first { $0["id"]?.numberValue == Double(id) } ?? [:]
    }

    private func errorCode(in record: [String: CLIJSONValue]) -> Double? {
        record["error"]?.objectValue?["code"]?.numberValue
    }

    private func temporaryDirectory(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}

private struct ProcessFixture {
    var session: AppServerSession
    var output: ProcessOutputCollector
    var workspace: URL
}

private actor ProcessOutputCollector {
    private var lines: [String] = []

    func append(_ line: String) { lines.append(line) }

    func records() throws -> [[String: CLIJSONValue]] {
        try lines.map { line in
            guard let record = try CLIJSONCodec.decode(line).objectValue else {
                throw ProcessTestError.invalidRecord
            }
            return record
        }
    }
}

private struct ProcessEchoLLM: LLMClient {
    func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AgentAction {
        .say(userMessage)
    }
}

private enum ProcessTestError: Error {
    case invalidRecord
    case timedOut
}
