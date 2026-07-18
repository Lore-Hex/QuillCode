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

    /// Runs the driver binary directly (argv[0] is the executable path, not a shell), so no argument
    /// is ever interpreted by a shell.
    public static let defaultRunProcess: @Sendable (_ arguments: [String], _ stdin: Data?) async throws -> ProcessRunResult = { arguments, stdin in
        #if canImport(Glibc) || canImport(Darwin)
        guard let executable = arguments.first else {
            throw CuaDriverError.driverNotFound("(empty argv)")
        }
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw CuaDriverError.driverNotFound(executable)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(arguments.dropFirst())
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        if stdin != nil {
            process.standardInput = Pipe()
        }
        try process.run()
        if let stdin, let inputPipe = process.standardInput as? Pipe {
            inputPipe.fileHandleForWriting.write(stdin)
            try? inputPipe.fileHandleForWriting.close()
        }
        // Read fully before waitUntilExit to avoid a pipe-buffer deadlock on large screenshots.
        let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ProcessRunResult(exitCode: process.terminationStatus, stdout: outData, stderr: errData)
        #else
        throw CuaDriverError.driverNotFound("Subprocess execution unavailable on this platform")
        #endif
    }
}
