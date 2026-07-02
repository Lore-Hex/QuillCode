import Foundation

/// Failure modes of the LSP subsystem. Every one is recoverable: the LSP features degrade to a
/// no-op (writes still succeed, nav tool reports the reason) rather than propagating up and breaking
/// the agent loop. The subsystem is a *correctness multiplier*, never a correctness *dependency*.
public enum LSPError: Error, Equatable, CustomStringConvertible {
    /// A response frame's Content-Length header was missing, negative, non-numeric, or oversized, or
    /// the framed body was not a JSON object. The transport carries untrusted bytes from an external
    /// subprocess, so a malformed frame must be reported, never force-unwrapped through.
    case invalidMessage(String)
    /// The server did not produce a response for a request id before the request's deadline. The
    /// caller aborts the single request; it never spins forever on a silent server.
    case timeout(String)
    /// The server returned a JSON-RPC `error` object for a request (e.g. an unsupported method).
    case serverError(code: Int, message: String)
    /// No language server could be located for a file (none configured for its extension, or the
    /// configured command was not found on PATH / via xcrun). The caller degrades gracefully.
    case serverUnavailable(String)
    /// The server subprocess exited / its stdout hit EOF while a request was outstanding.
    case serverClosed(String)

    public var description: String {
        switch self {
        case .invalidMessage(let detail):
            return "LSP message error: \(detail)"
        case .timeout(let detail):
            return "LSP timeout: \(detail)"
        case .serverError(let code, let message):
            return "LSP server error \(code): \(message)"
        case .serverUnavailable(let detail):
            return "LSP unavailable: \(detail)"
        case .serverClosed(let detail):
            return "LSP server closed: \(detail)"
        }
    }
}
