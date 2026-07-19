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
        public init(exitCode: Int32, stdout: Data, stderr: Data) {
            self.exitCode = exitCode
            self.stdout = stdout
            self.stderr = stderr
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
            let stderr = String(data: result.stderr, encoding: .utf8) ?? ""
            let stdout = String(data: result.stdout, encoding: .utf8) ?? ""
            let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                : stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw CuaDriverError.toolFailed(tool: name, message: String(message.prefix(400)))
        }
        return result.stdout
    }

    /// Wall-clock ceiling for a single driver call. A screenshot read is a few MB and completes in
    /// well under a second; this only bounds a hung/streaming child so the computer-use loop can never
    /// wedge indefinitely in the unattended-coworker case.
    public static let defaultTimeout: TimeInterval = 60

    /// Runs the driver binary directly (argv[0] is the executable path, not a shell), so no argument
    /// is ever interpreted by a shell.
    ///
    /// Three properties the naive version lacked: (1) stdout and stderr are drained **concurrently**,
    /// so a child that fills the stderr pipe (verbose logs, a backtrace) while we read the multi-MB
    /// screenshot on stdout can't deadlock; (2) a timeout terminates — then hard-kills — a hung child;
    /// (3) cancelling the owning Task terminates the child instead of leaking it.
    public static let defaultRunProcess: @Sendable (_ arguments: [String], _ stdin: Data?) async throws -> ProcessRunResult = { arguments, stdin in
        try await runProcess(arguments: arguments, stdin: stdin, timeout: defaultTimeout)
    }

    static func runProcess(
        arguments: [String],
        stdin: Data?,
        timeout: TimeInterval
    ) async throws -> ProcessRunResult {
        #if canImport(Glibc) || canImport(Darwin)
        guard let executable = arguments.first else {
            throw CuaDriverError.driverNotFound("(empty argv)")
        }
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw CuaDriverError.driverNotFound(executable)
        }
        let handle = ProcessHandle()
        return try await withTaskCancellationHandler {
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
                            handle: handle
                        )
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            handle.terminate()
        }
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
        handle: ProcessHandle
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
        handle.attach(process)
        try process.run()
        if let stdin, let inputPipe = process.standardInput as? Pipe {
            inputPipe.fileHandleForWriting.write(stdin)
            try? inputPipe.fileHandleForWriting.close()
        }

        // Drain both pipes on independent queues; each read completes when the child closes that pipe
        // (at exit). Waiting on the group therefore waits for exit AND full drain, with no ordering
        // hazard between the two streams.
        let outBox = DataBox()
        let errBox = DataBox()
        let group = DispatchGroup()
        let ioQueue = DispatchQueue(label: "com.quillcode.cua.pipe", attributes: .concurrent)
        group.enter()
        ioQueue.async { outBox.set(stdoutPipe.fileHandleForReading.readDataToEndOfFile()); group.leave() }
        group.enter()
        ioQueue.async { errBox.set(stderrPipe.fileHandleForReading.readDataToEndOfFile()); group.leave() }

        if group.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if group.wait(timeout: .now() + 2) == .timedOut {
                handle.kill()
                _ = group.wait(timeout: .now() + 2)
            }
            process.waitUntilExit()
            throw CuaDriverError.toolFailed(
                tool: (arguments.first ?? "cua-driver"),
                message: "cua-driver timed out after \(Int(timeout))s"
            )
        }
        process.waitUntilExit()
        return ProcessRunResult(exitCode: process.terminationStatus, stdout: outBox.get(), stderr: errBox.get())
    }
    #endif
}

#if canImport(Glibc) || canImport(Darwin)
/// Lock-guarded accumulator so pipe reads on background queues don't data-race the captured buffers.
private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func set(_ value: Data) { lock.lock(); data = value; lock.unlock() }
    func get() -> Data { lock.lock(); defer { lock.unlock() }; return data }
}

/// Holds the running process so the Task-cancellation handler can terminate/kill it from another
/// thread. `Process` isn't `Sendable`; access is serialized by the lock.
private final class ProcessHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    func attach(_ process: Process) { lock.lock(); self.process = process; lock.unlock() }
    func terminate() {
        lock.lock(); defer { lock.unlock() }
        if let process, process.isRunning { process.terminate() }
    }
    func kill() {
        lock.lock(); defer { lock.unlock() }
        if let process, process.isRunning { Foundation.kill(process.processIdentifier, SIGKILL) }
    }
}
#endif
