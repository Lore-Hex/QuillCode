import Foundation

public enum ToolFailureKind: String, Codable, Sendable, Hashable {
    case sandboxDenied
    case sandboxUnavailable
}

public struct ToolResult: Codable, Sendable, Hashable {
    public var ok: Bool
    public var stdout: String
    public var stderr: String
    public var exitCode: Int32?
    public var error: String?
    public var artifacts: [String]
    public var failureKind: ToolFailureKind?

    public init(
        ok: Bool,
        stdout: String = "",
        stderr: String = "",
        exitCode: Int32? = nil,
        error: String? = nil,
        artifacts: [String] = [],
        failureKind: ToolFailureKind? = nil
    ) {
        self.ok = ok
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.error = error
        self.artifacts = artifacts
        self.failureKind = failureKind
    }
}
