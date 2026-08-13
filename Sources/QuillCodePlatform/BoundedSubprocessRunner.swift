import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct BoundedSubprocessRequest: Sendable {
    public var executableURL: URL
    public var arguments: [String]
    public var environment: [String: String]?
    public var currentDirectoryURL: URL?
    public var timeout: TimeInterval
    public var terminationGrace: TimeInterval
    public var standardOutputLimit: Int
    public var standardErrorLimit: Int

    public init(
        executableURL: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectoryURL: URL? = nil,
        timeout: TimeInterval,
        terminationGrace: TimeInterval = 2,
        standardOutputLimit: Int = 64 * 1_024,
        standardErrorLimit: Int = 64 * 1_024
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.currentDirectoryURL = currentDirectoryURL
        self.timeout = timeout
        self.terminationGrace = terminationGrace
        self.standardOutputLimit = standardOutputLimit
        self.standardErrorLimit = standardErrorLimit
    }
}

public struct BoundedSubprocessStreamResult: Sendable, Equatable {
    public var data: Data
    public var totalByteCount: Int64
    public var wasTruncated: Bool
    public var readCompleted: Bool

    public init(
        data: Data,
        totalByteCount: Int64,
        wasTruncated: Bool,
        readCompleted: Bool
    ) {
        self.data = data
        self.totalByteCount = totalByteCount
        self.wasTruncated = wasTruncated
        self.readCompleted = readCompleted
    }
}

public struct BoundedSubprocessResult: Sendable, Equatable {
    public var exitCode: Int32
    public var standardOutput: BoundedSubprocessStreamResult
    public var standardError: BoundedSubprocessStreamResult

    public init(
        exitCode: Int32,
        standardOutput: BoundedSubprocessStreamResult,
        standardError: BoundedSubprocessStreamResult
    ) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public enum BoundedSubprocessError: Error, LocalizedError, Sendable, Equatable {
    case invalidRequest
    case executableUnavailable
    case launchFailed
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .invalidRequest:
            "The subprocess request is invalid."
        case .executableUnavailable:
            "The subprocess executable is unavailable."
        case .launchFailed:
            "The subprocess could not be launched."
        case .timedOut:
            "The subprocess exceeded its time limit."
        }
    }
}

/// Runs direct child processes with bounded output residency and bounded lifetime.
public struct BoundedSubprocessRunner: Sendable {
    private static let queue = DispatchQueue(
        label: "co.lorehex.QuillCode.bounded-subprocess",
        qos: .userInitiated,
        attributes: .concurrent
    )

    public init() {}

    public func run(_ request: BoundedSubprocessRequest) async throws -> BoundedSubprocessResult {
        try Task.checkCancellation()
        let handle = BoundedSubprocessHandle()
        do {
            let result = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<BoundedSubprocessResult, any Error>) in
                    Self.queue.async {
                        do {
                            continuation.resume(returning: try runBlocking(request, handle: handle))
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            } onCancel: {
                handle.requestCancellation(grace: request.terminationGrace)
            }
            try Task.checkCancellation()
            return result
        } catch {
            try Task.checkCancellation()
            throw error
        }
    }

    public func runBlocking(
        _ request: BoundedSubprocessRequest
    ) throws -> BoundedSubprocessResult {
        try runBlocking(request, handle: BoundedSubprocessHandle())
    }

    private func runBlocking(
        _ request: BoundedSubprocessRequest,
        handle: BoundedSubprocessHandle
    ) throws -> BoundedSubprocessResult {
        try Self.validate(request)

        let process = Process()
        process.executableURL = request.executableURL
        process.arguments = request.arguments
        process.environment = request.environment
        process.currentDirectoryURL = request.currentDirectoryURL

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let terminationSignal = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in terminationSignal.signal() }

        let outputCapture = BoundedSubprocessPipeCapture(
            handle: outputPipe.fileHandleForReading,
            byteLimit: request.standardOutputLimit,
            retention: .prefix
        )
        let errorCapture = BoundedSubprocessPipeCapture(
            handle: errorPipe.fileHandleForReading,
            byteLimit: request.standardErrorLimit,
            retention: .suffix
        )
        outputCapture.start()
        errorCapture.start()
        handle.attach(process)

        do {
            try process.run()
        } catch {
            handle.detach()
            try? outputPipe.fileHandleForWriting.close()
            try? errorPipe.fileHandleForWriting.close()
            _ = outputCapture.finish(grace: request.terminationGrace)
            _ = errorCapture.finish(grace: request.terminationGrace)
            throw BoundedSubprocessError.launchFailed
        }
        try? outputPipe.fileHandleForWriting.close()
        try? errorPipe.fileHandleForWriting.close()
        handle.terminateIfCancellationRequested()

