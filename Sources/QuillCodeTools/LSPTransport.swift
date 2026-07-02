import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// The byte-level channel to a language server. Behind this protocol sits either a real subprocess's
/// stdin/stdout (`LSPStdioTransport`) or a canned in-memory scripted server in tests — so the entire
/// `LSPClient` runs deterministically without a real sourcekit-lsp.
///
/// Implementations must be `Sendable`; the client serializes access with its own lock, so a
/// transport need not be internally concurrent, only safe to hand across the boundary.
public protocol LSPTransport: Sendable {
    /// Writes one already-framed message (header + body) to the server. Throws if the write fails
    /// (e.g. the server's stdin is closed because it crashed).
    func send(_ data: Data) throws

    /// Blocks for up to `timeout` seconds for more bytes from the server, returning whatever arrived
    /// (possibly empty on a spurious wakeup) or `nil` on end-of-stream (server exited). Throws only on
    /// an unexpected OS error, never on a plain timeout — a timeout returns empty so the caller can
    /// re-check its own deadline.
    func receive(timeout: TimeInterval) throws -> Data?

    /// Releases the underlying channel (closes the pipe file descriptors for a stdio transport).
    /// Idempotent. Closing stdin signals EOF to the child so it can exit; not closing leaks fds and
    /// can wedge the child. In-memory test transports may no-op.
    func close()
}

public extension LSPTransport {
    /// Default no-op so in-memory/scripted transports need not implement it.
    func close() {}
}

/// A transport over a subprocess's stdin (write) and stdout (read) file handles. Reads use `poll(2)`
/// with a bounded timeout so a silent server never wedges the calling thread — the exact pattern the
/// MCP stdio prober uses. The caller owns the `Process`; this type only touches the handles.
public final class LSPStdioTransport: LSPTransport, @unchecked Sendable {
    private let input: FileHandle
    private let output: FileHandle
    private let writeLock = NSLock()
    private var closed = false

    public init(input: FileHandle, output: FileHandle) {
        self.input = input
        self.output = output
    }

    public func send(_ data: Data) throws {
        writeLock.lock()
        defer { writeLock.unlock() }
        guard !closed else { throw LSPError.serverClosed("transport is closed") }
        // `write(contentsOf:)` throws instead of raising SIGPIPE-style traps when the pipe is broken,
        // which is exactly what we want when the server has died mid-request.
        try input.write(contentsOf: data)
    }

    /// Closes both pipe ends. Closing stdin sends EOF to the child so it can exit cleanly; closing
    /// stdout releases the read fd. Idempotent and error-swallowing — a double close or an
    /// already-broken pipe is not worth surfacing on a teardown path.
    public func close() {
        writeLock.lock()
        defer { writeLock.unlock() }
        guard !closed else { return }
        closed = true
        try? input.close()
        try? output.close()
    }

    public func receive(timeout: TimeInterval) throws -> Data? {
        let milliseconds = Int32(max(0, min(timeout * 1000, Double(Int32.max))))
        var descriptor = pollfd(fd: output.fileDescriptor, events: Int16(POLLIN), revents: 0)
        let ready = poll(&descriptor, 1, milliseconds)
        if ready == 0 {
            return Data() // plain timeout — no bytes, not EOF
        }
        guard ready > 0 else {
            if errno == EINTR { return Data() } // interrupted syscall — let the caller retry
            throw LSPError.serverClosed("poll on server stdout failed with errno \(errno)")
        }

        var bytes = [UInt8](repeating: 0, count: 64 * 1024)
        let count = read(descriptor.fd, &bytes, bytes.count)
        if count == 0 {
            return nil // EOF: the server closed its stdout / exited
        }
        guard count > 0 else {
            if errno == EINTR || errno == EAGAIN { return Data() }
            throw LSPError.serverClosed("read on server stdout failed with errno \(errno)")
        }
        return Data(bytes.prefix(count))
    }
}
