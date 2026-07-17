import Foundation
import QuillCodeTools

extension AppServerExecServerWebSocketClient {
    private static var processReadBytes: Int { 64 * 1_024 }
    private static var processReadWaitMilliseconds: Int { 1_000 }

    func runProcess(
        _ request: AppServerRemoteProcessRequest
    ) async throws -> AppServerRemoteProcessResult {
        let processID = "quillcode-\(UUID().uuidString.lowercased())"
        let start = try await self.request(method: "process/start", params: .object([
            "arg0": .null,
            "argv": .array(request.argv.map(CLIJSONValue.string)),
            "cwd": .string(request.cwdURI),
            "enforceManagedNetwork": .bool(false),
            "env": .object(request.environment.mapValues(CLIJSONValue.string)),
            "envPolicy": .null,
            "managedNetwork": .null,
            "pipeStdin": .bool(false),
            "processId": .string(processID),
            "sandbox": request.sandbox.rpcValue,
            "tty": .bool(false)
        ]))
        guard start.objectValue?["processId"]?.stringValue == processID else {
            throw AppServerExecServerError.invalidResponse(
                "process/start did not acknowledge the requested process id"
            )
        }

        return try await withTaskCancellationHandler {
            try await collectProcess(
                processID: processID,
                timeoutSeconds: request.timeoutSeconds
            )
        } onCancel: { [weak self] in
            Task { await self?.terminateProcess(processID) }
        }
    }

    private func collectProcess(
        processID: String,
        timeoutSeconds: TimeInterval
    ) async throws -> AppServerRemoteProcessResult {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: appServerDuration(seconds: timeoutSeconds))
        var afterSequence: UInt64?
        var stdout = ShellOutputAccumulator()
        var stderr = ShellOutputAccumulator()
        var terminalExitCode: Int32?
        var terminalFailure: String?
        var sandboxDenied = false

        while true {
            try Task.checkCancellation()
            guard clock.now < deadline else {
                await terminateProcess(processID)
                throw AppServerExecServerError.timedOut(
                    operation: "process",
                    seconds: timeoutSeconds
                )
            }
            let result = try await request(method: "process/read", params: .object([
                "afterSeq": afterSequence.map { .number(Double($0)) } ?? .null,
                "maxBytes": .number(Double(Self.processReadBytes)),
                "processId": .string(processID),
                "waitMs": .number(Double(Self.processReadWaitMilliseconds))
            ]))
            guard let object = result.objectValue,
                  let chunks = object["chunks"]?.arrayValue,
                  let rawNextSequence = object["nextSeq"]?.numberValue,
                  let exited = object["exited"]?.boolValue,
                  let closed = object["closed"]?.boolValue else {
                throw AppServerExecServerError.invalidResponse(
                    "process/read returned a malformed response"
                )
            }
            let nextSequence = try Self.decodeUInt64(
                rawNextSequence,
                malformedResponse: "process/read returned a malformed response"
            )
            for chunk in chunks {
                guard let chunkObject = chunk.objectValue,
                      let stream = chunkObject["stream"]?.stringValue,
                      ["stdout", "stderr"].contains(stream),
                      let encoded = chunkObject["chunk"]?.stringValue,
                      let data = Data(base64Encoded: encoded) else {
                    throw AppServerExecServerError.invalidResponse(
                        "process/read returned a malformed output chunk"
                    )
                }
                let text = String(decoding: data, as: UTF8.self)
                if stream == "stderr" {
                    stderr.append(text)
                } else {
                    stdout.append(text)
                }
            }
            // Exec-server's cursor is inclusive: afterSeq is the last event observed, while
            // nextSeq is the first event not included in this response. Preserve the previous
            // cursor when a server reports zero, matching Codex's checked_sub(1).or(afterSeq).
            if nextSequence > 0 {
                afterSequence = max(afterSequence ?? 0, nextSequence - 1)
            }
            if let exitCode = object["exitCode"]?.numberValue {
                guard exitCode.rounded() == exitCode,
                      exitCode >= Double(Int32.min),
                      exitCode <= Double(Int32.max) else {
                    throw AppServerExecServerError.invalidResponse(
                        "process/read returned an invalid exit code"
                    )
                }
                terminalExitCode = Int32(exitCode)
            }
            if let failure = object["failure"], failure != .null {
                guard let value = failure.stringValue else {
                    throw AppServerExecServerError.invalidResponse(
                        "process/read returned an invalid failure"
                    )
                }
                terminalFailure = value
            }
            if let denied = object["sandboxDenied"], denied != .null {
                guard let value = denied.boolValue else {
                    throw AppServerExecServerError.invalidResponse(
                        "process/read returned an invalid sandbox status"
                    )
                }
                sandboxDenied = value
            }
            if closed || terminalFailure != nil || sandboxDenied {
                guard exited || terminalFailure != nil || sandboxDenied else {
                    throw AppServerExecServerError.invalidResponse(
                        "process/read closed before reporting a terminal state"
                    )
                }
                guard terminalExitCode != nil || terminalFailure != nil || sandboxDenied else {
                    throw AppServerExecServerError.invalidResponse(
                        "process/read reached a terminal state without an exit status"
                    )
                }
                return AppServerRemoteProcessResult(
                    stdout: stdout.text,
                    stderr: stderr.text,
                    exitCode: terminalExitCode ?? (terminalFailure == nil ? 0 : 1),
                    failure: terminalFailure,
                    sandboxDenied: sandboxDenied
                )
            }
        }
    }

    private func terminateProcess(_ processID: String) async {
        _ = try? await request(method: "process/terminate", params: .object([
            "processId": .string(processID)
        ]))
    }
}
