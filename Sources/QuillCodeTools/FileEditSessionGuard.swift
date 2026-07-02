import Foundation

/// Records which workspace files this session has actually read, so a model-driven write or
/// patch can be refused when it would blind-overwrite a file the session never inspected. Also
/// hands out per-file locks so concurrent edits to the same file are serialized instead of
/// interleaved.
///
/// One instance is one "session" of file knowledge. `shared` is the process-wide session that
/// `ToolRouter` uses by default: the CLI runs one agent session per process, and the desktop
/// app's tool runs all share the app process. Tests inject a fresh instance for isolation.
public final class FileEditSessionGuard: @unchecked Sendable {
    public static let shared = FileEditSessionGuard()

    private let stateLock = NSLock()
    private var readKeys: Set<String> = []
    private var fileLocks: [String: NSLock] = [:]

    public init() {}

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
