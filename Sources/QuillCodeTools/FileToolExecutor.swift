import Foundation
import QuillCodeCore

public struct FileToolExecutor: Sendable {
    public var workspaceRoot: URL
    /// When set, `write` refuses to overwrite an existing file the session never read, rejects
    /// no-op writes, and serializes concurrent writes to the same file; `read` records the file
    /// in the session's read-set. When nil (the default), reads and writes are unguarded —
    /// direct programmatic use such as test fixtures. `ToolRouter` always injects a guard.
    public var editGuard: FileEditSessionGuard?

    private var pathResolver: FileWorkspacePathResolver {
        FileWorkspacePathResolver(workspaceRoot: workspaceRoot)
    }

    private var directoryLister: FileDirectoryLister {
        FileDirectoryLister(pathResolver: pathResolver)
    }

    private var searchScanner: FileSearchScanner {
        FileSearchScanner(pathResolver: pathResolver)
    }

    public init(workspaceRoot: URL, editGuard: FileEditSessionGuard? = nil) {
        self.workspaceRoot = workspaceRoot.standardizedFileURL
        self.editGuard = editGuard
    }

    public func read(path: String, offset: Int? = nil, limit: Int? = nil) -> ToolResult {
        do {
            let url = try resolve(path)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                return ToolResult(ok: false, error: missingFileMessage(for: url))
            }
            if isDirectory.boolValue {
                return ToolResult(
                    ok: false,
                    error: "\(pathResolver.relativePath(for: url)) is a directory, not a file. Use host.file.list to see its contents."
                )
            }
            let data = try Data(contentsOf: url)
            // Refuse binary/image content gracefully instead of erroring or dumping garbage into
            // context. The refusal must NOT count as a read: the session was never shown the
            // content, so it earns no write/patch rights over it.
            if FileReadRenderer.isProbablyBinary(data) {
                return ToolResult(
                    ok: true,
                    stdout: FileReadRenderer.binaryDescription(data, fileName: url.lastPathComponent),
                    artifacts: [url.path]
                )
            }
            let text = String(data: data, encoding: .utf8) ?? ""
            // Strip a leading BOM and normalize CRLF→LF so the numbered view is not polluted by a
            // U+FEFF on line 1 or a trailing `\r` on every line. The file on disk is untouched.
            let display = FileEncodingPreservation.normalizeForDisplay(text)
            // A partial (offset/limit) read counts as reading the file, but a window past the end
            // shows no content at all, so it must not mark either.
            if Self.windowShowsContent(display: display, offset: offset) {
                editGuard?.markRead(url)
            }
            return ToolResult(
                ok: true,
                stdout: FileReadRenderer.render(display, offset: offset, limit: limit),
                artifacts: [url.path]
            )
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    /// Whether a `[offset, …)` read window intersects the file at all — mirrors
    /// `FileReadRenderer.render`'s "offset is past the end" case.
    private static func windowShowsContent(display: String, offset: Int?) -> Bool {
        let start = max(1, offset ?? 1)
        guard start > 1 else { return true }
        var lines = display.isEmpty ? [] : display.components(separatedBy: "\n")
        if display.hasSuffix("\n"), lines.last == "" { lines.removeLast() }
        return start <= lines.count
    }

    public func write(path: String, content: String) -> ToolResult {
        do {
            let url = try resolve(path)
            guard let editGuard else {
                return try performWrite(content, to: url)
            }
            // The existence check, no-op check, and write happen under the per-file lock so a
            // concurrent edit to the same file cannot interleave with (or invalidate) them.
            return try editGuard.withExclusiveAccess(to: [url]) {
                let existing = try? Data(contentsOf: url)
                if FileManager.default.fileExists(atPath: url.path), !editGuard.hasRead(url) {
                    throw FileEditGuardError.writeWithoutRead(path)
                }
                if let existing, existing == encodedData(for: content, existing: existing) {
                    throw FileEditGuardError.noOpWrite(path)
                }
                let result = try performWrite(content, to: url, existing: existing)
                // The session wrote this exact content, so it now knows the file.
                editGuard.markRead(url)
                return result
            }
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    private func performWrite(_ content: String, to url: URL, existing: Data? = nil) throws -> ToolResult {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = encodedData(for: content, existing: existing ?? (try? Data(contentsOf: url)))
        try data.write(to: url, options: .atomic)
        return ToolResult(ok: true, stdout: "Wrote \(url.path)\n", artifacts: [url.path])
    }

    /// Preserve the existing file's BOM + line-ending style so a content edit doesn't silently
    /// rewrite every line. A new file gets the default (bare UTF-8, LF, no BOM).
    private func encodedData(for content: String, existing: Data?) -> Data {
        let style = existing.map(FileEncodingPreservation.detect) ?? .default
        return FileEncodingPreservation.apply(content, style: style)
    }

    public func list(path: String = ".", includeHidden: Bool = false, maxEntries: Int? = nil) -> ToolResult {
        do {
            let result = try directoryLister.list(
                path: path,
                includeHidden: includeHidden,
                maxEntries: maxEntries
            )
            return ToolResult(
                ok: true,
                stdout: encode(result.output),
                artifacts: result.artifacts
            )
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func search(query: String, path: String = ".", maxResults: Int? = nil) -> ToolResult {
        do {
            let result = try searchScanner.search(query: query, path: path, maxResults: maxResults)
            return ToolResult(
                ok: true,
                stdout: encode(result.output),
                artifacts: result.artifacts
            )
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func resolve(_ path: String) throws -> URL {
        try pathResolver.resolve(path)
    }

    /// A missing-file error the model can act on in one glance: the workspace-relative path plus
    /// "did you mean" siblings when the name looks like a typo of something that exists.
    private func missingFileMessage(for url: URL) -> String {
        let relative = pathResolver.relativePath(for: url)
        let parent = url.deletingLastPathComponent()
        // Suggestions enumerate the parent directory, so the parent itself must be inside the
        // workspace. When the missing path IS the workspace root (deleted or misconfigured), its
        // parent lies outside the boundary and sibling names there must not leak into the error.
        guard WorkspaceBoundary.isWithin(parent, root: workspaceRoot) else {
            return "File not found: \(relative)"
        }
        let matches = FilePathSuggester.suggest(missingFileAt: url)
        guard !matches.isEmpty else {
            return "File not found: \(relative)"
        }
        let parentRelative = pathResolver.relativePath(for: parent)
        let prefix = parentRelative == "." ? "" : "\(parentRelative)/"
        let hints = matches.map { "\(prefix)\($0)" }.joined(separator: ", ")
        return "File not found: \(relative). Did you mean: \(hints)?"
    }

    private func encode<T: Encodable>(_ output: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(output) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }
}
