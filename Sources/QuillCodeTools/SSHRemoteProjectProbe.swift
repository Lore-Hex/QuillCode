import Foundation
import QuillCodeCore

public struct SSHRemoteProjectProbeResult: Sendable, Hashable {
    public var isReachable: Bool
    public var resolvedPath: String?
    public var errorMessage: String?

    public init(isReachable: Bool, resolvedPath: String? = nil, errorMessage: String? = nil) {
        self.isReachable = isReachable
        self.resolvedPath = resolvedPath
        self.errorMessage = errorMessage
    }
}

public struct SSHRemoteProjectProbe: Sendable {
    private static let marker = "__QUILLCODE_SSH_READY__"

    public var remoteExecutor: SSHRemoteShellExecutor
    public var shellExecutor: ShellToolExecutor

    public init(
        remoteExecutor: SSHRemoteShellExecutor = SSHRemoteShellExecutor(),
        shellExecutor: ShellToolExecutor = ShellToolExecutor()
    ) {
        self.remoteExecutor = remoteExecutor
        self.shellExecutor = shellExecutor
    }

    public func run(connection: ProjectConnection) async -> SSHRemoteProjectProbeResult {
        guard let request = remoteExecutor.request(
            command: "printf '\(Self.marker)\\n' && pwd",
            connection: connection,
            timeoutSeconds: 15
        ) else {
            return SSHRemoteProjectProbeResult(
                isReachable: false,
                errorMessage: "The SSH host or remote folder is invalid."
            )
        }
        let result = await shellExecutor.runCancellable(request)
        guard result.ok else {
            return SSHRemoteProjectProbeResult(
                isReachable: false,
                errorMessage: Self.failureMessage(for: result)
            )
        }
        let lines = result.stdout.split(whereSeparator: \Character.isNewline).map(String.init)
        guard let markerIndex = lines.firstIndex(of: Self.marker) else {
            return SSHRemoteProjectProbeResult(
                isReachable: false,
                errorMessage: "SSH connected but returned an unexpected response."
            )
        }
        guard let resolvedPath = lines.dropFirst(markerIndex + 1).first,
              resolvedPath.hasPrefix("/")
        else {
            return SSHRemoteProjectProbeResult(
                isReachable: false,
                errorMessage: "SSH connected but did not resolve the remote project folder."
            )
        }
        return SSHRemoteProjectProbeResult(isReachable: true, resolvedPath: resolvedPath)
    }

    private static func failureMessage(for result: ToolResult) -> String {
        let detail = [result.stderr, result.error]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let detail else { return "Could not connect to the SSH host." }
        return String(detail.prefix(360))
    }
}
