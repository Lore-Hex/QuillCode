import Foundation

/// Invokes a single cua-driver MCP tool and returns its raw JSON result.
///
/// cua-driver (https://github.com/trycua/cua, MIT) is a background computer-use automation driver
/// that drives native apps WITHOUT stealing focus or moving the user's cursor — the property that
/// makes it right for QuillCode's unattended-coworker use. We adopt it behind QuillCode's existing
/// `ComputerUseBackend` seam, so the agent-facing tools and the Approved-Apps safety gate are
/// unchanged; only the executing driver differs.
///
/// The transport is deliberately a protocol so the whole mapping is unit-testable against a scripted
/// fake, with no subprocess. The production impl shells out `cua-driver call <tool> <args>`.
public protocol CuaDriverToolInvoking: Sendable {
    /// Calls a cua-driver tool by name. `argumentsJSON` is a serialized JSON object (may be empty
    /// `{}`). Returns the tool's raw JSON result bytes. Throws on a non-zero driver exit / transport
    /// failure.
    func callTool(name: String, argumentsJSON: Data) async throws -> Data
}

public enum CuaDriverError: Error, CustomStringConvertible, Sendable, Equatable {
    /// The configured driver binary was not found or is not executable.
    case driverNotFound(String)
    /// The `cua-driver call` process exited non-zero; carries the tool name and captured stderr.
    case toolFailed(tool: String, message: String)
    /// The driver returned output that could not be parsed as the expected JSON shape.
    case malformedResult(tool: String, detail: String)

    public var description: String {
        switch self {
        case .driverNotFound(let path):
            return "cua-driver not found at \(path)"
        case .toolFailed(let tool, let message):
            return "cua-driver \(tool) failed: \(message)"
        case .malformedResult(let tool, let detail):
            return "cua-driver \(tool) returned unexpected output: \(detail)"
        }
    }
}

/// Minimal JSON helpers over `JSONSerialization`, so the backend can build tool arguments and read
/// results without a dynamic-JSON dependency. Kept internal + tiny on purpose.
enum CuaJSON {
    /// Serializes a `[String: any Sendable]`-shaped argument object to JSON `Data`. Only the value
    /// types the tool schemas use (String, Int, Double, Bool, nested [String: …], [Any]) are passed.
    static func encode(_ object: [String: Any]) -> Data {
        // sortedKeys makes the emitted arguments deterministic, which is what the tests assert on.
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    static func object(from data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func array(from data: Data) -> [Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [Any]
    }
}