        if terminationSignal.wait(timeout: .now() + request.timeout) == .timedOut {
            handle.terminate()
            if terminationSignal.wait(timeout: .now() + request.terminationGrace) == .timedOut {
                handle.forceKill()
                _ = terminationSignal.wait(timeout: .now() + request.terminationGrace)
            }
            handle.detach()
            _ = outputCapture.finish(grace: request.terminationGrace)
            _ = errorCapture.finish(grace: request.terminationGrace)
            throw BoundedSubprocessError.timedOut
        }

        handle.detach()
        return BoundedSubprocessResult(
            exitCode: process.terminationStatus,
            standardOutput: outputCapture.finish(grace: request.terminationGrace),
            standardError: errorCapture.finish(grace: request.terminationGrace)
        )
    }

    private static func validate(_ request: BoundedSubprocessRequest) throws {
        guard request.executableURL.isFileURL,
              FileManager.default.isExecutableFile(atPath: request.executableURL.path)
        else {
            throw BoundedSubprocessError.executableUnavailable
        }
        guard request.timeout.isFinite,
              request.timeout >= 0,
              request.terminationGrace.isFinite,
              request.terminationGrace >= 0,
              request.standardOutputLimit >= 0,
              request.standardErrorLimit >= 0
        else {
            throw BoundedSubprocessError.invalidRequest
        }
    }
}

private final class BoundedSubprocessPipeCapture: @unchecked Sendable {
    enum Retention {
        case prefix
        case suffix
    }

    private static let chunkBytes = 64 * 1_024

    private let handle: FileHandle
    private let byteLimit: Int
    private let retention: Retention
    private let completion = DispatchGroup()
    private let lock = NSLock()
    private var wasForceClosed = false
    private var result = BoundedSubprocessStreamResult(
        data: Data(),
        totalByteCount: 0,
        wasTruncated: false,
        readCompleted: false
    )

    init(handle: FileHandle, byteLimit: Int, retention: Retention) {
        self.handle = handle
        self.byteLimit = byteLimit
        self.retention = retention
    }

    func start() {
        completion.enter()
        DispatchQueue.global(qos: .utility).async { [self] in
            drain()
            completion.leave()
        }
    }

    func finish(grace: TimeInterval) -> BoundedSubprocessStreamResult {
        if completion.wait(timeout: .now() + grace) == .timedOut {
            lock.lock()
            wasForceClosed = true
            lock.unlock()
            try? handle.close()
            _ = completion.wait(timeout: .now() + max(0.1, grace))
        }
        lock.lock()
        defer { lock.unlock() }
        return result
    }

    private func drain() {
        var data = Data()
        var totalByteCount: Int64 = 0
        var reachedEndOfFile = false
        do {
            while let chunk = try handle.read(upToCount: Self.chunkBytes), !chunk.isEmpty {
                totalByteCount = Self.saturatingSum(totalByteCount, Int64(chunk.count))
                retain(chunk, in: &data)
            }
            reachedEndOfFile = true
        } catch {
            reachedEndOfFile = false
        }

        lock.lock()
        result = BoundedSubprocessStreamResult(
            data: data,
            totalByteCount: totalByteCount,
            wasTruncated: totalByteCount > Int64(byteLimit),
            readCompleted: reachedEndOfFile && !wasForceClosed
        )
        lock.unlock()
    }

    private func retain(_ chunk: Data, in data: inout Data) {
        guard byteLimit > 0 else { return }
        switch retention {
        case .prefix:
            let available = byteLimit - data.count
            if available > 0 { data.append(chunk.prefix(available)) }
        case .suffix:
            if chunk.count >= byteLimit {
                data = Data(chunk.suffix(byteLimit))
                return
            }
            let overflow = data.count + chunk.count - byteLimit
            if overflow > 0 { data.removeFirst(overflow) }
            data.append(chunk)
        }
    }

    private static func saturatingSum(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int64.max : sum
    }
}

private final class BoundedSubprocessHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancellationRequested = false

    func attach(_ process: Process) {
        lock.lock()
        self.process = process
        lock.unlock()
    }

    func detach() {
        lock.lock()
        process = nil
        lock.unlock()
    }

    func requestCancellation(grace: TimeInterval) {
        lock.lock()
        cancellationRequested = true
        lock.unlock()
        terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + grace) { [self] in
            forceKill()
        }
    }

    func terminateIfCancellationRequested() {
        lock.lock()
        let shouldTerminate = cancellationRequested
        lock.unlock()
        if shouldTerminate { terminate() }
    }

    func terminate() {
        lock.lock()
        let process = process
        lock.unlock()
        if let process, process.isRunning { process.terminate() }
    }

    func forceKill() {
        lock.lock()
        let process = process
        lock.unlock()
        guard let process, process.isRunning else { return }
        Self.sendKill(to: process.processIdentifier)
    }

    private static func sendKill(to processIdentifier: Int32) {
        #if canImport(Darwin)
        _ = Darwin.kill(processIdentifier, SIGKILL)
        #elseif canImport(Glibc)
        _ = Glibc.kill(processIdentifier, SIGKILL)
        #endif
    }
}
