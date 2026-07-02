import Foundation
import Network
import QuillCodeCore

enum MCPOAuthLoopbackError: Error, CustomStringConvertible {
    case invalidPort
    case listenerFailed(String)
    case cancelled
    case invalidCallbackRequest

    var description: String {
        switch self {
        case .invalidPort:
            return "Could not reserve a localhost port for the MCP OAuth callback."
        case .listenerFailed(let message):
            return "MCP OAuth callback server failed: \(message)"
        case .cancelled:
            return "MCP OAuth sign-in was cancelled."
        case .invalidCallbackRequest:
            return "MCP OAuth callback request was invalid."
        }
    }
}

/// A single-use localhost HTTP listener that captures one OAuth redirect. Mirrors
/// `TrustedRouterLoopbackCallbackServer` but is parameterized on port and callback path so each
/// MCP sign-in can reserve its own ephemeral port. Built on `Network.framework` like its sibling.
final class MCPOAuthLoopbackCallbackServer: @unchecked Sendable {
    let redirectURI: String

    private let queue = DispatchQueue(label: "co.lorehex.quillcode.mcp-oauth-loopback")
    private let listener: NWListener
    private let port: UInt16
    private let callbackPath: String
    private let callbackBaseURL: URL
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var callbackContinuation: CheckedContinuation<URL, Error>?
    private var pendingCallbackResult: Result<URL, Error>?
    private var isStarted = false
    private var isFinished = false

    /// Bind a loopback listener on an explicit port (chosen by the caller from an ephemeral range)
    /// and build the matching redirect URI. Throws if the port cannot be reserved so the caller
    /// can try the next candidate.
    init(port: UInt16, callbackPath: String = "/callback") throws {
        let path = callbackPath.hasPrefix("/") ? callbackPath : "/\(callbackPath)"
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw MCPOAuthLoopbackError.invalidPort
        }
        self.port = port
        self.callbackPath = path
        self.redirectURI = "http://localhost:\(port)\(path)"
        guard let base = URL(string: "http://localhost:\(port)") else {
            throw MCPOAuthLoopbackError.invalidPort
        }
        self.callbackBaseURL = base
        self.listener = try NWListener(using: .tcp, on: nwPort)
        self.listener.stateUpdateHandler = { [weak self] state in
            self?.handleListenerState(state)
        }
        self.listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if self.isStarted {
                    continuation.resume()
                    return
                }
                self.startContinuation = continuation
                self.listener.start(queue: self.queue)
            }
        }
    }

    func waitForCallback() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if let result = self.pendingCallbackResult {
                    self.pendingCallbackResult = nil
                    continuation.resume(with: result)
                    return
                }
                self.callbackContinuation = continuation
            }
        }
    }

    func cancel() {
        queue.async {
            self.finish(.failure(MCPOAuthLoopbackError.cancelled), cancelListener: true)
        }
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            isStarted = true
            startContinuation?.resume()
            startContinuation = nil
        case .failed(let error):
            finish(.failure(MCPOAuthLoopbackError.listenerFailed(String(describing: error))), cancelListener: true)
        case .cancelled:
            if !isFinished {
                finish(.failure(MCPOAuthLoopbackError.cancelled), cancelListener: false)
            }
        default:
            break
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, error in
            guard let self else {
                connection.cancel()
                return
            }
            if error != nil {
                self.sendHTML(status: "400 Bad Request", body: "QuillCode could not read the callback.", on: connection)
                self.finish(.failure(MCPOAuthLoopbackError.invalidCallbackRequest), cancelListener: true)
                return
            }
            guard let data,
                  let request = String(data: data, encoding: .utf8),
                  let target = self.requestTarget(from: request)
            else {
                self.sendHTML(status: "400 Bad Request", body: "QuillCode received an invalid callback.", on: connection)
                self.finish(.failure(MCPOAuthLoopbackError.invalidCallbackRequest), cancelListener: true)
                return
            }
            guard self.isCallbackTarget(target),
                  let callbackURL = URL(
                    string: "\(self.callbackBaseURL.absoluteString)\(target)"
                  )
            else {
                self.sendHTML(status: "404 Not Found", body: "QuillCode is waiting for the MCP sign-in callback.", on: connection)
                return
            }
            self.sendHTML(status: "200 OK", body: "MCP sign-in complete. You can return to QuillCode.", on: connection) {
                self.finish(.success(callbackURL), cancelListener: true)
            }
        }
    }

    private func isCallbackTarget(_ target: String) -> Bool {
        target == callbackPath || target.hasPrefix("\(callbackPath)?")
    }

    private func requestTarget(from request: String) -> String? {
        guard let firstLine = request.components(separatedBy: "\r\n").first else { return nil }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else { return nil }
        return String(parts[1])
    }

    private func sendHTML(
        status: String,
        body: String,
        on connection: NWConnection,
        completion: (@Sendable () -> Void)? = nil
    ) {
        let escapedBody = body
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let html = """
        <!doctype html>
        <html lang="en">
          <head><meta charset="utf-8"><title>QuillCode</title></head>
          <body style="font-family: -apple-system, BlinkMacSystemFont, sans-serif; padding: 40px;">
            <h1>\(escapedBody)</h1>
          </body>
        </html>
        """
        let bodyData = Data(html.utf8)
        let headers = [
            "HTTP/1.1 \(status)",
            "Content-Type: text/html; charset=utf-8",
            "Content-Length: \(bodyData.count)",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        var payload = Data(headers.utf8)
        payload.append(bodyData)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
            completion?()
        })
    }

    private func finish(_ result: Result<URL, Error>, cancelListener: Bool) {
        guard !isFinished else { return }
        isFinished = true
        if let startContinuation {
            switch result {
            case .success:
                startContinuation.resume()
            case .failure(let error):
                startContinuation.resume(throwing: error)
            }
        }
        startContinuation = nil
        if let continuation = callbackContinuation {
            callbackContinuation = nil
            continuation.resume(with: result)
        } else {
            pendingCallbackResult = result
        }
        if cancelListener {
            listener.cancel()
        }
    }
}
