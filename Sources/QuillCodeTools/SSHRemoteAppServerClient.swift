import Foundation
import QuillCodeCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

final class SSHRemoteAppServerClient: @unchecked Sendable {
    static let maximumMessageBytes = 4 * 1_024 * 1_024

    private let connection: ProjectConnection
    private let sshExecutor: SSHRemoteShellExecutor
    private let quillCodeExecutable: String
    private let environment: [String: String]
    private let handshakeTimeoutSeconds: TimeInterval
    private let ioLock = NSLock()
    private let processLock = NSLock()
    private let standardErrorBuffer = BoundedSSHAppServerErrorBuffer()

    private var process: Process?
    private var standardInput: FileHandle?
    private var standardOutput: FileHandle?
    private var standardError: FileHandle?
    private var readBuffer = Data()
    private var nextRequestID = 1
    private var ready = false

    init(
        connection: ProjectConnection,
        sshExecutor: SSHRemoteShellExecutor,
        quillCodeExecutable: String,
        environment: [String: String],
        handshakeTimeoutSeconds: TimeInterval
    ) {
        self.connection = connection
        self.sshExecutor = sshExecutor
        self.quillCodeExecutable = quillCodeExecutable
        self.environment = environment
        self.handshakeTimeoutSeconds = handshakeTimeoutSeconds
    }

    deinit {
        cancelCurrentRequest()
    }

    func executeShell(
        command: String,
        timeoutSeconds: TimeInterval
    ) -> SSHRemoteAppServerExecutionOutcome {
        ioLock.lock()
        defer { ioLock.unlock() }

        let command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            return .completed(ToolResult(ok: false, error: ShellToolMessages.missingCommand))
        }

        do {
            try connectIfNeededLocked()
        } catch {
            teardownLocked()
            return .unavailableBeforeExecution(failureMessage(error))
        }

