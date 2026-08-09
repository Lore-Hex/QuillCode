import Foundation
import QuillCodeCore

public struct FileToolExecutor: Sendable {
    public var workspaceRoot: URL
    public let accessScope: HostToolAccessScope
    /// When set, `write` refuses to overwrite an existing file the session never read, rejects
    /// no-op edits to files the session only read, and serializes concurrent writes to the same
    /// file. Replaying content this session already wrote is an idempotent success. When nil (the
    /// default), reads and writes are unguarded — direct programmatic use such as test fixtures.
    /// `ToolRouter` always injects a guard.
    public var editGuard: FileEditSessionGuard?

    private var pathResolver: FileWorkspacePathResolver {
        FileWorkspacePathResolver(workspaceRoot: workspaceRoot, accessScope: accessScope)
    }

    private var directoryLister: FileDirectoryLister {
        FileDirectoryLister(pathResolver: pathResolver)
    }

    private var searchScanner: FileSearchScanner {
        FileSearchScanner(pathResolver: pathResolver)
    }

    public init(
        workspaceRoot: URL,
        accessScope: HostToolAccessScope = .workspaceOnly,
        editGuard: FileEditSessionGuard? = nil
    ) {
        self.workspaceRoot = workspaceRoot.standardizedFileURL
        self.accessScope = accessScope
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
                    error: "\(pathResolver.relativePath(for: url)) is a directory, not a file. "
                        + "Use host.file.list to see its contents."
                )
            }
            let data = try FileSystemIO.readFile(at: url)
            // Rich formats are selected by their declared file type, not by whether their bytes
            // happen to decode as UTF-8. Small, valid PDFs can be entirely ASCII; treating those
            // as text would dump PDF object streams into the model context instead of page text.
            if let extracted = RichDocumentTextExtractor.extract(from: url) {
                if Self.windowShowsContent(display: extracted, offset: offset) {
                    editGuard?.markRead(url)
                }
                return ToolResult(
                    ok: true,
                    stdout: FileReadRenderer.render(extracted, offset: offset, limit: limit),
                    artifacts: [url.path]
                )
            }
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
            try validateStructuredContent(content, for: url)
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
                    if editGuard.hasWritten(url) {
                        return ToolResult(
                            ok: true,
                            stdout: "Already up to date \(url.path)\n",
                            artifacts: [url.path]
                        )
                    }
                    throw FileEditGuardError.noOpWrite(path)
                }
                let result = try performWrite(content, to: url, existing: existing)
                // The session wrote this exact content, so it now knows the file.
                editGuard.markWritten(url)
                return result
            }
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    private func validateStructuredContent(_ content: String, for url: URL) throws {
        guard url.pathExtension.caseInsensitiveCompare("csv") == .orderedSame,
              !content.isEmpty else { return }
        try CSVContentValidator.validate(content)
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
        let relative = Self.displayPath(pathResolver.relativePath(for: url))
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
        let parentRelative = Self.displayPath(pathResolver.relativePath(for: parent))
        let prefix = parentRelative == "." ? "" : "\(parentRelative)/"
        let hints = matches.map { Self.displayPath("\(prefix)\($0)") }.joined(separator: ", ")
        return "File not found: \(relative). Did you mean: \(hints)?"
    }

    private static func displayPath(_ path: String) -> String {
        let sanitized = path.unicodeScalars
            .map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }
            .joined()
        guard sanitized.count > 240 else { return sanitized }
        let end = sanitized.index(sanitized.startIndex, offsetBy: 240)
        return String(sanitized[..<end]) + "..."
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

private enum CSVValidationError: Error, CustomStringConvertible {
    case unexpectedQuote(row: Int, column: Int)
    case unexpectedCharacterAfterQuote(row: Int, column: Int)
    case unterminatedQuote(row: Int, column: Int)
    case inconsistentWidth(row: Int, actual: Int, expected: Int)

    var description: String {
        let repair = "Quote fields containing commas, quotes, or newlines and retry."
        switch self {
        case .unexpectedQuote(let row, let column):
            return "Invalid CSV: unexpected quote in row \(row), column \(column). \(repair)"
        case .unexpectedCharacterAfterQuote(let row, let column):
            return "Invalid CSV: unexpected character after a closing quote in row \(row), column \(column). \(repair)"
        case .unterminatedQuote(let row, let column):
            return "Invalid CSV: unterminated quoted field in row \(row), column \(column). \(repair)"
        case .inconsistentWidth(let row, let actual, let expected):
            return "Invalid CSV: row \(row) has \(actual) columns; the header has \(expected). \(repair)"
        }
    }
}

private enum CSVContentValidator {
    private enum FieldState {
        case start
        case unquoted
        case quoted
        case closedQuote
    }

    static func validate(_ content: String) throws {
        let characters = Array(content)
        var index = 0
        var row = 1
        var column = 1
        var columnsInRow = 1
        var expectedColumns: Int?
        var state = FieldState.start
        var rowHasContent = false

        func validateWidth() throws {
            guard rowHasContent else { return }
            if let expectedColumns, columnsInRow != expectedColumns {
                throw CSVValidationError.inconsistentWidth(
                    row: row,
                    actual: columnsInRow,
                    expected: expectedColumns
                )
            }
            if expectedColumns == nil {
                expectedColumns = columnsInRow
            }
        }

        func finishRow() throws {
            try validateWidth()
            row += 1
            column = 1
            columnsInRow = 1
            state = .start
            rowHasContent = false
        }

        while index < characters.count {
            let character = characters[index]
            switch state {
            case .quoted:
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        index += 1
                    } else {
                        state = .closedQuote
                    }
                }
            case .closedQuote:
                if character == "," {
                    columnsInRow += 1
                    column += 1
                    state = .start
                } else if character == "\n" || character == "\r" {
                    try finishRow()
                    if character == "\r", index + 1 < characters.count,
                       characters[index + 1] == "\n" {
                        index += 1
                    }
                } else {
                    throw CSVValidationError.unexpectedCharacterAfterQuote(row: row, column: column)
                }
            case .start:
                if character == "\"" {
                    state = .quoted
                    rowHasContent = true
                } else if character == "," {
                    columnsInRow += 1
                    column += 1
                    rowHasContent = true
                } else if character == "\n" || character == "\r" {
                    try finishRow()
                    if character == "\r", index + 1 < characters.count,
                       characters[index + 1] == "\n" {
                        index += 1
                    }
                } else {
                    state = .unquoted
                    rowHasContent = true
                }
            case .unquoted:
                if character == "\"" {
                    throw CSVValidationError.unexpectedQuote(row: row, column: column)
                } else if character == "," {
                    columnsInRow += 1
                    column += 1
                    state = .start
                } else if character == "\n" || character == "\r" {
                    try finishRow()
                    if character == "\r", index + 1 < characters.count,
                       characters[index + 1] == "\n" {
                        index += 1
                    }
                }
            }
            index += 1
        }

        if state == .quoted {
            throw CSVValidationError.unterminatedQuote(row: row, column: column)
        }
        try validateWidth()
    }
}
