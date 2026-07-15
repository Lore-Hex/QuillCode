import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum ProcessCompletion: Sendable, Equatable {
    case finished
    case timedOut
}

final class ProcessCompletionWaiter: @unchecked Sendable {
    private static let terminationGraceSeconds: TimeInterval = 2

    private let completion = DispatchSemaphore(value: 0)

    init(process: Process) {
        process.terminationHandler = { [completion] _ in
            completion.signal()
        }
    }

    func wait(for process: Process, timeoutSeconds: TimeInterval) -> ProcessCompletion {
        guard completion.wait(timeout: .now() + timeoutSeconds) == .timedOut else {
            return .finished
        }

        process.terminate()
        if completion.wait(timeout: .now() + Self.terminationGraceSeconds) == .timedOut,
           process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            completion.wait()
        }
        return .timedOut
    }
}

final class ProcessOutputCollector: @unchecked Sendable {
    private let stdoutPipe: Pipe
    private let stderrPipe: Pipe
    private let readers = DispatchGroup()
    private(set) var stdout = Data()
    private(set) var stderr = Data()

    init(stdout: Pipe, stderr: Pipe) {
        self.stdoutPipe = stdout
        self.stderrPipe = stderr
    }

    func start() {
        read(stdoutPipe) { [weak self] data in self?.stdout = data }
        read(stderrPipe) { [weak self] data in self?.stderr = data }
    }

    func wait() {
        readers.wait()
    }

    private func read(_ pipe: Pipe, assign: @escaping @Sendable (Data) -> Void) {
        readers.enter()
        DispatchQueue.global(qos: .utility).async { [readers] in
            assign(pipe.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }
    }
}