        let requestID = nextIDLocked()
        var requestMayHaveStarted = false
        do {
            let timeoutMilliseconds = Int64(max(1, min(timeoutSeconds * 1_000, Double(Int64.max))))
            try writeLocked([
                "id": requestID,
                "method": "command/exec",
                "params": [
                    "command": ["/bin/sh", "-lc", command],
                    "permissionProfile": ":danger-full-access",
                    "timeoutMs": timeoutMilliseconds
                ]
            ])
            requestMayHaveStarted = true
            let result = try readResultLocked(
                id: requestID,
                deadline: Date().addingTimeInterval(max(1, timeoutSeconds) + 2)
            )
            return .completed(Self.toolResult(from: result))
        } catch let error as SSHRemoteAppServerClientError where error.isDefinitiveResponseError {
            return .completed(ToolResult(ok: false, error: failureMessage(error)))
        } catch {
            let message = failureMessage(error)
            teardownLocked()
            return requestMayHaveStarted
                ? .executionStateUnknown(message)
                : .unavailableBeforeExecution(message)
        }
    }

    func cancelCurrentRequest() {
        processLock.lock()
        let activeProcess = process
        processLock.unlock()
        if activeProcess?.isRunning == true {
            activeProcess?.terminate()
        }
    }

    func close() {
        cancelCurrentRequest()
        ioLock.lock()
        teardownLocked()
        ioLock.unlock()
    }

    private func connectIfNeededLocked() throws {
        if ready, processSnapshot()?.isRunning == true { return }
        teardownLocked()

        let innerCommand = "exec \(SSHRemoteInvocation.shellSingleQuoted(quillCodeExecutable)) app-server --stdio"
        let loginShellCommand = "exec \"${SHELL:-/bin/sh}\" -lc \(SSHRemoteInvocation.shellSingleQuoted(innerCommand))"
        guard let invocation = sshExecutor.projectInvocation(
            command: loginShellCommand,
            connection: connection
        ) else {
            throw SSHRemoteAppServerClientError.invalidConnection
        }

        let process = Process()
        let workingDirectory = FileManager.default.homeDirectoryForCurrentUser
        let launch = MCPProcessLaunchConfiguration.resolve(
            command: invocation.executable,
            arguments: invocation.arguments,
            environment: environment,
            workingDirectory: workingDirectory
        )
        process.executableURL = launch.executableURL
        process.arguments = launch.arguments
        process.currentDirectoryURL = workingDirectory
        if !launch.environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(
                launch.environment,
                uniquingKeysWith: { _, configured in configured }
            )
        }

        let input = Pipe()
        let output = Pipe()
        let errorPipe = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errorPipe
        standardErrorBuffer.reset()
        errorPipe.fileHandleForReading.readabilityHandler = { [standardErrorBuffer] handle in
            standardErrorBuffer.append(handle.availableData)
        }

        do {
            try process.run()
        } catch {
            errorPipe.fileHandleForReading.readabilityHandler = nil
            throw SSHRemoteAppServerClientError.launchFailed(error.localizedDescription)
        }

        setProcess(process)
        standardInput = input.fileHandleForWriting
        standardOutput = output.fileHandleForReading
        standardError = errorPipe.fileHandleForReading
        readBuffer.removeAll(keepingCapacity: true)
        ready = false
        nextRequestID = 1

        let initializeID = nextIDLocked()
        try writeLocked([
            "id": initializeID,
            "method": "initialize",
            "params": [
                "clientInfo": ["name": "quillcode-ssh-remote", "version": "1"],
                "capabilities": ["experimentalApi": true]
            ]
        ])
        _ = try readResultLocked(
            id: initializeID,
            deadline: Date().addingTimeInterval(handshakeTimeoutSeconds)
        )
        try writeLocked(["method": "initialized", "params": [:]])
        ready = true
    }

    private func nextIDLocked() -> Int {
        defer { nextRequestID += 1 }
        return nextRequestID
    }

    private func writeLocked(_ object: [String: Any]) throws {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw SSHRemoteAppServerClientError.invalidMessage("request is not valid JSON")
        }
        guard let standardInput else {
            throw SSHRemoteAppServerClientError.disconnected
        }
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        data.append(0x0A)
        guard data.count <= Self.maximumMessageBytes else {
            throw SSHRemoteAppServerClientError.invalidMessage("request exceeds the message limit")
        }
        try standardInput.write(contentsOf: data)
    }

    private func readResultLocked(id: Int, deadline: Date) throws -> [String: Any] {
        while Date() < deadline {
            if let line = try nextLineLocked(deadline: deadline) {
                guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    throw SSHRemoteAppServerClientError.invalidMessage("response must be a JSON object")
                }
                guard Self.matchesID(object["id"], id) else { continue }
                if let error = object["error"] as? [String: Any] {
                    let message = error["message"] as? String ?? "remote app server returned an error"
                    throw SSHRemoteAppServerClientError.responseError(message)
                }
                guard let result = object["result"] as? [String: Any] else {
                    throw SSHRemoteAppServerClientError.invalidMessage("response did not include a result object")
                }
                return result
            }
        }
        throw SSHRemoteAppServerClientError.timeout
    }

    private func nextLineLocked(deadline: Date) throws -> Data? {
        while Date() < deadline {
            if let newline = readBuffer.firstIndex(of: 0x0A) {
                let line = Data(readBuffer[..<newline])
                readBuffer.removeSubrange(...newline)
                if line.isEmpty { continue }
                return line
            }
            guard readBuffer.count <= Self.maximumMessageBytes else {
                throw SSHRemoteAppServerClientError.invalidMessage("response exceeds the message limit")
            }
            let remaining = min(0.1, max(0.01, deadline.timeIntervalSinceNow))
            guard let data = try readAvailableDataLocked(timeout: remaining) else { continue }
            guard !data.isEmpty else { throw SSHRemoteAppServerClientError.disconnected }
            readBuffer.append(data)
        }
        return nil
    }

    private func readAvailableDataLocked(timeout: TimeInterval) throws -> Data? {
        guard let standardOutput else { throw SSHRemoteAppServerClientError.disconnected }
        let timeoutMilliseconds = Int32(max(1, min(timeout * 1_000, Double(Int32.max))))
        var descriptor = pollfd(
            fd: Int32(standardOutput.fileDescriptor),
            events: Int16(POLLIN),
            revents: 0
        )
        let result = poll(&descriptor, 1, timeoutMilliseconds)
        if result == 0 { return nil }
        guard result > 0 else {
            throw SSHRemoteAppServerClientError.ioFailure("stdout poll failed with errno \(errno)")
        }

        var bytes = [UInt8](repeating: 0, count: 64 * 1_024)
        let count = read(descriptor.fd, &bytes, bytes.count)
        guard count >= 0 else {
            throw SSHRemoteAppServerClientError.ioFailure("stdout read failed with errno \(errno)")
        }
        return Data(bytes.prefix(count))
    }

    private func teardownLocked() {
        ready = false
        standardError?.readabilityHandler = nil
        try? standardInput?.close()
        try? standardOutput?.close()
        try? standardError?.close()
        standardInput = nil
        standardOutput = nil
        standardError = nil
        readBuffer.removeAll(keepingCapacity: false)

        processLock.lock()
        let activeProcess = process
        process = nil
        processLock.unlock()
        if activeProcess?.isRunning == true { activeProcess?.terminate() }
    }

    private func setProcess(_ process: Process?) {
        processLock.lock()
        self.process = process
        processLock.unlock()
    }

    private func processSnapshot() -> Process? {
        processLock.lock()
        defer { processLock.unlock() }
        return process
    }

    private func failureMessage(_ error: Error) -> String {
        let detail = standardErrorBuffer.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = String(describing: error)
        let combined = detail.isEmpty ? base : "\(base): \(detail)"
        return ShellOutputCapper.cap(combined).text
    }

    private static func matchesID(_ value: Any?, _ expected: Int) -> Bool {
        if let number = value as? NSNumber { return number.intValue == expected }
        if let string = value as? String { return string == String(expected) }
        return false
    }

    private static func toolResult(from result: [String: Any]) -> ToolResult {
        let exitCode = (result["exitCode"] as? NSNumber)?.int32Value ?? -1
        let stdout = ShellOutputCapper.cap(result["stdout"] as? String ?? "").text
        let stderr = ShellOutputCapper.cap(result["stderr"] as? String ?? "").text
        return ToolResult(
            ok: exitCode == 0,
            stdout: stdout,
            stderr: stderr,
            exitCode: exitCode,
            error: exitCode == 0 ? nil : "Command failed with exit code \(exitCode)."
        )
    }
}

