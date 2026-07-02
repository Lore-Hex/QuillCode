import Foundation

/// Owns the running language-server sessions for one workspace and hands out a ready `LSPClient` for
/// a given file, launching and initializing the server on first use. One session per server
/// *command* (all `.swift` files share one sourcekit-lsp), keyed by the config's command.
///
/// Robustness is centered here:
/// - **Missing server:** `client(forPath:)` returns `nil` and records a one-time notice; callers no-op.
/// - **Crash:** a dead process is detected before reuse and relaunched, up to a bounded restart count
///   with backoff, after which the language is disabled for the session (no infinite relaunch loop).
/// - **Slow/hung:** every client call carries a deadline, so the manager itself never blocks unbounded.
///
/// Access is serialized by a lock; the manager is `@unchecked Sendable` and safe to share across the
/// tool router instances created per tool step.
public final class LSPSessionManager: @unchecked Sendable {
    private struct Session {
        var client: LSPClient
        var process: any LSPProcessControlling
        var config: LSPServerConfig
        var restarts: Int
    }

    /// Max relaunches of a repeatedly-crashing server before its language is disabled for the run.
    static let maxRestarts = 3

    private let workspaceRoot: URL
    private let registry: LSPServerRegistry
    private let launcher: LSPServerLaunching
    /// Upper bound on the `initialize` handshake. A server that does not complete it in this window is
    /// treated as a failed launch (and, after `maxRestarts`, disabled) rather than blocking forever.
    private let initializeTimeout: TimeInterval
    private let lock = NSLock()

    /// Keyed by server command. A `nil` value marks a command we know is unavailable (missing binary
    /// or exhausted restarts) so we neither retry launching nor renotify.
    private var sessions: [String: Session] = [:]
    private var disabledCommands: Set<String> = []
    private var emittedUnavailableNotice: Set<String> = []

    public init(
        workspaceRoot: URL,
        registry: LSPServerRegistry = LSPServerRegistry(),
        launcher: LSPServerLaunching = DefaultLSPServerLauncher(),
        initializeTimeout: TimeInterval = 10.0
    ) {
        self.workspaceRoot = workspaceRoot.standardizedFileURL
        self.registry = registry
        self.launcher = launcher
        self.initializeTimeout = initializeTimeout
    }

    /// Whether any language server is configured *and available* for this file's type. Cheap check
    /// used to skip the diagnostics/format work entirely for unsupported files.
    public func hasServer(forPath path: String) -> Bool {
        registry.config(forPath: path) != nil
    }

    /// The `languageId` for a file, or `nil` if unsupported.
    public func languageID(forPath path: String) -> String? {
        registry.config(forPath: path)?.languageID
    }

    /// A ready, initialized client for the server that handles `path`, launching it if needed.
    /// Returns `nil` (never throws) when the server is missing, disabled, or fails to start — the LSP
    /// features are a multiplier, so their absence must be a silent no-op to the write path.
    public func client(forPath path: String) -> LSPClient? {
        lock.lock()
        defer { lock.unlock() }
        guard let config = registry.config(forPath: path) else { return nil }
        let key = config.command

        if disabledCommands.contains(key) { return nil }

        // Reuse a live session; relaunch a crashed OR poisoned one within the restart budget. A client
        // whose read stream desynced on a malformed frame (`isHealthy == false`) is as unusable as a
        // dead process — reusing it would replay the corrupt buffer on every request — so it is torn
        // down and relaunched the same way.
        if let existing = sessions[key] {
            if existing.process.isRunning && existing.client.isHealthy {
                return existing.client
            }
            // The process died or the stream is corrupt. Reap it AND close the transport so its
            // stdin/stdout fds are not leaked across the relaunch.
            existing.process.terminate()
            existing.client.closeTransport()
            sessions[key] = nil
            guard existing.restarts < Self.maxRestarts else {
                disabledCommands.insert(key)
                return nil
            }
            return launchAndStore(config: config, key: key, restarts: existing.restarts + 1)
        }

        return launchAndStore(config: config, key: key, restarts: 0)
    }

    /// A one-time human-readable notice for a file whose server is unavailable, or `nil` if a server
    /// is available or the notice was already emitted for this command. The write path shows this
    /// once so the model knows why diagnostics are quiet, without repeating it on every write.
    public func consumeUnavailableNoticeIfNeeded(forPath path: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let config = registry.config(forPath: path) else { return nil }
        let key = config.command
        // Only notice when we actually tried and failed (missing binary or disabled after crashes).
        guard disabledCommands.contains(key) || registry.resolveExecutable(for: config) == nil else {
            return nil
        }
        guard !emittedUnavailableNotice.contains(key) else { return nil }
        emittedUnavailableNotice.insert(key)
        return "Language server '\(config.command)' is not available; skipping diagnostics and formatting."
    }

    /// Terminates every running server. Call on workspace teardown.
    public func shutdown() {
        lock.lock()
        defer { lock.unlock() }
        for (_, session) in sessions {
            session.client.shutdown()
            session.process.terminate()
        }
        sessions.removeAll()
    }

    // MARK: Private

    private func launchAndStore(config: LSPServerConfig, key: String, restarts: Int) -> LSPClient? {
        guard let executable = registry.resolveExecutable(for: config) else {
            disabledCommands.insert(key)
            return nil
        }
        let launched: LSPLaunchedServer
        do {
            launched = try launcher.launch(
                executable: executable,
                arguments: config.arguments,
                workspaceRoot: workspaceRoot
            )
        } catch {
            if restarts >= Self.maxRestarts { disabledCommands.insert(key) }
            return nil
        }
        let client = LSPClient(transport: launched.transport)
        do {
            // A failed handshake (timeout / EOF) counts as a launch failure — tear it down and, on
            // repeated failure, disable rather than relaunch endlessly.
            try client.initialize(workspaceRoot: workspaceRoot, timeout: initializeTimeout)
            sessions[key] = Session(client: client, process: launched.process, config: config, restarts: restarts)
            return client
        } catch {
            // Reap the process and close the transport so a failed handshake does not leak fds.
            launched.process.terminate()
            client.closeTransport()
            if restarts >= Self.maxRestarts { disabledCommands.insert(key) }
            return nil
        }
    }
}
