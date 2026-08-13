import Foundation

/// Production `CuaDriverToolInvoking`: runs `cua-driver call <tool> <args-json>` as a one-shot
/// subprocess per action and returns its stdout. cua-driver's `call` path is standalone (no separate
/// daemon required) and its tools default to background delivery, so each action lands without
/// stealing focus or moving the user's cursor. Telemetry is disabled once at first use so no
/// automation metadata leaves the machine — QuillCode's privacy posture, not cua's default.
public struct CuaDriverProcessClient: CuaDriverToolInvoking {
    public let driverPath: String
    private let runProcess: @Sendable (_ arguments: [String], _ stdin: Data?) async throws -> ProcessRunResult

    public struct ProcessRunResult: Sendable {
        public var exitCode: Int32
        public var stdout: Data
        public var stderr: Data
        public var stdoutByteCount: Int
        public var stderrByteCount: Int
        public var stdoutWasTruncated: Bool
        public var stderrWasTruncated: Bool
        public var stdoutReadCompleted: Bool
        public var stderrReadCompleted: Bool

        public init(
            exitCode: Int32,
            stdout: Data,
            stderr: Data,
            stdoutByteCount: Int? = nil,
            stderrByteCount: Int? = nil,
            stdoutWasTruncated: Bool = false,
            stderrWasTruncated: Bool = false,
            stdoutReadCompleted: Bool = true,
            stderrReadCompleted: Bool = true
        ) {
            self.exitCode = exitCode
            self.stdout = stdout
            self.stderr = stderr
            self.stdoutByteCount = max(stdout.count, stdoutByteCount ?? stdout.count)
            self.stderrByteCount = max(stderr.count, stderrByteCount ?? stderr.count)
            self.stdoutWasTruncated = stdoutWasTruncated
            self.stderrWasTruncated = stderrWasTruncated
            self.stdoutReadCompleted = stdoutReadCompleted
            self.stderrReadCompleted = stderrReadCompleted
        }
    }

    public init(
        driverPath: String,
        runProcess: @escaping @Sendable (_ arguments: [String], _ stdin: Data?) async throws -> ProcessRunResult = CuaDriverProcessClient.defaultRunProcess
    ) {
        self.driverPath = driverPath
        self.runProcess = runProcess
    }

    public func callTool(name: String, argumentsJSON: Data) async throws -> Data {
        let argsString = String(data: argumentsJSON, encoding: .utf8) ?? "{}"
        let result = try await runProcess([driverPath, "call", name, argsString], nil)
        guard result.exitCode == 0 else {
            let stderr = String(decoding: result.stderr, as: UTF8.self)
            let stdout = String(decoding: result.stdout, as: UTF8.self)
            let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                : stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let truncationNote = result.stderrWasTruncated || (stderr.isEmpty && result.stdoutWasTruncated)
                ? "[diagnostic tail truncated] "
                : ""
            throw CuaDriverError.toolFailed(
                tool: name,
                message: truncationNote + String(message.prefix(400))
            )
        }
        guard result.stdoutReadCompleted else {
            throw CuaDriverError.toolFailed(
                tool: name,
                message: "cua-driver response ended before its output stream could be read completely"
            )
        }
        guard !result.stdoutWasTruncated else {
            throw CuaDriverError.toolFailed(
                tool: name,
                message: "cua-driver response exceeded the 32 MiB safety limit and was rejected"
            )
        }
        return result.stdout
    }

    /// Wall-clock ceiling for a single driver call. A screenshot read is a few MB and completes in
    /// well under a second; this only bounds a hung/streaming child so the computer-use loop can never
    /// wedge indefinitely in the unattended-coworker case.
    public static let defaultTimeout: TimeInterval = 60
    public static let maximumStandardOutputBytes = 32 * 1_024 * 1_024
    public static let maximumStandardErrorBytes = 256 * 1_024
    private static let defaultTerminationGraceSeconds: TimeInterval = 2

    /// Runs the driver binary directly (argv[0] is the executable path, not a shell), so no argument
    /// is ever interpreted by a shell.
    ///
    /// The process boundary drains stdout and stderr concurrently with independent residency caps,
    /// tracks timeout against process exit rather than pipe closure, and gives timeout/cancellation a
    /// bounded terminate-then-kill path. A noisy or uncooperative driver therefore cannot deadlock a
    /// pipe, grow the app without bound, or outlive the task that owns it.
    public static let defaultRunProcess: @Sendable (_ arguments: [String], _ stdin: Data?) async throws -> ProcessRunResult = { arguments, stdin in
        try await runProcess(arguments: arguments, stdin: stdin, timeout: defaultTimeout)
    }

