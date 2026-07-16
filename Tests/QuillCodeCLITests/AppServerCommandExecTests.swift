import Foundation
import QuillCodeAgent
@testable import QuillCodeCLI
import QuillCodeCore
import QuillCodeSafety
import XCTest

final class AppServerCommandExecTests: XCTestCase {
    func testBufferedExecutionDefersResponseAndAppliesCWDAndEnvironment() async throws {
        let fixture = try await makeFixture(environment: [
            "PATH": defaultPath,
            "REMOVE_ME": "inherited"
        ])
        let nested = fixture.workspace.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("nested".utf8).write(to: nested.appendingPathComponent("cwd-marker"))

        try await sendRequest(
            id: 2,
            method: "command/exec",
            params: execParams(
                command: [
                    "/bin/sh", "-c",
                    "sleep 0.15; printf '%s:%s' \"$(cat cwd-marker)\" \"$QC_VALUE\"; "
                        + "printf '%s' \"${REMOVE_ME-unset}\" >&2"
                ],
                extra: [
                    "cwd": "nested",
                    "env": ["QC_VALUE": "set", "REMOVE_ME": NSNull()]
                ]
            ),
            to: fixture.session
        )

        let earlyRecords = try await fixture.output.records()
        XCTAssertNil(response(id: 2, in: earlyRecords), "command/exec must defer its response")

        let records = try await waitForResponse(id: 2, output: fixture.output)
        let result = try XCTUnwrap(response(id: 2, in: records)?["result"]?.objectValue)
        XCTAssertEqual(result["exitCode"]?.numberValue, 0)
        XCTAssertEqual(result["stdout"]?.stringValue, "nested:set")
        XCTAssertEqual(result["stderr"]?.stringValue, "unset")
        XCTAssertFalse(records.contains { $0["method"]?.stringValue == "command/exec/outputDelta" })
    }

    func testStreamingOutputPrecedesFinalResponseAndIsNotDuplicated() async throws {
        let fixture = try await makeFixture()
        try await sendRequest(
            id: 2,
            method: "command/exec",
            params: execParams(
                command: ["/bin/sh", "-c", "printf abcdef; printf 123456 >&2"],
                processID: "streamed",
                extra: ["streamStdoutStderr": true, "outputBytesCap": 3]
            ),
            to: fixture.session
        )

        let records = try await waitForResponse(id: 2, output: fixture.output)
        let responseIndex = try XCTUnwrap(records.firstIndex { $0["id"]?.numberValue == 2 })
        let deltas = records.enumerated().filter {
            $0.element["method"]?.stringValue == "command/exec/outputDelta"
        }
        XCTAssertEqual(deltas.count, 2)
        XCTAssertTrue(deltas.allSatisfy { $0.offset < responseIndex })
        XCTAssertTrue(deltas.allSatisfy {
            $0.element["params"]?.objectValue?["processId"]?.stringValue == "streamed"
        })
        XCTAssertTrue(deltas.allSatisfy {
            $0.element["params"]?.objectValue?["capReached"]?.boolValue == true
        })
        let decoded = Dictionary(uniqueKeysWithValues: try deltas.map { item in
            let params = try XCTUnwrap(item.element["params"]?.objectValue)
            let stream = try XCTUnwrap(params["stream"]?.stringValue)
            let encoded = try XCTUnwrap(params["deltaBase64"]?.stringValue)
            let data = try XCTUnwrap(Data(base64Encoded: encoded))
            return (stream, String(decoding: data, as: UTF8.self))
        })
        XCTAssertEqual(decoded["stdout"], "abc")
        XCTAssertEqual(decoded["stderr"], "123")

        let result = try XCTUnwrap(response(id: 2, in: records)?["result"]?.objectValue)
        XCTAssertEqual(result["stdout"]?.stringValue, "")
        XCTAssertEqual(result["stderr"]?.stringValue, "")
    }

    func testStreamingStdinClosesAndDrainsBeforeFinalResponse() async throws {
        let fixture = try await makeFixture()
        try await sendRequest(
            id: 2,
            method: "command/exec",
            params: execParams(
                command: ["/bin/cat"],
                processID: "stdin",
                extra: ["streamStdin": true, "disableTimeout": true]
            ),
            to: fixture.session
        )
        try await sendRequest(
            id: 3,
            method: "command/exec/write",
            params: [
                "processId": "stdin",
                "deltaBase64": Data("hello\n".utf8).base64EncodedString(),
                "closeStdin": true
            ],
            to: fixture.session
        )

        let records = try await waitForResponse(id: 2, output: fixture.output)
        let writeIndex = try XCTUnwrap(records.firstIndex { $0["id"]?.numberValue == 3 })
        let finalIndex = try XCTUnwrap(records.firstIndex { $0["id"]?.numberValue == 2 })
        XCTAssertLessThan(writeIndex, finalIndex)
        XCTAssertEqual(response(id: 3, in: records)?["result"]?.objectValue, [:])
        let result = try XCTUnwrap(response(id: 2, in: records)?["result"]?.objectValue)
        XCTAssertEqual(result["exitCode"]?.numberValue, 0)
        XCTAssertEqual(result["stdout"]?.stringValue, "hello\n")
    }

