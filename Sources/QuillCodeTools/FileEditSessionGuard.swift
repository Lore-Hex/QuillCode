import Foundation

/// Records which workspace files a session has actually read, so a model-driven write or
/// patch can be refused when it would blind-overwrite a file the session never inspected. Also
/// hands out per-file locks so concurrent edits to the same file are serialized instead of
/// interleaved.
///
/// One instance is one "session" of file knowledge, and the invariant it protects is
/// "THIS session's model has seen this file's content". The scopes in use:
///
/// - `session(for:)` — the guard for one chat thread's model context, keyed by the thread ID.
///   The agent tool loop (CLI and desktop) uses this: a read that entered thread A's context
///   never grants thread B write rights, and a new chat starts with an empty read-set.
/// - The desktop app keeps ONE separate guard for app/UI-initiated tool runs
///   (`QuillCodeWorkspaceModel.uiEditSessionGuard`), so a review-pane "Open" click never grants
///   any model thread write rights.
/// - `shared` — the process-wide fallback for `ToolRouter` construction sites without a finer
///   session. No model loop uses it; the agent and workspace paths inject a scoped guard.
///
/// Tests inject fresh instances for isolation.
public final class FileEditSessionGuard: @unchecked Sendable {
    public static let shared = FileEditSessionGuard()

    private static let sessions = SessionRegistry()

    private let stateLock = NSLock()
    private var readKeys: Set<String> = []
    private var fileLocks: [String: NSLock] = [:]

    public init() {}

    /// The guard scoped to one model session (chat thread), keyed by the thread ID. The same ID
    /// always returns the same instance for the lifetime of the process; a new thread ID starts
    /// with an empty read-set. (Entries are a few strings per touched file — no eviction needed
    /// at chat-thread scale.)
    public static func session(for id: UUID) -> FileEditSessionGuard {
        sessions.sessionGuard(for: id)
    }

    /// Records that the session knows the current content of `url` — a successful read, or a
    /// write/patch the session itself just made.
    public func markRead(_ url: URL) {
        let key = Self.key(for: url)
        stateLock.lock()
        defer { stateLock.unlock() }
        readKeys.insert(key)
    }

    public func hasRead(_ url: URL) -> Bool {
        let key = Self.key(for: url)
        stateLock.lock()
        defer { stateLock.unlock() }
        return readKeys.contains(key)
    }

    /// Runs `body` while holding this session's lock for every URL in `urls`, so two edits
    /// touching the same file cannot interleave. Locks are acquired in sorted key order (each
    /// key at most once), which keeps multi-file acquisition deadlock-free.
    public func withExclusiveAccess<T>(to urls: [URL], _ body: () throws -> T) rethrows -> T {
        let locks = orderedLocks(for: urls)
        for lock in locks { lock.lock() }
        defer {
            for lock in locks.reversed() { lock.unlock() }
        }
        return try body()
    }

    private func orderedLocks(for urls: [URL]) -> [NSLock] {
        let keys = Set(urls.map(Self.key(for:))).sorted()
        stateLock.lock()
        defer { stateLock.unlock() }
        return keys.map { key in
            if let existing = fileLocks[key] { return existing }
            let lock = NSLock()
            fileLocks[key] = lock
            return lock
        }
    }

    /// Symlink-resolved absolute path, so the same file always lands on the same key no matter
    /// how it was addressed (e.g. macOS `/var` vs `/private/var` temporary directories).
    private static func key(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

/// The lock-protected thread-ID → guard map behind `FileEditSessionGuard.session(for:)`.
private final class SessionRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var guards: [UUID: FileEditSessionGuard] = [:]

    func sessionGuard(for id: UUID) -> FileEditSessionGuard {
        lock.lock()
        defer { lock.unlock() }
        if let existing = guards[id] { return existing }
        let created = FileEditSessionGuard()
        guards[id] = created
        return created
    }
}

public enum FileEditGuardError: Error, CustomStringConvertible {
    case writeWithoutRead(String)
    case patchWithoutRead(String)
    case noOpWrite(String)

    public var description: String {
        switch self {
        case .writeWithoutRead(let path):
            return "Refusing to overwrite \(path): the file exists but was not read in this session. "
                + "Read it with host.file.read first, then write content based on what is actually there."
        case .patchWithoutRead(let path):
            return "Refusing to patch \(path): the file exists but was not read in this session. "
                + "Read it with host.file.read first so the patch is based on what is actually there."
        case .noOpWrite(let path):
            return "No-op write to \(path): the new content is identical to what the file already contains. "
                + "Skip this write, or re-read the file if you expected different content."
        }
    }
}
