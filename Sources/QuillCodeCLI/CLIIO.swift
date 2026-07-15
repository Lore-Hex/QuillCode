import CQuillPTY
import Foundation

public protocol CLIInputReading: Sendable {
    var isTerminal: Bool { get }
    func read(maxBytes: Int) throws -> Data
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
