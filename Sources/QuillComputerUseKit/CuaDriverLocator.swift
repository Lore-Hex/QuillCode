import Foundation

/// Discovers an installed `cua-driver` binary and builds a permission-probed
/// `CuaDriverComputerUseBackend`, or reports that cua is unavailable so the caller can fall back to
/// the native CGEvent backend.
///
/// Discovery order: an explicit path (settings/env `QUILLCODE_CUA_DRIVER_PATH`), then a small set of
/// conventional install locations. When found, telemetry is disabled once (QuillCode's privacy
/// posture — no automation metadata leaves the machine), and `check_permissions` is probed to build
/// status. Because cua's `call` path runs in-process and inherits the *caller's* TCC identity, the
/// probed Accessibility + Screen Recording grants are QuillCode's own — the same grants the native
/// backend already asks the user for, so adopting cua adds no new permission prompt.
public struct CuaDriverLocator: Sendable {
    /// The environment variable a user (or QuillCode settings) can set to point at a specific binary.
    public static let pathEnvironmentVariable = "QUILLCODE_CUA_DRIVER_PATH"

    private let runProcess: @Sendable (_ arguments: [String], _ stdin: Data?) async throws -> CuaDriverProcessClient.ProcessRunResult
    private let fileExists: @Sendable (String) -> Bool

    public init(
        runProcess: @escaping @Sendable (_ arguments: [String], _ stdin: Data?) async throws -> CuaDriverProcessClient.ProcessRunResult = CuaDriverProcessClient.defaultRunProcess,
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        self.runProcess = runProcess
        self.fileExists = fileExists
    }

    /// Resolves the driver path (nil if none is installed).
    public func resolvedDriverPath(
        explicitPath: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        Self.resolveDriverPath(
            explicitPath: explicitPath,
            environment: environment,
            candidatePaths: Self.candidatePaths(home: environment["HOME"]),
            fileExists: fileExists
        )
    }

    /// Builds a cua backend if the binary is present; returns nil so the caller falls back otherwise.
    /// The returned backend's `status` reflects QuillCode's inherited grants, so a missing grant still
    /// yields a cua backend whose preflight tells the user exactly what to grant (parity with native).
    public func makeBackendIfAvailable(
        explicitPath: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        sessionID: String = "quillcode",
        maxScreenshotDimension: Int? = 1568
    ) async -> CuaDriverComputerUseBackend? {
        guard let path = resolvedDriverPath(explicitPath: explicitPath, environment: environment) else {
            return nil
        }
        // Best-effort, idempotent: keep automation metadata on-device.
        _ = try? await runProcess([path, "telemetry", "disable"], nil)

        let client = CuaDriverProcessClient(driverPath: path, runProcess: runProcess)
        let status = await probeStatus(client: client)
        return CuaDriverComputerUseBackend(
            client: client,
            status: status,
            sessionID: sessionID,
            maxScreenshotDimension: maxScreenshotDimension
        )
    }

    private func probeStatus(client: CuaDriverProcessClient) async -> ComputerUseStatus {
        do {
            let result = try await client.callTool(
                name: "check_permissions",
                argumentsJSON: CuaJSON.encode(["prompt": false])
            )
            guard let status = Self.status(fromCheckPermissions: result) else {
                return .unavailable("cua-driver check_permissions returned an unexpected shape.")
            }
            return status
        } catch {
            return .unavailable("cua-driver could not be probed: \(error)")
        }
    }

    // MARK: - Pure helpers (unit-tested without a subprocess)

    /// Conventional install locations, most-specific first. `~` is expanded from `home`.
    public static func candidatePaths(home: String?) -> [String] {
        var paths: [String] = []
        if let home, !home.isEmpty {
            paths.append(contentsOf: [
                "\(home)/.quillcode/tools/cua-driver",
                "\(home)/.local/bin/cua-driver",
                "\(home)/.cua/bin/cua-driver",
            ])
        }
        paths.append(contentsOf: [
            "/opt/homebrew/bin/cua-driver",
            "/usr/local/bin/cua-driver",
        ])
        return paths
    }

    public static func resolveDriverPath(
        explicitPath: String?,
        environment: [String: String],
        candidatePaths: [String],
        fileExists: (String) -> Bool
    ) -> String? {
        let ordered = [explicitPath, environment[pathEnvironmentVariable]].compactMap { $0 }
            .map { ($0 as NSString).expandingTildeInPath }
            + candidatePaths
        return ordered.first(where: fileExists)
    }

    public static func status(fromCheckPermissions data: Data) -> ComputerUseStatus? {
        guard let object = CuaJSON.object(from: data) else { return nil }
        guard
            let accessibility = object["accessibility"] as? Bool,
            let screenRecording = object["screen_recording"] as? Bool
        else {
            return nil
        }
        return .permissionStatus(
            screenRecordingGranted: screenRecording,
            accessibilityGranted: accessibility
        )
    }
}
