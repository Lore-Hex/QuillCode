import Foundation

/// Shared workspace path-boundary checks used by every agent-facing path validator (the file tools,
/// the git tools, and `apply_patch`) so they all enforce the *same* sandbox: a lexical (`..`-resolved)
/// bound **plus** a symlink-resolved bound.
///
/// `standardizedFileURL` does not follow symbolic links, so the lexical check alone lets a symlink
/// inside the workspace — e.g. one the agent created with `ln -s` — point outside and let a write
/// escape. Every gate must also check the symlink-resolved path; centralizing it here keeps the
/// validators consistent rather than each re-deriving (and drifting on) the boundary.
public enum WorkspaceBoundary {
    public static func safeURL(_ path: String, root: URL) -> URL? {
        let standardizedRoot = root.standardizedFileURL
        let candidate = path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : standardizedRoot.appendingPathComponent(path)
        guard isWithin(candidate, root: standardizedRoot) else {
            return nil
        }
        return candidate.standardizedFileURL
    }

    public static func safeRelativePath(_ path: String, root: URL) -> String? {
        let standardizedRoot = root.standardizedFileURL
        guard let url = safeURL(path, root: standardizedRoot) else {
            return nil
        }
        if url.path == standardizedRoot.path {
            return "."
        }
        let rootPath = standardizedRoot.path.hasSuffix("/") ? standardizedRoot.path : "\(standardizedRoot.path)/"
        guard url.path.hasPrefix(rootPath) else {
            return nil
        }
        return String(url.path.dropFirst(rootPath.count))
    }

    /// Whether `candidate` resolves to a location inside (or equal to) `root`, enforcing both the
    /// lexical and the symlink-resolved boundary. Both sides are symlink-resolved for the second check
    /// because the workspace root itself is often a symlink on macOS (`/tmp` -> `/private/tmp`,
    /// `/var` -> `/private/var`), so an unresolved-vs-resolved mismatch is normal, not an escape.
    public static func isWithin(_ candidate: URL, root: URL) -> Bool {
        let standardized = candidate.standardizedFileURL
        guard isInside(standardized.path, root: root.standardizedFileURL.path) else { return false }
        return isInside(symlinkResolvedPath(standardized), root: root.resolvingSymlinksInPath().path)
    }

    /// True if `path` is `root` itself or lies under it. The trailing slash on `root` prevents a
    /// sibling like `/repo-evil` from matching `/repo`.
    public static func isInside(_ path: String, root: String) -> Bool {
        let rootPath = root.hasSuffix("/") ? root : "\(root)/"
        return path == root || path.hasPrefix(rootPath)
    }

    /// Resolves the symlinks in a URL's *existing* path components, then re-appends any trailing
    /// components that do not exist yet (a new file or directory being written). `resolvingSymlinksInPath`
    /// only follows symlinks for the portion of the path that exists, so for a not-yet-created target
    /// we resolve the deepest existing ancestor explicitly and append the remainder.
    public static func symlinkResolvedPath(_ url: URL) -> String {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            return url.resolvingSymlinksInPath().path
        }
        var existing = url.deletingLastPathComponent()
        var tail: [String] = [url.lastPathComponent]
        while existing.path != "/" && !fileManager.fileExists(atPath: existing.path) {
            tail.append(existing.lastPathComponent)
            existing = existing.deletingLastPathComponent()
        }
        var resolved = existing.resolvingSymlinksInPath()
        for component in tail.reversed() {
            resolved.appendPathComponent(component)
        }
        return resolved.standardizedFileURL.path
    }
}