    func testPTYSupportsInitialSizeResizeAndInteractiveInput() async throws {
        let fixture = try await makeFixture()
        try await sendRequest(
            id: 2,
            method: "command/exec",
            params: execParams(
                command: [
                    "/bin/sh", "-c",
                    "stty size; IFS= read -r line; printf 'got:%s\\n' \"$line\"; stty size"
                ],
                processID: "pty",
                extra: [
                    "tty": true,
                    "size": ["rows": 24, "cols": 80],
                    "disableTimeout": true
                ]
            ),
            to: fixture.session
        )
        _ = try await waitForNotification("command/exec/outputDelta", output: fixture.output)

        try await sendRequest(
            id: 3,
            method: "command/exec/resize",
            params: ["processId": "pty", "size": ["rows": 40, "cols": 100]],
            to: fixture.session
        )
        try await sendRequest(
            id: 4,
            method: "command/exec/write",
            params: [
                "processId": "pty",
                "deltaBase64": Data("hello\n".utf8).base64EncodedString()
            ],
            to: fixture.session
        )

        let records = try await waitForResponse(id: 2, output: fixture.output)
        let output = try streamedText(in: records)
        XCTAssertTrue(output.contains("24 80"), output)
        XCTAssertTrue(output.contains("got:hello"), output)
        XCTAssertTrue(output.contains("40 100"), output)
        XCTAssertEqual(response(id: 3, in: records)?["result"]?.objectValue, [:])
        XCTAssertEqual(response(id: 4, in: records)?["result"]?.objectValue, [:])
    }

    func testDuplicateProcessIDIsRejectedThenReusableAfterExit() async throws {
        let fixture = try await makeFixture()
        try await sendRequest(
            id: 2,
            method: "command/exec",
            params: execParams(
                command: ["/bin/sleep", "30"],
                processID: "shared-process",
                extra: ["disableTimeout": true]
            ),
            to: fixture.session
        )
        try await sendRequest(
            id: 3,
            method: "command/exec",
            params: execParams(command: ["/bin/echo", "duplicate"], processID: "shared-process"),
            to: fixture.session
        )
        let duplicateRecords = try await waitForResponse(id: 3, output: fixture.output)
        XCTAssertEqual(
            error(in: response(id: 3, in: duplicateRecords))?.message,
            "duplicate active command/exec process id: \"shared-process\""
        )

        try await sendRequest(
            id: 4,
            method: "command/exec/terminate",
            params: ["processId": "shared-process"],
            to: fixture.session
        )
        _ = try await waitForResponse(id: 2, output: fixture.output)

        for generation in 0..<8 {
            let requestID = 5 + generation
            let expected = "reused-\(generation)"
            try await sendRequest(
                id: requestID,
                method: "command/exec",
                params: execParams(
                    command: ["/bin/echo", expected],
                    processID: "shared-process"
                ),
                to: fixture.session
            )
            let records = try await waitForResponse(id: requestID, output: fixture.output)
            XCTAssertEqual(
                response(id: requestID, in: records)?["result"]?.objectValue?["stdout"]?.stringValue,
                "\(expected)\n"
            )
        }
    }

    func testTimeoutUsesExitCode124() async throws {
        let fixture = try await makeFixture()
        try await sendRequest(
            id: 2,
            method: "command/exec",
            params: execParams(command: ["/bin/sleep", "5"], extra: ["timeoutMs": 20]),
            to: fixture.session
        )
        let records = try await waitForResponse(id: 2, output: fixture.output)
        XCTAssertEqual(
            response(id: 2, in: records)?["result"]?.objectValue?["exitCode"]?.numberValue,
            124
        )
    }

