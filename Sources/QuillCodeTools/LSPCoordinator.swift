import Foundation

/// The outcome of the post-write LSP pass: an optional notice to append to the write result's
/// `stdout` (diagnostics and/or a format notice, or a one-time "server unavailable"), and whether the
/// on-disk file was rewritten by formatting.
public struct LSPWriteFeedback: Sendable, Equatable {
    /// Text to append to the tool result, or `nil` when there is nothing to say.
    public var notice: String?
    /// True when format-on-save rewrote the file (so the caller can refresh its read-set snapshot).
    public var didFormat: Bool

    public init(notice: String? = nil, didFormat: Bool = false) {
        self.notice = notice
        self.didFormat = didFormat
    }

    static let empty = LSPWriteFeedback()
}

/// Drives the two write-triggered LSP behaviors and backs the `host.lsp.*` navigation tool. Holds an
/// `LSPSessionManager`, so a single coordinator serves an entire workspace across many tool steps.
///
/// Every entry point is failure-tolerant: an unavailable/slow/crashed server yields empty feedback
/// (writes proceed untouched) rather than an error. Format-on-save is off by default and, when on,
/// is crash-safe — a formatting failure keeps the original file.
public final class LSPCoordinator: @unchecked Sendable {
    private let workspaceRoot: URL
    private let sessions: LSPSessionManager
    /// Auto-format on save. Opt-in: `false` never touches file contents.
    private let formatOnSave: Bool
    /// How long to wait for diagnostics to settle after a save before reporting them.
    private let diagnosticsWait: TimeInterval

    public init(
        workspaceRoot: URL,
        sessions: LSPSessionManager? = nil,
        formatOnSave: Bool = false,
        diagnosticsWait: TimeInterval = 1.5
    ) {
        self.workspaceRoot = workspaceRoot.standardizedFileURL
        self.sessions = sessions ?? LSPSessionManager(workspaceRoot: workspaceRoot)
        self.formatOnSave = formatOnSave
        self.diagnosticsWait = diagnosticsWait
    }

    /// Runs format-on-save (if enabled) then collects project-wide diagnostics for the file(s) just
    /// written. `paths` are absolute paths inside the workspace. Never throws.
    public func afterWrite(paths: [URL]) -> LSPWriteFeedback {
        let supported = paths.filter { sessions.hasServer(forPath: $0.path) }
        guard let primary = supported.first else {
            return .empty
        }

        guard let client = sessions.client(forPath: primary.path) else {
            // Server missing/disabled: emit the one-time notice (once per workspace run) and no-op.
            let notice = sessions.consumeUnavailableNoticeIfNeeded(forPath: primary.path)
            return LSPWriteFeedback(notice: notice)
        }

        var notices: [String] = []
        var didFormat = false

        for url in supported {
            guard let languageID = sessions.languageID(forPath: url.path) else { continue }

            // Format first so diagnostics reflect the formatted text the model will see.
            if formatOnSave, client.supportsFormatting {
                if let formatNotice = formatFile(url, client: client, languageID: languageID) {
                    notices.append(formatNotice)
                    didFormat = true
                }
            }

            // Sync the (possibly reformatted) content to the server and prompt a diagnostics pass.
            syncDocument(url, client: client, languageID: languageID)
        }

        // Let the server settle, then collect project-wide diagnostics capped at ≤5 files.
        _ = client.diagnostics(for: primary.path, waitFor: diagnosticsWait)
        let diagnostics = client.allDiagnostics()
        if let block = LSPDiagnosticsFormatter.format(
            diagnosticsByPath: diagnostics,
            workspaceRoot: workspaceRoot,
            editedPath: primary.path
        ) {
            notices.append(block)
        }

        let notice = notices.isEmpty ? nil : notices.joined(separator: "\n\n")
        return LSPWriteFeedback(notice: notice, didFormat: didFormat)
    }

    /// The navigation tool's client + language for a path, or `nil` if unsupported/unavailable.
    func navigationClient(forPath path: String) -> (client: LSPClient, languageID: String)? {
        guard let languageID = sessions.languageID(forPath: path),
              let client = sessions.client(forPath: path)
        else { return nil }
        // Make sure the server knows the file before a position-based request.
        if let text = try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8) {
            try? client.didOpen(path: path, text: text, languageID: languageID)
        }
        return (client, languageID)
    }

    public func shutdown() { sessions.shutdown() }

    // MARK: Private

    private func syncDocument(_ url: URL, client: LSPClient, languageID: String) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        try? client.didOpen(path: url.path, text: text, languageID: languageID)
        try? client.didSave(path: url.path)
    }

    /// Formats one file crash-safely: request edits, apply them in-memory, and only write when the
    /// result is a non-empty, changed, valid string. Any failure (server error, malformed edits,
    /// empty output) leaves the file exactly as written. Returns a notice when the file changed.
    private func formatFile(_ url: URL, client: LSPClient, languageID: String) -> String? {
        guard let originalData = try? Data(contentsOf: url),
              let original = String(data: originalData, encoding: .utf8)
        else { return nil }
        // The server needs the current text before it can format it.
        try? client.didOpen(path: url.path, text: original, languageID: languageID)

        let edits: [LSPTextEdit]
        do {
            edits = try client.formatting(path: url.path)
        } catch {
            return nil // server error/timeout: keep original
        }
        guard !edits.isEmpty,
              let formatted = LSPEditApplier.apply(edits, to: original),
              !formatted.isEmpty,
              formatted != original
        else { return nil }

        // Preserve the file's existing BOM + line-ending style so formatting a CRLF/BOM file does not
        // silently rewrite every line to bare UTF-8/LF — the same guarantee host.file.write gives.
        let style = FileEncodingPreservation.detect(originalData)
        let encoded = FileEncodingPreservation.apply(formatted, style: style)
        // A no-op after re-encoding (formatting only changed the LF style we just restored) is not a
        // real change — skip the write and the notice.
        guard encoded != originalData else { return nil }

        // Never truncate: an atomic write means readers see either the old or the new file, never a
        // partial one. A write failure leaves the original in place.
        do {
            try encoded.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        let relative = LSPDiagnosticsRelativePath.of(url.path, workspaceRoot: workspaceRoot)
        return "Auto-formatted \(relative) on save."
    }
}

/// Small shared relative-path helper (the formatter has its own private copy; this keeps the
/// coordinator from importing it privately across files).
enum LSPDiagnosticsRelativePath {
    static func of(_ path: String, workspaceRoot: URL) -> String {
        let root = workspaceRoot.standardizedFileURL.path
        let prefix = root.hasSuffix("/") ? root : "\(root)/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }
}
