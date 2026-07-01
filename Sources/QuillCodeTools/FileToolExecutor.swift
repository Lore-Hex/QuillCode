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

    public func read(path: String) -> ToolResult {
        do {
            let url = try resolve(path)
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else {
                throw FileToolError.invalidUTF8(path)
            }
            return ToolResult(ok: true, stdout: text, artifacts: [url.path])
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
            try content.write(to: url, atomically: true, encoding: .utf8)
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
