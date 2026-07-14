import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum ShellProcessCompletion: Sendable, Equatable {
    case finished
    case timedOut
}

final class ShellProcessCompletionWaiter: @unchecked Sendable {
    private static let terminationGraceSeconds: TimeInterval = 2

    private let completion = DispatchSemaphore(value: 0)

    init(process: Process) {
        process.terminationHandler = { [completion] _ in
            completion.signal()
        }
    }

    func wait(for process: Process, timeoutSeconds: TimeInterval) -> ShellProcessCompletion {
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
