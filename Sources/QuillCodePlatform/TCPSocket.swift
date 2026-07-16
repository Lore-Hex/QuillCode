import CQuillPlatform
import Foundation

public enum TCPSocketError: Error, LocalizedError, Sendable, Equatable {
    case invalidHost(String)
    case listenerUnavailable(host: String, port: UInt16)
    case acceptFailed
    case connectionFailed(host: String, port: UInt16)
    case readFailed
    case writeFailed
    case closed
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidHost(let host):
            "TCP hosts must be numeric IPv4 or IPv6 addresses: \(host)"
        case .listenerUnavailable(let host, let port):
            "Could not open the TCP listener at \(host):\(port)."
        case .acceptFailed:
            "The TCP listener could not accept a connection."
        case .connectionFailed(let host, let port):
            "Could not connect to \(host):\(port)."
        case .readFailed:
            "Could not read from the TCP socket."
        case .writeFailed:
            "Could not write to the TCP socket."
        case .closed:
            "The TCP socket is closed."
        case .cancelled:
            "The TCP socket operation was cancelled."
        }
    }
}

public final class TCPSocketListener: @unchecked Sendable {
    public let host: String
    public let port: UInt16

    private static let pollMilliseconds: Int32 = 100
    private let descriptor: ManagedSocketDescriptor

    public init(host: String, port: UInt16) throws {
        guard Self.isNumericHost(host) else { throw TCPSocketError.invalidHost(host) }
        var boundPort: UInt16 = 0
        let rawDescriptor = host.withCString {
            cquill_tcp_open($0, port, &boundPort)
        }
        guard rawDescriptor >= 0 else {
            throw TCPSocketError.listenerUnavailable(host: host, port: port)
        }
        self.host = host
        self.port = boundPort
        self.descriptor = ManagedSocketDescriptor(rawDescriptor)
    }

    deinit { close() }

    public func accept() async throws -> TCPSocketConnection {
        try await withTaskCancellationHandler {
            try await SocketBlockingIO.run { [descriptor] in
                let listener: Int32
                do {
                    listener = try descriptor.acquire()
                } catch {
                    throw TCPSocketError.closed
                }
                defer { descriptor.release() }
                while true {
                    let accepted = cquill_loopback_accept(listener, Self.pollMilliseconds)
                    if accepted == -2 {
                        if descriptor.isClosing { throw TCPSocketError.cancelled }
                        continue
                    }
                    if accepted >= 0 { return TCPSocketConnection(descriptor: accepted) }
                    if descriptor.isClosing { throw TCPSocketError.cancelled }
                    throw TCPSocketError.acceptFailed
                }
            }
        } onCancel: {
            descriptor.close()
        }
    }

    public func close() { descriptor.close() }

    private static func isNumericHost(_ host: String) -> Bool {
        guard !host.isEmpty, !host.contains("\0") else { return false }
        return host.allSatisfy { character in
            character.isHexDigit || character == "." || character == ":"
        }
    }
}

public final class TCPSocketConnection: SocketByteConnection, @unchecked Sendable {
    private static let pollMilliseconds: Int32 = 100
    private let descriptor: ManagedSocketDescriptor

    fileprivate init(descriptor: Int32) {
        self.descriptor = ManagedSocketDescriptor(descriptor)
    }

    public static func connect(host: String, port: UInt16) throws -> TCPSocketConnection {
        let rawDescriptor = host.withCString { cquill_tcp_connect($0, port) }
        guard rawDescriptor >= 0 else {
            throw TCPSocketError.connectionFailed(host: host, port: port)
        }
        return TCPSocketConnection(descriptor: rawDescriptor)
    }

    deinit { close() }

    public func receive(maxBytes: Int = 64 * 1_024) async throws -> Data? {
        precondition(maxBytes > 0)
        return try await withTaskCancellationHandler {
            try await SocketBlockingIO.run { [descriptor] in
                let socket: Int32
                do {
                    socket = try descriptor.acquire()
                } catch {
                    throw TCPSocketError.closed
                }
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
                        if descriptor.isClosing { throw TCPSocketError.cancelled }
                        continue
                    }
                    if count > 0 { return Data(bytes.prefix(Int(count))) }
                    if count == 0 { return nil }
                    if descriptor.isClosing { throw TCPSocketError.cancelled }
                    throw TCPSocketError.readFailed
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
                let socket: Int32
                do {
                    socket = try descriptor.acquire()
                } catch {
                    throw TCPSocketError.closed
                }
                defer { descriptor.release() }
                let result = data.withUnsafeBytes { bytes in
                    cquill_socket_send_all(socket, bytes.baseAddress, bytes.count)
                }
                guard result == 0 else {
                    if descriptor.isClosing { throw TCPSocketError.cancelled }
                    throw TCPSocketError.writeFailed
                }
            }
        } onCancel: {
            descriptor.close()
        }
    }

    public func close() { descriptor.close() }
}
