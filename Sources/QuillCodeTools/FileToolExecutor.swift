import Foundation
import QuillCodeCore

public struct FileToolExecutor: Sendable {
    public var workspaceRoot: URL

    private var pathResolver: FileWorkspacePathResolver {
        FileWorkspacePathResolver(workspaceRoot: workspaceRoot)
    }

    private var directoryLister: FileDirectoryLister {
        FileDirectoryLister(pathResolver: pathResolver)
    }

    private var searchScanner: FileSearchScanner {
        FileSearchScanner(pathResolver: pathResolver)
    }

    public init(workspaceRoot: URL) {
        self.workspaceRoot = workspaceRoot.standardizedFileURL
    }

    public func read(path: String, offset: Int? = nil, limit: Int? = nil) -> ToolResult {
        do {
            let url = try resolve(path)
            let data = try Data(contentsOf: url)
            // Refuse binary/image content gracefully instead of erroring or dumping garbage into context.
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
            return ToolResult(
                ok: true,
                stdout: FileReadRenderer.render(display, offset: offset, limit: limit),
                artifacts: [url.path]
            )
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func write(path: String, content: String) -> ToolResult {
        do {
            let url = try resolve(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // Preserve the existing file's BOM + line-ending style so a content edit doesn't silently
            // rewrite every line. A new file gets the default (bare UTF-8, LF, no BOM).
            let style = (try? Data(contentsOf: url)).map(FileEncodingPreservation.detect) ?? .default
            let data = FileEncodingPreservation.apply(content, style: style)
            try data.write(to: url, options: .atomic)
            return ToolResult(ok: true, stdout: "Wrote \(url.path)\n", artifacts: [url.path])
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
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

    private func encode<T: Encodable>(_ output: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(output) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }
}