    static func runProcess(
        arguments: [String],
        stdin: Data?,
        timeout: TimeInterval,
        stdoutByteLimit: Int = maximumStandardOutputBytes,
        stderrByteLimit: Int = maximumStandardErrorBytes,
        terminationGraceSeconds: TimeInterval = defaultTerminationGraceSeconds
    ) async throws -> ProcessRunResult {
        #if canImport(Glibc) || canImport(Darwin)
        try Task.checkCancellation()
        guard let executable = arguments.first else {
            throw CuaDriverError.driverNotFound("(empty argv)")
        }
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw CuaDriverError.driverNotFound(executable)
        }
        let handle = CuaDriverProcessHandle()
        let result = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProcessRunResult, Error>) in
                // Run the blocking Foundation work off the cooperative pool so a slow child never ties
                // up a Swift-concurrency worker thread.
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let result = try runBlocking(
                            executable: executable,
                            arguments: Array(arguments.dropFirst()),
                            stdin: stdin,
                            timeout: timeout,
                            stdoutByteLimit: stdoutByteLimit,
                            stderrByteLimit: stderrByteLimit,
                            terminationGraceSeconds: terminationGraceSeconds,
                            handle: handle
                        )
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            handle.requestCancellation(terminationGraceSeconds: terminationGraceSeconds)
        }
        try Task.checkCancellation()
        return result
        #else
        throw CuaDriverError.driverNotFound("Subprocess execution unavailable on this platform")
        #endif
    }

    #if canImport(Glibc) || canImport(Darwin)
    private static func runBlocking(
        executable: String,
        arguments: [String],
        stdin: Data?,
        timeout: TimeInterval,
        stdoutByteLimit: Int,
        stderrByteLimit: Int,
        terminationGraceSeconds: TimeInterval,
        handle: CuaDriverProcessHandle
    ) throws -> ProcessRunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        if stdin != nil {
            process.standardInput = Pipe()
        }
        let processCompletion = DispatchGroup()
        processCompletion.enter()
        process.terminationHandler = { _ in processCompletion.leave() }
        handle.attach(process)
        try process.run()
        handle.terminateIfCancellationRequested()

        let stdoutCapture = CuaDriverBoundedPipeCapture(
            handle: stdoutPipe.fileHandleForReading,
            byteLimit: stdoutByteLimit,
            retention: .prefix
        )
        let stderrCapture = CuaDriverBoundedPipeCapture(
            handle: stderrPipe.fileHandleForReading,
            byteLimit: stderrByteLimit,
            retention: .suffix
        )
        stdoutCapture.start()
        stderrCapture.start()

        if let stdin, let inputPipe = process.standardInput as? Pipe {
            inputPipe.fileHandleForWriting.write(stdin)
            try? inputPipe.fileHandleForWriting.close()
        }

        let boundedTimeout = max(0, timeout)
        if processCompletion.wait(timeout: .now() + boundedTimeout) == .timedOut {
            handle.terminate()
            if processCompletion.wait(timeout: .now() + max(0, terminationGraceSeconds)) == .timedOut {
                handle.kill()
                _ = processCompletion.wait(timeout: .now() + max(0, terminationGraceSeconds))
            }
            _ = stdoutCapture.finishAfterProcessExit(graceSeconds: terminationGraceSeconds)
            _ = stderrCapture.finishAfterProcessExit(graceSeconds: terminationGraceSeconds)
            throw CuaDriverError.toolFailed(
                tool: (arguments.first ?? "cua-driver"),
                message: "cua-driver timed out after \(Int(timeout))s"
            )
        }

        let stdout = stdoutCapture.finishAfterProcessExit(graceSeconds: terminationGraceSeconds)
        let stderr = stderrCapture.finishAfterProcessExit(graceSeconds: terminationGraceSeconds)
        return ProcessRunResult(
            exitCode: process.terminationStatus,
            stdout: stdout.data,
            stderr: stderr.data,
            stdoutByteCount: stdout.totalByteCount,
            stderrByteCount: stderr.totalByteCount,
            stdoutWasTruncated: stdout.wasTruncated,
            stderrWasTruncated: stderr.wasTruncated,
            stdoutReadCompleted: stdout.readCompleted,
            stderrReadCompleted: stderr.readCompleted
        )
    }
    #endif
}
