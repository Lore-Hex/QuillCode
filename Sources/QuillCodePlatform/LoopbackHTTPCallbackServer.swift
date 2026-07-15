import CQuillPlatform
import Foundation

public enum LoopbackHTTPCallbackError: Error, CustomStringConvertible, Sendable, Equatable {
    case invalidCallbackURL(String)
    case invalidPath(String)
    case listenerUnavailable(port: UInt16)
    case listenerFailed
    case invalidRequest
    case cancelled
    case alreadyWaiting

    public var description: String {
        switch self {
        case .invalidCallbackURL(let value):
            return "Invalid localhost callback URL: \(value)"
        case .invalidPath(let path):
            return "Invalid loopback callback path: \(path)"
        case .listenerUnavailable(let port):
            return port == 0
                ? "Could not reserve a localhost callback port."
                : "Could not reserve localhost callback port \(port)."
        case .listenerFailed:
            return "The localhost callback listener failed."
        case .invalidRequest:
            return "The localhost callback request was invalid."
        case .cancelled:
            return "The localhost callback was cancelled."
        case .alreadyWaiting:
            return "The localhost callback listener can only be awaited once."
        }
    }
}

/// A single-use HTTP listener bound strictly to 127.0.0.1. POSIX socket details live in the
/// `CQuillPlatform` adapter, keeping every Swift caller identical on macOS and Linux.
public final class LoopbackHTTPCallbackServer: @unchecked Sendable {
    public let callbackURL: URL

    private static let maximumRequestBytes = 16 * 1_024
    private static let acceptPollMilliseconds: Int32 = 100
    private static let maximumRequestReceiveAttempts = 64

    private struct State {
        var isWaiting = false
        var isCancelled = false
        var isFinished = false
        var isClosed = false
    }

    private let callbackPath: String
    private let callbackOrigin: URL
    private let serverDescriptor: Int32
    private let requestReceiveAttemptLimit: Int
    private let lock = NSLock()
    private var state = State()

    /// Creates a listener for an exact, pre-registered localhost redirect URL. This is used for
    /// OAuth providers such as TrustedRouter that allowlist a fixed port and path.
    public convenience init(callbackURL: URL) throws {
        guard let components = URLComponents(
            url: callbackURL,
            resolvingAgainstBaseURL: false
        ),
        components.scheme?.lowercased() == "http",
        components.host?.lowercased() == "localhost",
        components.user == nil,
        components.password == nil,
        components.query == nil,
        components.fragment == nil,
        components.percentEncodedPath.count > 1,
        let configuredPort = components.port,
        (1...Int(UInt16.max)).contains(configuredPort)
        else {
            throw LoopbackHTTPCallbackError.invalidCallbackURL(callbackURL.absoluteString)
        }

        let path = components.percentEncodedPath
        try self.init(port: UInt16(configuredPort), callbackPath: path)
        guard self.callbackURL.absoluteString == callbackURL.absoluteString else {
            cancel()
            throw LoopbackHTTPCallbackError.invalidCallbackURL(callbackURL.absoluteString)
        }
    }

    public convenience init(port: UInt16 = 0, callbackPath: String = "/callback") throws {
        try self.init(
            port: port,
            callbackPath: callbackPath,
            requestReceiveAttemptLimit: Self.maximumRequestReceiveAttempts
        )
    }

    init(
        port: UInt16,
        callbackPath: String,
        requestReceiveAttemptLimit: Int
    ) throws {
        precondition(requestReceiveAttemptLimit > 0)
        let path = callbackPath.hasPrefix("/") ? callbackPath : "/\(callbackPath)"
        guard path.count > 1,
              !path.contains("?"),
              !path.contains("#"),
              let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              encodedPath == path
        else {
            throw LoopbackHTTPCallbackError.invalidPath(callbackPath)
        }

        var boundPort: UInt16 = 0
        let descriptor = cquill_loopback_open(port, &boundPort)
        guard descriptor >= 0,
              let origin = URL(string: "http://localhost:\(boundPort)"),
              let callback = URL(string: path, relativeTo: origin)?.absoluteURL
        else {
            if descriptor >= 0 { _ = cquill_descriptor_close(descriptor) }
            throw LoopbackHTTPCallbackError.listenerUnavailable(port: port)
        }

        self.callbackPath = path
        self.callbackOrigin = origin
        self.callbackURL = callback
        self.serverDescriptor = descriptor
        self.requestReceiveAttemptLimit = requestReceiveAttemptLimit
    }

    deinit {
        cancel()
    }

