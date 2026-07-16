import Foundation
import QuillCodeCore

final class ShellStreamingProcessRunner: @unchecked Sendable {
    private enum OutputStream {
        case stdout
        case stderr
    }

    private let request: ShellExecutionRequest
    private let continuation: AsyncStream<ShellProcessEvent>.Continuation
    private let lock = NSLock()
    private var process: Process?
    private var standardInput: Pipe?
    private var stdout = ShellOutputAccumulator()
    private var stderr = ShellOutputAccumulator()
    private var didFinish = false
    private var didCancel = false
    private var didTimeOut = false

    init(
        request: ShellExecutionRequest,
        continuation: AsyncStream<ShellProcessEvent>.Continuation
    ) {
        self.request = request
        self.continuation = continuation
    }

    func start() {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            run()
        }
    }

    func cancel() {
        let activeProcess: Process?
        let activeInput: Pipe?
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didCancel = true
        activeProcess = process
        activeInput = standardInput
        lock.unlock()
        try? activeInput?.fileHandleForWriting.close()
        activeProcess?.terminate()
    }

    func sendInput(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let input: Pipe?
        lock.lock()
        guard !didFinish, !didCancel, !didTimeOut else {
            lock.unlock()
            return false
        }
        input = standardInput
        lock.unlock()

        guard let input else { return false }
        do {
            try input.fileHandleForWriting.write(contentsOf: Data(text.utf8))
            return true
        } catch {
            return false
        }
    }

    private func run() {
        let trimmed = request.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            finish(
                stdout: "",
                stderr: "",
                exitCode: nil,
                ok: false,
                error: ShellToolMessages.missingCommand
            )
            return
        }

        let process = Process()
        process.executableURL = request.shellExecutableURL
        process.arguments = ["-lc", trimmed]
        process.currentDirectoryURL = request.cwd
        process.environment = request.environment

        let standardOutput = Pipe()
        let standardError = Pipe()
        let standardInput = Pipe()
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError

        lock.lock()
        if didCancel {
            lock.unlock()
            finishCancelled()
            return
        }
        self.standardInput = standardInput
        lock.unlock()

        do {
            try process.run()
        } catch {
            finish(
                stdout: "",
                stderr: "",
                exitCode: nil,
                ok: false,
                error: "Failed to start shell: \(error)"
            )
            return
        }

        lock.lock()
        self.process = process
        let shouldTerminate = didCancel
        lock.unlock()

        let readers = DispatchGroup()
        startReader(standardOutput, stream: .stdout, readers: readers)
        startReader(standardError, stream: .stderr, readers: readers)
        if shouldTerminate {
            process.terminate()
        }

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + request.timeoutSeconds) { [weak self] in
            self?.timeout()
        }

        process.waitUntilExit()
        readers.wait()
        finish(process: process)
    }

    private func startReader(_ pipe: Pipe, stream: OutputStream, readers: DispatchGroup) {
        readers.enter()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            defer { readers.leave() }
            while true {
                let data = pipe.fileHandleForReading.availableData
                if data.isEmpty {
                    return
                }
                self?.handleOutput(data, stream: stream)
            }
        }
    }

    private func handleOutput(_ data: Data, stream: OutputStream) {
        guard !data.isEmpty else { return }
        let text = String(decoding: data, as: UTF8.self)
        lock.lock()
        switch stream {
        case .stdout:
            stdout.append(text)
        case .stderr:
            stderr.append(text)
        }
        lock.unlock()
        switch stream {
        case .stdout:
            continuation.yield(.stdout(text))
        case .stderr:
            continuation.yield(.stderr(text))
        }
    }

    private func timeout() {
        let activeProcess: Process?
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didTimeOut = true
        activeProcess = process
        lock.unlock()
        activeProcess?.terminate()
    }

    private func finish(process: Process) {
        let out: String
        let err: String
        let cancelled: Bool
        let timedOut: Bool
        lock.lock()
        out = stdout.text
        err = stderr.text
        cancelled = didCancel
        timedOut = didTimeOut
        lock.unlock()

        if cancelled {
            finish(stdout: out, stderr: err, exitCode: nil, ok: false, error: "Command cancelled.")
            return
        }
        if timedOut {
            finish(
                stdout: out,
                stderr: err,
                exitCode: process.terminationStatus,
                ok: false,
                error: "Command timed out after \(Int(request.timeoutSeconds))s."
            )
            return
        }

        let ok = process.terminationStatus == 0
        finish(
            stdout: out,
            stderr: err,
            exitCode: process.terminationStatus,
            ok: ok,
            error: ok ? nil : "Command failed with exit code \(process.terminationStatus)."
        )
    }

    private func finishCancelled() {
        let out: String
        let err: String
        lock.lock()
        out = stdout.text
        err = stderr.text
        lock.unlock()
        finish(stdout: out, stderr: err, exitCode: nil, ok: false, error: "Command cancelled.")
    }

    private func finish(
        stdout: String,
        stderr: String,
        exitCode: Int32?,
        ok: Bool,
        error: String?
    ) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        let activeProcess = process
        let activeInput = standardInput
        process = nil
        standardInput = nil
        lock.unlock()

        try? activeInput?.fileHandleForWriting.close()
        if let activeProcess, activeProcess.isRunning {
            activeProcess.terminate()
        }

        continuation.yield(.finished(ToolResult(
            ok: ok,
            stdout: stdout,
            stderr: stderr,
            exitCode: exitCode,
            error: error
        )))
        continuation.finish()
    }
}
