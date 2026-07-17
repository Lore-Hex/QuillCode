import CQuillPlatform
import Foundation

public enum UnixDomainSocketError: Error, LocalizedError, Sendable, Equatable {
    case invalidPath(String)
    case listenerUnavailable(String)
    case acceptFailed
    case connectionFailed(String)
    case readFailed
    case writeFailed
    case closed
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidPath(let path):
            "Unix socket paths must be absolute file paths: \(path)"
        case .listenerUnavailable(let path):
            "Could not open the Unix socket listener at \(path)."
        case .acceptFailed:
            "The Unix socket listener could not accept a connection."
        case .connectionFailed(let path):
            "Could not connect to the Unix socket at \(path)."
        case .readFailed:
            "Could not read from the Unix socket."
        case .writeFailed:
            "Could not write to the Unix socket."
        case .closed:
            "The Unix socket is closed."
        case .cancelled:
            "The Unix socket operation was cancelled."
        }
    }
}

/// A private Unix-domain socket listener shared by the macOS and Linux app-server transports.
/// Low-level path ownership and descriptor operations live in `CQuillPlatform`; Swift owns
/// cancellation, lifetime, and the asynchronous connection API.
public final class UnixDomainSocketListener: @unchecked Sendable {
    public let socketURL: URL

    private static let pollMilliseconds: Int32 = 100
    private let descriptor: ManagedSocketDescriptor

    public init(socketURL: URL) throws {
        let path = try Self.validatedPath(socketURL)
        var device: UInt64 = 0
        var inode: UInt64 = 0
        let rawDescriptor = path.withCString {
            cquill_unix_open($0, &device, &inode)
        }
        guard rawDescriptor >= 0 else {
            throw UnixDomainSocketError.listenerUnavailable(path)
        }

        let boundDevice = device
        let boundInode = inode
        self.socketURL = URL(fileURLWithPath: path)
        self.descriptor = ManagedSocketDescriptor(rawDescriptor) {
            path.withCString {
                _ = cquill_unix_unlink_if_same($0, boundDevice, boundInode)
            }
        }
    }

    deinit {
        close()
    }

    public func accept() async throws -> UnixDomainSocketConnection {
        try await withTaskCancellationHandler {
            try await SocketBlockingIO.run { [descriptor] in
                let listener = try descriptor.acquire()
                defer { descriptor.release() }
                while true {
                    let accepted = cquill_loopback_accept(
                        listener,
                        Self.pollMilliseconds
                    )
                    if accepted == -2 {
                        if descriptor.isClosing { throw UnixDomainSocketError.cancelled }
                        continue
                    }
                    if accepted >= 0 {
                        return UnixDomainSocketConnection(descriptor: accepted)
                    }
                    if descriptor.isClosing { throw UnixDomainSocketError.cancelled }
                    throw UnixDomainSocketError.acceptFailed
                }
            }
        } onCancel: {
            descriptor.close()
        }
    }

    public func close() {
        descriptor.close()
    }

    private static func validatedPath(_ url: URL) throws -> String {
        guard url.isFileURL else {
            throw UnixDomainSocketError.invalidPath(url.absoluteString)
        }
        let path = url.standardizedFileURL.path
        guard NSString(string: path).isAbsolutePath,
              !path.contains("\0")
        else {
            throw UnixDomainSocketError.invalidPath(url.absoluteString)
        }
        return path
    }
}

/// A full-duplex Unix-domain socket connection. Reads and writes may proceed concurrently while
/// descriptor lifetime remains race-safe: close first interrupts active operations, then releases
/// the descriptor only after every operation has returned.
public protocol SocketByteConnection: AnyObject, Sendable {
    func receive(maxBytes: Int) async throws -> Data?
    func send(_ data: Data) async throws
    func close()
}

public extension SocketByteConnection {
    func receive() async throws -> Data? {
        try await receive(maxBytes: 64 * 1_024)
    }
}

public final class UnixDomainSocketConnection: SocketByteConnection, @unchecked Sendable {
    private static let pollMilliseconds: Int32 = 100
    private let descriptor: ManagedSocketDescriptor

    fileprivate init(descriptor: Int32) {
        self.descriptor = ManagedSocketDescriptor(descriptor)
    }

    public static func connect(to socketURL: URL) throws -> UnixDomainSocketConnection {
        guard socketURL.isFileURL else {
            throw UnixDomainSocketError.invalidPath(socketURL.absoluteString)
        }
        let path = socketURL.standardizedFileURL.path
        guard NSString(string: path).isAbsolutePath,
              !path.contains("\0")
        else {
            throw UnixDomainSocketError.invalidPath(socketURL.absoluteString)
        }
        let rawDescriptor = path.withCString(cquill_unix_connect)
        guard rawDescriptor >= 0 else {
            throw UnixDomainSocketError.connectionFailed(path)
        }
        return UnixDomainSocketConnection(descriptor: rawDescriptor)
    }

