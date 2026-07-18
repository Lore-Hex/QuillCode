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
        fileExists: @escaping @Sendable (String) -> Bool = { CuaDriverLocator.isSafeExecutable($0) }
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
        // Best-effort, idempotent, and PERSISTED: cua writes the disabled flag to its config file
        // (`telemetry status` reports `source: persisted`), so this one call covers every subsequent
        // one-shot `call` process. We don't hard-block cua on its result — cua telemetry is an
        // anonymous install ping, not per-action automation content — but we no longer bury a genuine
        // failure: a non-zero exit is surfaced so a regression is visible.
        if let result = try? await runProcess([path, "telemetry", "disable"], nil), result.exitCode != 0 {
            let message = String(data: result.stderr, encoding: .utf8) ?? ""
            NSLog("cua-driver telemetry disable exited \(result.exitCode): \(message.prefix(200))")
        }

        let client = CuaDriverProcessClient(driverPath: path, runProcess: runProcess)
        // A probe FAILURE (driver errored / unexpected shape) returns nil so the caller keeps the
        // already-working native backend, rather than clobbering it with a dead cua backend. A valid
        // "needs Accessibility" status is NOT a failure — that's a usable cua backend the user grants.
        guard let status = await probeStatus(client: client) else {
            return nil
        }
        return CuaDriverComputerUseBackend(
            client: client,
            status: status,
            sessionID: sessionID,
            maxScreenshotDimension: maxScreenshotDimension
        )
    }

    private func probeStatus(client: CuaDriverProcessClient) async -> ComputerUseStatus? {
        guard
            let result = try? await client.callTool(
                name: "check_permissions",
                argumentsJSON: CuaJSON.encode(["prompt": false])
            )
        else {
            return nil
        }
        return Self.status(fromCheckPermissions: result)
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
            let accessibility = boolValue(object["accessibility"]),
            let screenRecording = boolValue(object["screen_recording"])
        else {
            return nil
        }
        return .permissionStatus(
            screenRecordingGranted: screenRecording,
            accessibilityGranted: accessibility
        )
    }

    /// Tolerant boolean coercion (JSON bool, 0/1, "true"/"false") so a driver reporting grants as
    /// numbers/strings doesn't cause the whole backend to read as `.unavailable`.
    static func boolValue(_ value: Any?) -> Bool? {
        switch value {
        case let bool as Bool: return bool
        case let number as NSNumber: return number.boolValue
        case let string as String:
            switch string.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        default: return nil
        }
    }

    /// Guards against executing a planted binary with QuillCode's Accessibility + Screen-Recording
    /// grants: the discovered file must be executable, NOT world-writable, and owned by the current
    /// user or root. This blocks the "malware drops `~/.quillcode/tools/cua-driver`" escalation while
    /// leaving normal user/Homebrew installs untouched. (An explicit `QUILLCODE_CUA_DRIVER_PATH` is
    /// user intent, but is held to the same bar — cheap and catches a world-writable target.)
    public static func isSafeExecutable(_ path: String) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: path) else { return false }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return false }
        if let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue,
           permissions & 0o002 != 0 {
            return false // world-writable
        }
        #if canImport(Glibc) || canImport(Darwin)
        if let owner = (attributes[.ownerAccountID] as? NSNumber)?.uint32Value {
            let currentUser = getuid()
            if owner != currentUser && owner != 0 { return false } // not owned by this user or root
        }
        #endif
        return true
    }
}
