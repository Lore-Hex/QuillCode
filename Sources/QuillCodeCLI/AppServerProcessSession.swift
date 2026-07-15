import CQuillPTY
import Foundation

final class AppServerProcessSession: @unchecked Sendable {
    let events: AsyncStream<AppServerProcessEvent>

    private static let readChunkBytes = 64 * 1_024
    private static let outputDrainMilliseconds = 500
    private static let terminationGraceMilliseconds = 1_000

    private let request: AppServerProcessSpawnRequest
    private let continuation: AsyncStream<AppServerProcessEvent>.Continuation
    private let lock = NSLock()
    private let readers = DispatchGroup()
    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputHandles: [FileHandle] = []
    private var masterFileDescriptor: Int32 = -1
    private var stdinClosed = false
    private var finished = false
    private var timedOut = false
    private var stdoutCapture: AppServerProcessOutputCapture
    private var stderrCapture: AppServerProcessOutputCapture

    init(request: AppServerProcessSpawnRequest) {
        self.request = request
        stdoutCapture = AppServerProcessOutputCapture(
            limit: request.outputBytesCap,
            buffers: !request.streamsOutput
        )
        stderrCapture = AppServerProcessOutputCapture(
            limit: request.outputBytesCap,
            buffers: !request.streamsOutput
        )
        let pair = AsyncStream<AppServerProcessEvent>.makeStream()
        events = pair.stream
        continuation = pair.continuation
    }