    func testValidationAndExperimentalCapabilityErrorsMatchCodex() async throws {
        let disabled = try await makeFixture(experimentalAPI: false)
        try await sendRequest(
            id: 2,
            method: "command/exec",
            params: execParams(command: ["/bin/echo", "no"]),
            to: disabled.session
        )
        let disabledRecords = try await waitForResponse(id: 2, output: disabled.output)
        XCTAssertEqual(
            error(in: response(id: 2, in: disabledRecords))?.message,
            "command/exec requires capabilities.experimentalApi: true"
        )

        let fixture = try await makeFixture()
        let requests: [(Int, String, [String: Any], Int, String)] = [
            (
                10,
                "command/exec",
                ["command": ["/bin/echo"], "streamStdoutStderr": true],
                -32_600,
                "command/exec tty or streaming requires a client-supplied processId"
            ),
            (
                11,
                "command/exec",
                execParams(command: ["/bin/echo"], extra: [
                    "timeoutMs": 1,
                    "disableTimeout": true
                ]),
                -32_602,
                "command/exec cannot set both timeoutMs and disableTimeout"
            ),
            (
                12,
                "command/exec",
                execParams(command: ["/bin/echo"], extra: [
                    "outputBytesCap": 1,
                    "disableOutputCap": true
                ]),
                -32_602,
                "command/exec cannot set both outputBytesCap and disableOutputCap"
            ),
            (
                13,
                "command/exec",
                execParams(command: ["/bin/echo"], extra: ["timeoutMs": -1]),
                -32_602,
                "command/exec timeoutMs must be non-negative, got -1"
            ),
            (
                14,
                "command/exec",
                [
                    "command": ["/bin/echo"],
                    "sandboxPolicy": ["type": "readOnly"],
                    "permissionProfile": ":danger-full-access"
                ],
                -32_600,
                "`permissionProfile` cannot be combined with `sandboxPolicy`"
            ),
            (
                15,
                "command/exec/terminate",
                ["processId": "missing"],
                -32_600,
                "no active command/exec for process id \"missing\""
            )
        ]
        for request in requests {
            try await sendRequest(
                id: request.0,
                method: request.1,
                params: request.2,
                to: fixture.session
            )
        }
        for request in requests {
            let records = try await waitForResponse(id: request.0, output: fixture.output)
            let rpcError = try XCTUnwrap(error(in: response(id: request.0, in: records)))
            XCTAssertEqual(rpcError.code, request.3, "request \(request.0)")
            XCTAssertEqual(rpcError.message, request.4, "request \(request.0)")
        }
    }

    func testDisconnectTerminatesProcessAndSuppressesDeferredResponse() async throws {
        let fixture = try await makeFixture()
        try await sendRequest(
            id: 2,
            method: "command/exec",
            params: execParams(
                command: ["/bin/sleep", "30"],
                processID: "disconnect",
                extra: ["disableTimeout": true]
            ),
            to: fixture.session
        )

        let started = Date()
        await fixture.session.finishInput()
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
        let records = try await fixture.output.records()
        XCTAssertNil(response(id: 2, in: records))
        XCTAssertFalse(records.contains { $0["method"]?.stringValue == "command/exec/outputDelta" })
    }

    func testMacOSSandboxBlocksReadOnlyWritesAndScopesWorkspaceWrites() async throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/sandbox-exec") else {
            throw XCTSkip("macOS Seatbelt is unavailable")
        }
        let sandboxEnvironment = ProcessInfo.processInfo.environment
        let fixture = try await makeFixture(environment: sandboxEnvironment)
        let blocked = FileManager.default.currentDirectoryPath
            + "/.command-exec-sandbox-\(UUID().uuidString)"
        let allowed = fixture.workspace.appendingPathComponent("allowed.txt").path
        addTeardownBlock { try? FileManager.default.removeItem(atPath: blocked) }

        try await sendRequest(
            id: 2,
            method: "command/exec",
            params: [
                "command": ["/bin/sh", "-c", "printf blocked > \"$1\"", "sh", blocked],
                "sandboxPolicy": ["type": "readOnly"]
            ],
            to: fixture.session
        )
        let readOnlyRecords = try await waitForResponse(id: 2, output: fixture.output)
        XCTAssertNotEqual(
            response(id: 2, in: readOnlyRecords)?["result"]?.objectValue?["exitCode"]?.numberValue,
            0
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: blocked))

        try await sendRequest(
            id: 3,
            method: "command/exec",
            params: [
                "command": [
                    "/bin/sh", "-c",
                    "printf allowed > \"$1\"; printf blocked > \"$2\"",
                    "sh", allowed, blocked
                ],
                "sandboxPolicy": ["type": "workspaceWrite"]
            ],
            to: fixture.session
        )
        let workspaceRecords = try await waitForResponse(id: 3, output: fixture.output)
        let workspaceResult = response(id: 3, in: workspaceRecords)?["result"]?.objectValue
        XCTAssertNotEqual(
            workspaceResult?["exitCode"]?.numberValue,
            0,
            "the out-of-workspace write should fail: \(String(describing: workspaceResult))"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: allowed),
            "workspace write should succeed: \(String(describing: workspaceResult))"
        )
        XCTAssertEqual(try String(contentsOfFile: allowed, encoding: .utf8), "allowed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: blocked))
    }

    func testSandboxFilesystemAliasesNeverIntroduceMissingPaths() throws {
        let directory = try temporaryDirectory(prefix: "command-exec-alias")
        let aliases = AppServerProcessSandbox.filesystemAliases(for: directory.path)

        XCTAssertTrue(aliases.contains(directory.path))
        XCTAssertTrue(aliases.allSatisfy(FileManager.default.fileExists(atPath:)))
    }
}

