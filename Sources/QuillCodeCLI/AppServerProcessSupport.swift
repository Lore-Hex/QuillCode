import CQuillPTY
import Foundation

enum AppServerProcessSupport {
    static func resolveExecutable(
        _ program: String,
        cwd: URL,
        environment: [String: String]
    ) throws -> URL {
        let fileManager = FileManager.default
        if program.contains("/") {
            let candidate = program.hasPrefix("/")
                ? URL(fileURLWithPath: program)
                : cwd.appendingPathComponent(program)
            let resolved = candidate.standardizedFileURL
            guard fileManager.isExecutableFile(atPath: resolved.path) else {
                throw spawnFailure(program)
            }
            return resolved
        }

        let path = environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        for directory in path.split(separator: ":", omittingEmptySubsequences: false) {
            let root = directory.isEmpty
                ? cwd
                : URL(fileURLWithPath: String(directory), isDirectory: true)
            let candidate = root.appendingPathComponent(program).standardizedFileURL
            if fileManager.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        throw spawnFailure(program)
    }

    static func write(_ data: Data, to descriptor: Int32) throws {
        var offset = 0
        while offset < data.count {
            let count = data.withUnsafeBytes { bytes -> Int in
                guard let baseAddress = bytes.baseAddress else { return 0 }
                return cquill_fd_write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    data.count - offset
                )
            }
            guard count > 0 else { throw stdinClosedError }
            offset += count
        }
    }

    static func dispatchMilliseconds(_ value: Int64) -> Int {
        Int(min(value, Int64(Int.max)))
    }

    static func noLongerRunningError(_ handle: String) -> AppServerRPCError {
        .invalidRequest("process \(handle.debugDescription) is no longer running")
    }

    static let stdinClosedError = AppServerRPCError.invalidRequest("stdin is already closed")

    private static func spawnFailure(_ program: String) -> AppServerRPCError {
        .internalError("failed to spawn process: executable not found: \(program)")
    }
}

struct AppServerProcessOutputCapture {
    struct Accepted {
        var data: Data
        var capReached: Bool
    }

    var limit: Int?
    var buffers: Bool
    var data = Data()
    var observedBytes = 0
    var capReached = false

    mutating func accept(_ incoming: Data) -> Accepted? {
        guard !capReached else { return nil }
        let accepted: Data
        if let limit {
            let count = min(max(0, limit - observedBytes), incoming.count)
            accepted = incoming.prefix(count)
            observedBytes += count
            capReached = observedBytes == limit
        } else {
            accepted = incoming
            observedBytes += incoming.count
        }
        if buffers { data.append(accepted) }
        return Accepted(data: accepted, capReached: capReached)
    }
}

extension NSLock {
    func appServerWithLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