    func start() throws {
        let executable = try AppServerProcessSupport.resolveExecutable(
            request.command[0],
            cwd: request.cwd,
            environment: request.environment
        )
        let process = Process()
        process.executableURL = executable
        process.arguments = Array(request.command.dropFirst())
        process.currentDirectoryURL = request.cwd
        process.environment = request.environment

        if request.usesPTY {
            try configurePTY(for: process)
        } else {
            configurePipes(for: process)
        }

        lock.appServerWithLock {
            self.process = process
        }
        do {
            try process.run()
        } catch {
            cleanUpFailedStart()
            throw AppServerRPCError.internalError("failed to spawn process: \(error.localizedDescription)")
        }

        closeParentOnlyDescriptorsAfterStart()
        startReaders()
        scheduleTimeoutIfNeeded()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.waitForExit()
        }
    }

    func writeStdin(_ data: Data, closeStdin: Bool) throws {
        if request.usesPTY {
            try writePTYStdin(data, closeStdin: closeStdin)
            return
        }
        let handle: FileHandle = try lock.appServerWithLock {
            guard request.streamsStdin else {
                throw AppServerRPCError.invalidRequest("stdin streaming is not enabled for this process")
            }
            guard !finished else {
                throw AppServerProcessSupport.noLongerRunningError(request.processHandle)
            }
            guard !stdinClosed, let inputHandle else {
                throw AppServerRPCError.invalidRequest("stdin is already closed")
            }
            return inputHandle
        }

        do {
            if !data.isEmpty { try handle.write(contentsOf: data) }
            if closeStdin {
                try handle.close()
                lock.appServerWithLock {
                    stdinClosed = true
                    inputHandle = nil
                }
            }
        } catch {
            throw AppServerRPCError.invalidRequest("stdin is already closed")
        }
    }

    private func writePTYStdin(_ data: Data, closeStdin: Bool) throws {
        let descriptor = try lock.appServerWithLock { () throws -> Int32 in
            guard request.streamsStdin else {
                throw AppServerRPCError.invalidRequest("stdin streaming is not enabled for this process")
            }
            guard !finished, masterFileDescriptor >= 0 else {
                throw AppServerProcessSupport.noLongerRunningError(request.processHandle)
            }
            guard !stdinClosed else {
                throw AppServerRPCError.invalidRequest("stdin is already closed")
            }
            return masterFileDescriptor
        }
        do {
            try AppServerProcessSupport.write(data, to: descriptor)
            if closeStdin {
                try AppServerProcessSupport.write(Data([0x04]), to: descriptor)
                lock.appServerWithLock { stdinClosed = true }
            }
        } catch let error as AppServerRPCError {
            throw error
        } catch {
            throw AppServerRPCError.invalidRequest("stdin is already closed")
        }
    }

    func resizePTY(to size: AppServerProcessTerminalSize) throws {
        try lock.appServerWithLock {
            guard request.usesPTY else {
                throw AppServerRPCError.invalidRequest("failed to resize PTY: process is not PTY-backed")
            }
            guard !finished, masterFileDescriptor >= 0 else {
                throw AppServerProcessSupport.noLongerRunningError(request.processHandle)
            }
            guard cquill_pty_set_winsize(masterFileDescriptor, size.rows, size.columns) == 0 else {
                throw AppServerRPCError.invalidRequest("failed to resize PTY")
            }
        }
    }

    func kill() throws {
        let activeProcess = try lock.appServerWithLock { () throws -> Process in
            guard !finished, let activeProcess = self.process, activeProcess.isRunning else {
                throw AppServerProcessSupport.noLongerRunningError(request.processHandle)
            }
            return activeProcess
        }
        terminate(activeProcess)
    }

    func terminateForDisconnect() {
        let activeProcess = lock.appServerWithLock { () -> Process? in
            guard !finished else { return nil }
            return self.process
        }
        if let activeProcess { terminate(activeProcess) }
    }

    private func configurePTY(for process: Process) throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        var slavePath = [CChar](repeating: 0, count: 1_024)
        guard cquill_pty_open(&master, &slave, &slavePath, slavePath.count) == 0 else {
            throw AppServerRPCError.internalError("failed to allocate a pseudo-terminal")
        }
        if let size = request.terminalSize,
           cquill_pty_set_winsize(master, size.rows, size.columns) != 0 {
            FileHandle(fileDescriptor: master, closeOnDealloc: true).closeFile()
            FileHandle(fileDescriptor: slave, closeOnDealloc: true).closeFile()
            throw AppServerRPCError.internalError("failed to set the initial PTY size")
        }

        let masterHandle = FileHandle(fileDescriptor: master, closeOnDealloc: true)
        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: true)
        process.standardInput = slaveHandle
        process.standardOutput = slaveHandle
        process.standardError = slaveHandle
        lock.appServerWithLock {
            inputHandle = masterHandle
            outputHandles = [masterHandle, slaveHandle]
            masterFileDescriptor = master
        }
    }

    private func configurePipes(for process: Process) {
        let standardOutput = Pipe()
        let standardError = Pipe()
        let standardInput = Pipe()
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError
        lock.appServerWithLock {
            inputHandle = standardInput.fileHandleForWriting
            outputHandles = [
                standardOutput.fileHandleForReading,
                standardError.fileHandleForReading
            ]
        }
    }

    private func closeParentOnlyDescriptorsAfterStart() {
        if request.usesPTY {
            let slave = lock.appServerWithLock {
                outputHandles.count > 1 ? outputHandles.removeLast() : nil
            }
            try? slave?.close()
        } else if !request.streamsStdin {
            let input = lock.appServerWithLock { () -> FileHandle? in
                stdinClosed = true
                defer { inputHandle = nil }
                return inputHandle
            }
            try? input?.close()
        }
    }

    private func startReaders() {
        let handles = lock.appServerWithLock { outputHandles }
        guard let stdout = handles.first else { return }
        if request.usesPTY {
            let descriptor = lock.appServerWithLock { masterFileDescriptor }
            startPTYReader(descriptor)
        } else {
            startReader(stdout, stream: .stdout)
            if handles.count > 1 { startReader(handles[1], stream: .stderr) }
        }
    }

    private func startPTYReader(_ descriptor: Int32) {
        readers.enter()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            defer { self?.readers.leave() }
            var buffer = [UInt8](repeating: 0, count: Self.readChunkBytes)
            while let self {
                let count = buffer.withUnsafeMutableBytes { bytes in
                    cquill_fd_read(descriptor, bytes.baseAddress, bytes.count)
                }
                guard count > 0 else { return }
                self.capture(Data(buffer.prefix(count)), stream: .stdout)
            }
        }
    }

    private func startReader(_ handle: FileHandle, stream: AppServerProcessOutputStream) {
        readers.enter()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            defer { self?.readers.leave() }
            while let self {
                let data: Data
                do {
                    data = try handle.read(upToCount: Self.readChunkBytes) ?? Data()
                } catch {
                    return
                }
                guard !data.isEmpty else { return }
                self.capture(data, stream: stream)
            }
        }
    }

    private func capture(_ data: Data, stream: AppServerProcessOutputStream) {
        let accepted: AppServerProcessOutputCapture.Accepted? = lock.appServerWithLock {
            switch stream {
            case .stdout: return stdoutCapture.accept(data)
            case .stderr: return stderrCapture.accept(data)
            }
        }
        guard request.streamsOutput, let accepted else { return }
        continuation.yield(.output(
            stream: stream,
            data: accepted.data,
            capReached: accepted.capReached
        ))
    }

    private func scheduleTimeoutIfNeeded() {
        guard let milliseconds = request.timeoutMilliseconds else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + .milliseconds(
                AppServerProcessSupport.dispatchMilliseconds(milliseconds)
            )
        ) { [weak self] in
            self?.timeOut()
        }
    }

    private func timeOut() {
        let activeProcess = lock.appServerWithLock { () -> Process? in
            guard !finished, !timedOut else { return nil }
            timedOut = true
            return self.process
        }
        if let activeProcess { terminate(activeProcess) }
    }

    private func terminate(_ process: Process) {
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + .milliseconds(Self.terminationGraceMilliseconds)
        ) {
            guard process.isRunning else { return }
            _ = cquill_process_force_kill(process.processIdentifier)
        }
    }

    private func waitForExit() {
        guard let process = lock.appServerWithLock({ process }) else { return }
        process.waitUntilExit()
        if readers.wait(timeout: .now() + .milliseconds(Self.outputDrainMilliseconds)) == .timedOut {
            let handles = lock.appServerWithLock { outputHandles }
            for handle in handles { try? handle.close() }
            readers.wait()
        }

        let result = lock.appServerWithLock { () -> AppServerProcessExit? in
            guard !finished else { return nil }
            finished = true
            let exitCode: Int32
            if timedOut {
                exitCode = 124
            } else if process.terminationReason == .uncaughtSignal {
                exitCode = 128 + process.terminationStatus
            } else {
                exitCode = process.terminationStatus
            }
            let result = AppServerProcessExit(
                exitCode: exitCode,
                stdout: stdoutCapture.data,
                stdoutCapReached: stdoutCapture.capReached,
                stderr: stderrCapture.data,
                stderrCapReached: stderrCapture.capReached
            )
            self.process = nil
            inputHandle = nil
            outputHandles = []
            masterFileDescriptor = -1
            return result
        }
        guard let result else { return }
        continuation.yield(.exited(result))
        continuation.finish()
    }

    private func cleanUpFailedStart() {
        let handles = lock.appServerWithLock { () -> [FileHandle] in
            defer {
                process = nil
                inputHandle = nil
                outputHandles = []
                masterFileDescriptor = -1
                finished = true
            }
            return Array(Set(outputHandles + [inputHandle].compactMap { $0 }))
        }
        for handle in handles { try? handle.close() }
        continuation.finish()
    }

}