private extension AppServerCommandExecTests {
    var defaultPath: String {
        ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
    }

    func makeFixture(
        experimentalAPI: Bool = true,
        environment: [String: String]? = nil
    ) async throws -> CommandExecFixture {
        let home = try temporaryDirectory(prefix: "command-exec-home")
        let workspace = try temporaryDirectory(prefix: "command-exec-workspace")
        let output = CommandExecOutputCollector()
        let session = try AppServerSession(
            request: CLIAppServerRequest(live: false, home: home),
            environment: environment ?? ProcessInfo.processInfo.environment,
            currentDirectory: workspace,
            runnerFactory: { configuration in
                AgentRunner(
                    llm: CommandExecEchoLLM(),
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
                "clientInfo": ["name": "CommandExecTests", "version": "1"],
                "capabilities": ["experimentalApi": experimentalAPI]
            ],
            to: session
        )
        try await sendNotification(method: "initialized", params: [:], to: session)
        return CommandExecFixture(session: session, output: output, workspace: workspace)
    }

    func execParams(
        command: [String],
        processID: String? = nil,
        extra: [String: Any] = [:]
    ) -> [String: Any] {
        var result: [String: Any] = [
            "command": command,
            "permissionProfile": ":danger-full-access"
        ]
        if let processID { result["processId"] = processID }
        result.merge(extra) { _, new in new }
        return result
    }

    func waitForResponse(
        id: Int,
        output: CommandExecOutputCollector
    ) async throws -> [[String: CLIJSONValue]] {
        try await waitForRecords(output: output, description: "response id \(id)") { records in
            response(id: id, in: records) == nil ? nil : records
        }
    }

    func waitForNotification(
        _ method: String,
        output: CommandExecOutputCollector
    ) async throws -> [[String: CLIJSONValue]] {
        try await waitForRecords(output: output, description: method) { records in
            records.contains { $0["method"]?.stringValue == method } ? records : nil
        }
    }

    func waitForRecords<Value>(
        output: CommandExecOutputCollector,
        description: String,
        match: ([[String: CLIJSONValue]]) -> Value?
    ) async throws -> Value {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(30))
        while clock.now < deadline {
            if let value = match(try await output.records()) { return value }
            try await clock.sleep(for: .milliseconds(10))
        }
        throw CommandExecTestError.timedOut(description)
    }

    func streamedText(in records: [[String: CLIJSONValue]]) throws -> String {
        try records
            .filter { $0["method"]?.stringValue == "command/exec/outputDelta" }
            .map { record in
                let encoded = try XCTUnwrap(
                    record["params"]?.objectValue?["deltaBase64"]?.stringValue
                )
                return String(
                    decoding: try XCTUnwrap(Data(base64Encoded: encoded)),
                    as: UTF8.self
                )
            }
            .joined()
    }

    func response(
        id: Int,
        in records: [[String: CLIJSONValue]]
    ) -> [String: CLIJSONValue]? {
        records.first { $0["id"]?.numberValue == Double(id) }
    }

    func error(in response: [String: CLIJSONValue]?) -> AppServerRPCError? {
        guard let object = response?["error"]?.objectValue,
              let code = object["code"]?.numberValue,
              let message = object["message"]?.stringValue else { return nil }
        return AppServerRPCError(
            code: Int(code),
            message: message,
            data: object["data"]
        )
    }

    func sendRequest(
        id: Int,
        method: String,
        params: [String: Any],
        to session: AppServerSession
    ) async throws {
        try await send(["id": id, "method": method, "params": params], to: session)
    }

    func sendNotification(
        method: String,
        params: [String: Any],
        to session: AppServerSession
    ) async throws {
        try await send(["method": method, "params": params], to: session)
    }

    func send(_ value: [String: Any], to session: AppServerSession) async throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        await session.receive(data)
    }

    func temporaryDirectory(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}

private struct CommandExecFixture {
    var session: AppServerSession
    var output: CommandExecOutputCollector
    var workspace: URL
}

private actor CommandExecOutputCollector {
    private var lines: [String] = []

    func append(_ line: String) { lines.append(line) }

    func records() throws -> [[String: CLIJSONValue]] {
        try lines.map { line in
            guard let record = try CLIJSONCodec.decode(line).objectValue else {
                throw CommandExecTestError.invalidRecord
            }
            return record
        }
    }
}

private struct CommandExecEchoLLM: LLMClient {
    func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AgentAction {
        .say(userMessage)
    }
}

private enum CommandExecTestError: Error {
    case invalidRecord
    case timedOut(String)
}
