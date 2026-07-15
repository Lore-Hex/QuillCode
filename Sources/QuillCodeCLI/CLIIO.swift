import CQuillPTY
import Foundation

public protocol CLIInputReading: Sendable {
    var isTerminal: Bool { get }
    func read(maxBytes: Int) throws -> Data
    func lines(maxLineBytes: Int) -> AsyncThrowingStream<Data, Error>
}

public final class StandardCLIInput: CLIInputReading, @unchecked Sendable {
    private let handle: FileHandle

    public init(handle: FileHandle = .standardInput) {
        self.handle = handle
    }

    public var isTerminal: Bool {
        cquill_fd_isatty(Int32(handle.fileDescriptor)) == 1
    }

    public func read(maxBytes: Int) throws -> Data {
        var data = Data()
        let chunkSize = min(64 * 1_024, maxBytes + 1)
        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { return data }
            data.append(chunk)
            if data.count > maxBytes {
                throw CLIError.stdinTooLarge(limit: maxBytes)
            }
        }
    }

    public func lines(maxLineBytes: Int) -> AsyncThrowingStream<Data, Error> {
        let descriptor = Int32(handle.fileDescriptor)
        return AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    var framer = CLIInputLineFramer(maxLineBytes: maxLineBytes)
                    var bytes = [UInt8](repeating: 0, count: 64 * 1_024)
                    while !Task.isCancelled {
                        let readiness = cquill_fd_wait_readable(descriptor, 100)
                        guard readiness >= 0 else { throw CLIInputStreamError.readFailed }
                        guard readiness == 1 else { continue }
                        let count = bytes.withUnsafeMutableBytes { buffer in
                            cquill_fd_read(descriptor, buffer.baseAddress, buffer.count)
                        }
                        guard count >= 0 else { throw CLIInputStreamError.readFailed }
                        if count == 0 { break }
                        let chunk = Data(bytes.prefix(Int(count)))
                        for line in try framer.append(chunk) {
                            continuation.yield(line)
                        }
                    }
                    if let finalLine = try framer.finish() {
                        continuation.yield(finalLine)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private enum CLIInputStreamError: LocalizedError {
    case readFailed

    var errorDescription: String? {
        "Could not read the app-server input stream."
    }
}

public struct BufferedCLIInput: CLIInputReading {
    public var isTerminal: Bool
    public var data: Data

    public init(text: String = "", isTerminal: Bool = false) {
        self.isTerminal = isTerminal
        self.data = Data(text.utf8)
    }

    public init(data: Data, isTerminal: Bool = false) {
        self.isTerminal = isTerminal
        self.data = data
    }

    public func read(maxBytes: Int) throws -> Data {
        guard data.count <= maxBytes else { throw CLIError.stdinTooLarge(limit: maxBytes) }
        return data
    }

    public func lines(maxLineBytes: Int) -> AsyncThrowingStream<Data, Error> {
        let data = data
        return AsyncThrowingStream { continuation in
            do {
                var framer = CLIInputLineFramer(maxLineBytes: maxLineBytes)
                for line in try framer.append(data) {
                    continuation.yield(line)
                }
                if let finalLine = try framer.finish() {
                    continuation.yield(finalLine)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}

struct CLIInputLineFramer: Sendable {
    private let maxLineBytes: Int
    private var buffer = Data()

    init(maxLineBytes: Int) {
        self.maxLineBytes = max(1, maxLineBytes)
    }

    mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var lines: [Data] = []
        var lineStart = buffer.startIndex
        while let newline = buffer[lineStart...].firstIndex(of: 0x0A) {
            var line = Data(buffer[lineStart..<newline])
            if line.last == 0x0D { line.removeLast() }
            try validate(line)
            lines.append(line)
            lineStart = buffer.index(after: newline)
        }
        if lineStart != buffer.startIndex {
            buffer.removeSubrange(buffer.startIndex..<lineStart)
        }
        try validate(buffer)
        return lines
    }

    mutating func finish() throws -> Data? {
        guard !buffer.isEmpty else { return nil }
        var line = buffer
        buffer.removeAll(keepingCapacity: false)
        if line.last == 0x0D { line.removeLast() }
        try validate(line)
        return line
    }

    private func validate(_ line: Data) throws {
        guard line.count <= maxLineBytes else {
            throw CLIError.appServerMessageTooLarge(limit: maxLineBytes)
        }
    }
}

public protocol CLIOutputWriting: Sendable {
    func writeStandardOutput(_ text: String) async
    func writeStandardError(_ text: String) async
}

public actor FileHandleCLIOutput: CLIOutputWriting {
    private let standardOutput: FileHandle
    private let standardError: FileHandle

    public init(
        standardOutput: FileHandle = .standardOutput,
        standardError: FileHandle = .standardError
    ) {
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public func writeStandardOutput(_ text: String) {
        write(text, to: standardOutput)
    }

    public func writeStandardError(_ text: String) {
        write(text, to: standardError)
    }

    private func write(_ text: String, to handle: FileHandle) {
        guard let data = text.data(using: .utf8) else { return }
        handle.write(data)
    }
}

public actor BufferedCLIOutput: CLIOutputWriting {
    public private(set) var standardOutput = ""
    public private(set) var standardError = ""

    public init() {}

    public func writeStandardOutput(_ text: String) {
        standardOutput += text
    }

    public func writeStandardError(_ text: String) {
        standardError += text
    }

    public func snapshot() -> (standardOutput: String, standardError: String) {
        (standardOutput, standardError)
    }
}

extension CLIOutputWriting {
    func writeStandardOutputLine(_ text: String) async {
        await writeStandardOutput(text + "\n")
    }

    func writeStandardErrorLine(_ text: String) async {
        await writeStandardError(text + "\n")
    }
}
