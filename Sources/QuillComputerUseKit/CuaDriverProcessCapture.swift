import Foundation

#if canImport(Glibc) || canImport(Darwin)
struct CuaDriverBoundedPipeCaptureResult: Sendable {
    var data = Data()
    var totalByteCount = 0
    var wasTruncated = false
    var readCompleted = false
}

/// Drains one subprocess pipe without allowing retained output to follow producer volume.
final class CuaDriverBoundedPipeCapture: @unchecked Sendable {
    enum Retention {
        case prefix
        case suffix
    }

    private static let readChunkBytes = 64 * 1_024

    private let handle: FileHandle
    private let byteLimit: Int
    private let retention: Retention
    private let completion = DispatchGroup()
    private let lock = NSLock()
    private var result = CuaDriverBoundedPipeCaptureResult()

    init(handle: FileHandle, byteLimit: Int, retention: Retention) {
        self.handle = handle
        self.byteLimit = max(0, byteLimit)
        self.retention = retention
    }

    func start() {
        completion.enter()
        DispatchQueue.global(qos: .utility).async { [self] in
            drain()
            completion.leave()
        }
    }

    func finishAfterProcessExit(graceSeconds: TimeInterval) -> CuaDriverBoundedPipeCaptureResult {
        if completion.wait(timeout: .now() + max(0, graceSeconds)) == .timedOut {
            try? handle.close()
            _ = completion.wait(timeout: .now() + max(0.1, graceSeconds))
        }
        lock.lock()
        defer { lock.unlock() }
        return result
    }

    private func drain() {
        var captured = Data()
        var totalByteCount = 0
        var wasTruncated = false
        var readCompleted = false

        do {
            while let chunk = try handle.read(upToCount: Self.readChunkBytes), !chunk.isEmpty {
                totalByteCount = Self.saturatingSum(totalByteCount, chunk.count)
                if totalByteCount > byteLimit {
                    wasTruncated = true
                }
                retain(chunk, in: &captured)
            }
            readCompleted = true
        } catch {
            readCompleted = false
        }

        lock.lock()
        result = CuaDriverBoundedPipeCaptureResult(
            data: captured,
            totalByteCount: totalByteCount,
            wasTruncated: wasTruncated,
            readCompleted: readCompleted
        )
        lock.unlock()
    }

    private func retain(_ chunk: Data, in captured: inout Data) {
        guard byteLimit > 0 else { return }
        switch retention {
        case .prefix:
            let available = byteLimit - captured.count
            guard available > 0 else { return }
            captured.append(chunk.prefix(available))
        case .suffix:
            if chunk.count >= byteLimit {
                captured = Data(chunk.suffix(byteLimit))
                return
            }
            let overflow = captured.count + chunk.count - byteLimit
            if overflow > 0 {
                captured.removeFirst(overflow)
            }
            captured.append(chunk)
        }
    }

    private static func saturatingSum(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int.max : sum
    }
}

/// Synchronizes task cancellation and timeout teardown with Foundation's non-Sendable `Process`.
final class CuaDriverProcessHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancellationRequested = false

    func attach(_ process: Process) {
        lock.lock()
        self.process = process
        lock.unlock()
    }

    func terminateIfCancellationRequested() {
        lock.lock()
        let shouldTerminate = cancellationRequested
        lock.unlock()
        if shouldTerminate { terminate() }
    }

    func requestCancellation(terminationGraceSeconds: TimeInterval) {
        lock.lock()
        cancellationRequested = true
        lock.unlock()
        terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + max(0, terminationGraceSeconds)
        ) { [self] in
            kill()
        }
    }

    func terminate() {
        lock.lock()
        let process = self.process
        lock.unlock()
        if let process, process.isRunning { process.terminate() }
    }

    func kill() {
        lock.lock()
        let process = self.process
        lock.unlock()
        if let process, process.isRunning {
            Foundation.kill(process.processIdentifier, SIGKILL)
        }
    }
}
#endif