    deinit {
        close()
    }

    public func receive(maxBytes: Int = 64 * 1_024) async throws -> Data? {
        precondition(maxBytes > 0)
        return try await withTaskCancellationHandler {
            try await SocketBlockingIO.run { [descriptor] in
                let socket = try descriptor.acquire()
                defer { descriptor.release() }
                var bytes = [UInt8](repeating: 0, count: maxBytes)
                while true {
                    let count = bytes.withUnsafeMutableBytes { buffer in
                        cquill_socket_receive(
                            socket,
                            buffer.baseAddress,
                            buffer.count,
                            Self.pollMilliseconds
                        )
                    }
                    if count == -2 {
                        if descriptor.isClosing { throw UnixDomainSocketError.cancelled }
                        continue
                    }
                    if count > 0 { return Data(bytes.prefix(Int(count))) }
                    if count == 0 { return nil }
                    if descriptor.isClosing { throw UnixDomainSocketError.cancelled }
                    throw UnixDomainSocketError.readFailed
                }
            }
        } onCancel: {
            descriptor.close()
        }
    }

    public func send(_ data: Data) async throws {
        guard !data.isEmpty else { return }
        try await withTaskCancellationHandler {
            try await SocketBlockingIO.run { [descriptor] in
                let socket = try descriptor.acquire()
                defer { descriptor.release() }
                let result = data.withUnsafeBytes { bytes in
                    cquill_socket_send_all(socket, bytes.baseAddress, bytes.count)
                }
                guard result == 0 else {
                    if descriptor.isClosing { throw UnixDomainSocketError.cancelled }
                    throw UnixDomainSocketError.writeFailed
                }
            }
        } onCancel: {
            descriptor.close()
        }
    }

    public func close() {
        descriptor.close()
    }
}

enum SocketBlockingIO {
    private static let queue = DispatchQueue(
        label: "com.lorehex.QuillCode.unix-domain-socket",
        qos: .userInitiated,
        attributes: .concurrent
    )

    static func run<Value: Sendable>(
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try operation())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

final class ManagedSocketDescriptor: @unchecked Sendable {
    private struct State {
        var descriptor: Int32?
        var activeOperations = 0
        var isClosing = false
        var didRunCloseHandler = false
    }

    private let lock = NSLock()
    private var state: State
    private let closeHandler: @Sendable () -> Void

    init(_ descriptor: Int32, closeHandler: @escaping @Sendable () -> Void = {}) {
        precondition(descriptor >= 0)
        self.state = State(descriptor: descriptor)
        self.closeHandler = closeHandler
    }

    deinit {
        close()
    }

    var isClosing: Bool {
        lock.withLock { state.isClosing }
    }

    func acquire() throws -> Int32 {
        try lock.withLock {
            guard !state.isClosing, let descriptor = state.descriptor else {
                throw UnixDomainSocketError.closed
            }
            state.activeOperations += 1
            return descriptor
        }
    }

    func release() {
        let cleanup = lock.withLock { () -> (Int32?, Bool) in
            precondition(state.activeOperations > 0)
            state.activeOperations -= 1
            return cleanupIfReady()
        }
        performCleanup(cleanup)
    }

    func close() {
        let result = lock.withLock { () -> (shutdown: Int32?, cleanup: (Int32?, Bool)) in
            guard !state.isClosing else { return (nil, (nil, false)) }
            state.isClosing = true
            return (state.descriptor, cleanupIfReady())
        }
        if let descriptor = result.shutdown {
            _ = cquill_socket_shutdown(descriptor)
        }
        performCleanup(result.cleanup)
    }

    private func cleanupIfReady() -> (Int32?, Bool) {
        guard state.isClosing, state.activeOperations == 0 else { return (nil, false) }
        let descriptor = state.descriptor
        state.descriptor = nil
        let shouldRunHandler = !state.didRunCloseHandler
        state.didRunCloseHandler = true
        return (descriptor, shouldRunHandler)
    }

    private func performCleanup(_ cleanup: (Int32?, Bool)) {
        if let descriptor = cleanup.0 {
            _ = cquill_descriptor_close(descriptor)
        }
        if cleanup.1 { closeHandler() }
    }
}

private extension NSLock {
    func withLock<Result>(_ operation: () throws -> Result) rethrows -> Result {
        lock()
        defer { unlock() }
        return try operation()
    }
}