private enum SSHRemoteAppServerClientError: Error, CustomStringConvertible {
    case invalidConnection
    case launchFailed(String)
    case disconnected
    case timeout
    case responseError(String)
    case invalidMessage(String)
    case ioFailure(String)

    var isDefinitiveResponseError: Bool {
        if case .responseError = self { return true }
        return false
    }

    var description: String {
        switch self {
        case .invalidConnection: "SSH Remote project is missing a usable host."
        case .launchFailed(let detail): "Failed to launch the remote QuillCode app server: \(detail)"
        case .disconnected: "The remote QuillCode app server disconnected."
        case .timeout: "The remote QuillCode app server did not respond before the timeout."
        case .responseError(let detail): "Remote app-server request failed: \(detail)"
        case .invalidMessage(let detail): "Remote app-server protocol error: \(detail)"
        case .ioFailure(let detail): "Remote app-server transport error: \(detail)"
        }
    }
}

private final class BoundedSSHAppServerErrorBuffer: @unchecked Sendable {
    private static let maximumBytes = 16 * 1_024
    private let lock = NSLock()
    private var bytes = Data()

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: bytes, as: UTF8.self)
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        bytes.append(data)
        if bytes.count > Self.maximumBytes {
            bytes.removeFirst(bytes.count - Self.maximumBytes)
        }
        lock.unlock()
    }

    func reset() {
        lock.lock()
        bytes.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}
