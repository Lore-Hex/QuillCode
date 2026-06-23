import Foundation
import Network
import QuillCodeCore

enum TrustedRouterLoopbackError: Error, CustomStringConvertible {
    case invalidPort
    case invalidCallbackURL(String)
    case listenerFailed(String)
    case cancelled
    case invalidCallbackRequest

    var description: String {
        switch self {
        case .invalidPort:
            return "Could not reserve localhost OAuth callback port 3000."
        case .invalidCallbackURL(let value):
            return "TrustedRouter sign-in callback URL is invalid: \(value)"
        case .listenerFailed(let message):
            return "TrustedRouter sign-in callback server failed: \(message)"
        case .cancelled:
            return "TrustedRouter sign-in was cancelled."
        case .invalidCallbackRequest:
            return "TrustedRouter sign-in callback request was invalid."
        }
    }
}

final class TrustedRouterLoopbackCallbackServer: @unchecked Sendable {
    static let callbackURL = TrustedRouterDefaults.loopbackCallbackURL

    private let queue = DispatchQueue(label: "co.lorehex.quillcode.oauth-loopback")
    private let listener: NWListener
    private let callbackBaseURL: URL
    private let callbackPath: String
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var callbackContinuation: CheckedContinuation<URL, Error>?
    private var pendingCallbackResult: Result<URL, Error>?
    private var isStarted = false
    private var isFinished = false

    init() throws {
        let parsedCallbackURL = try Self.parseCallbackURL(Self.callbackURL)
        self.callbackBaseURL = parsedCallbackURL.baseURL
        self.callbackPath = parsedCallbackURL.path
        guard let port = NWEndpoint.Port(rawValue: 3000) else {
            throw TrustedRouterLoopbackError.invalidPort
        }
        self.listener = try NWListener(using: .tcp, on: port)
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
            self.finish(.failure(TrustedRouterLoopbackError.cancelled), cancelListener: true)
        }
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            isStarted = true
            startContinuation?.resume()
            startContinuation = nil
        case .failed(let error):
            finish(.failure(TrustedRouterLoopbackError.listenerFailed(String(describing: error))), cancelListener: true)
        case .cancelled:
            if !isFinished {
                finish(.failure(TrustedRouterLoopbackError.cancelled), cancelListener: false)
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
            if let error {
                self.sendHTML(
                    status: "400 Bad Request",
                    body: "QuillCode could not read the TrustedRouter callback.",
                    on: connection
                )
                self.finish(.failure(TrustedRouterLoopbackError.listenerFailed(String(describing: error))), cancelListener: true)
                return
            }
            guard let data,
                  let request = String(data: data, encoding: .utf8),
                  let target = self.requestTarget(from: request)
            else {
                self.sendHTML(
                    status: "400 Bad Request",
                    body: "QuillCode received an invalid TrustedRouter callback.",
                    on: connection
                )
                self.finish(.failure(TrustedRouterLoopbackError.invalidCallbackRequest), cancelListener: true)
                return
            }
            guard self.isCallbackTarget(target),
                  let callbackURL = URL(
                    string: "\(self.callbackBaseURL.absoluteString)\(target.dropFirst(self.callbackPath.count))"
                  )
            else {
                self.sendHTML(
                    status: "404 Not Found",
                    body: "QuillCode is waiting for the TrustedRouter sign-in callback.",
                    on: connection
                )
                return
            }

            self.sendHTML(
                status: "200 OK",
                body: "QuillCode sign-in complete. You can return to QuillCode.",
                on: connection
            ) {
                self.finish(.success(callbackURL), cancelListener: true)
            }
        }
    }

    private static func parseCallbackURL(_ value: String) throws -> (baseURL: URL, path: String) {
        guard let url = URL(string: value),
              let scheme = url.scheme,
              let host = url.host,
              scheme == "http",
              host == "localhost"
        else {
            throw TrustedRouterLoopbackError.invalidCallbackURL(value)
        }
        return (url, url.path.isEmpty ? "/" : url.path)
    }

    private func isCallbackTarget(_ target: String) -> Bool {
        target == callbackPath || target.hasPrefix("\(callbackPath)?")
    }

    private func requestTarget(from request: String) -> String? {
        guard let firstLine = request.components(separatedBy: "\r\n").first else {
            return nil
        }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else {
            return nil
        }
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
        guard !isFinished else {
            return
        }
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