    public func waitForCallback() async throws -> URL {
        try beginWaiting()
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) { [self] in
                try waitForCallbackBlocking()
            }.value
        } onCancel: {
            self.cancel()
        }
    }

    public func cancel() {
        let shouldShutdown = lock.withLock { () -> Bool in
            guard !state.isCancelled, !state.isFinished else { return false }
            state.isCancelled = true
            if !state.isWaiting {
                closeDescriptorLocked()
                state.isFinished = true
                return false
            }
            return true
        }
        if shouldShutdown {
            _ = cquill_socket_shutdown(serverDescriptor)
        }
    }

    private func beginWaiting() throws {
        try lock.withLock {
            guard !state.isWaiting else { throw LoopbackHTTPCallbackError.alreadyWaiting }
            guard !state.isCancelled, !state.isFinished else {
                throw LoopbackHTTPCallbackError.cancelled
            }
            state.isWaiting = true
        }
    }

    private func waitForCallbackBlocking() throws -> URL {
        defer { finishWaiting() }
        while !isCancelled {
            let clientDescriptor = cquill_loopback_accept(
                serverDescriptor,
                Self.acceptPollMilliseconds
            )
            if clientDescriptor == -2 { continue }
            guard clientDescriptor >= 0 else {
                if isCancelled { throw LoopbackHTTPCallbackError.cancelled }
                throw LoopbackHTTPCallbackError.listenerFailed
            }
            defer { _ = cquill_descriptor_close(clientDescriptor) }

            do {
                let target = try readRequestTarget(from: clientDescriptor)
                guard isCallbackTarget(target),
                      let callback = URL(string: target, relativeTo: callbackOrigin)?.absoluteURL
                else {
                    try sendResponse(
                        status: "404 Not Found",
                        message: "QuillCode is waiting for its sign-in callback.",
                        to: clientDescriptor
                    )
                    continue
                }
                try sendResponse(
                    status: "200 OK",
                    message: "QuillCode sign-in is complete. You can return to QuillCode.",
                    to: clientDescriptor
                )
                return callback
            } catch {
                if isCancelled { throw LoopbackHTTPCallbackError.cancelled }
                try? sendResponse(
                    status: "400 Bad Request",
                    message: "QuillCode could not read the sign-in callback.",
                    to: clientDescriptor
                )
                continue
            }
        }
        throw LoopbackHTTPCallbackError.cancelled
    }

    private var isCancelled: Bool {
        lock.withLock { state.isCancelled }
    }

    private func finishWaiting() {
        lock.withLock {
            state.isFinished = true
            closeDescriptorLocked()
        }
    }

    private func closeDescriptorLocked() {
        guard !state.isClosed else { return }
        state.isClosed = true
        _ = cquill_descriptor_close(serverDescriptor)
    }

    private func readRequestTarget(from descriptor: Int32) throws -> String {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 2_048)
        var receiveAttempts = 0
        while data.count < Self.maximumRequestBytes {
            if isCancelled { throw LoopbackHTTPCallbackError.cancelled }
            guard receiveAttempts < requestReceiveAttemptLimit else {
                throw LoopbackHTTPCallbackError.invalidRequest
            }
            receiveAttempts += 1
            let remaining = min(buffer.count, Self.maximumRequestBytes - data.count)
            let count = buffer.withUnsafeMutableBytes { bytes in
                cquill_socket_receive(
                    descriptor,
                    bytes.baseAddress,
                    remaining,
                    Self.acceptPollMilliseconds
                )
            }
            if count == -2 { continue }
            guard count > 0 else { throw LoopbackHTTPCallbackError.invalidRequest }
            data.append(buffer, count: Int(count))
            if data.range(of: Data("\r\n\r\n".utf8)) != nil { break }
        }
        guard data.count < Self.maximumRequestBytes,
              let request = String(data: data, encoding: .utf8),
              let firstLine = request.components(separatedBy: "\r\n").first
        else {
            throw LoopbackHTTPCallbackError.invalidRequest
        }
        let parts = firstLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 3,
              parts[0] == "GET",
              parts[2].hasPrefix("HTTP/1."),
              parts[1].hasPrefix("/")
        else {
            throw LoopbackHTTPCallbackError.invalidRequest
        }
        return String(parts[1])
    }

    private func isCallbackTarget(_ target: String) -> Bool {
        target == callbackPath || target.hasPrefix("\(callbackPath)?")
    }

    private func sendResponse(status: String, message: String, to descriptor: Int32) throws {
        let escaped = message
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let body = """
        <!doctype html>
        <html lang="en">
          <head><meta charset="utf-8"><title>QuillCode</title></head>
          <body style="font-family: system-ui, sans-serif; padding: 40px;"><h1>\(escaped)</h1></body>
        </html>
        """
        let bodyData = Data(body.utf8)
        let header = [
            "HTTP/1.1 \(status)",
            "Content-Type: text/html; charset=utf-8",
            "Content-Length: \(bodyData.count)",
            "Cache-Control: no-store",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        var payload = Data(header.utf8)
        payload.append(bodyData)
        let result = payload.withUnsafeBytes { bytes in
            cquill_socket_send_all(descriptor, bytes.baseAddress, bytes.count)
        }
        guard result == 0 else { throw LoopbackHTTPCallbackError.listenerFailed }
    }
}

private extension NSLock {
    func withLock<Result>(_ operation: () throws -> Result) rethrows -> Result {
        lock()
        defer { unlock() }
        return try operation()
    }
}
