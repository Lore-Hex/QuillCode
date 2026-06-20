import Foundation
import QuillCodeCore

public enum FileToolError: Error, CustomStringConvertible {
    case outsideWorkspace(String)
    case invalidUTF8(String)

    public var description: String {
        switch self {
        case .outsideWorkspace(let path):
            return "Path is outside the workspace: \(path)"
        case .invalidUTF8(let path):
            return "File is not valid UTF-8 text: \(path)"
        }
    }
}

public struct FileToolExecutor: Sendable {
    public var workspaceRoot: URL

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

    public func resolve(_ path: String) throws -> URL {
        let candidate: URL
        if path.hasPrefix("/") {
            candidate = URL(fileURLWithPath: path)
        } else {
            candidate = workspaceRoot.appendingPathComponent(path)
        }
        let standardized = candidate.standardizedFileURL
        let rootPath = workspaceRoot.path.hasSuffix("/") ? workspaceRoot.path : "\(workspaceRoot.path)/"
        guard standardized.path == workspaceRoot.path || standardized.path.hasPrefix(rootPath) else {
            throw FileToolError.outsideWorkspace(path)
        }
        return standardized
    }
}

public extension ToolDefinition {
    static let fileRead = ToolDefinition(
        name: "host.file.read",
        description: "Read a UTF-8 file inside the project workspace.",
        parametersJSON: #"{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}"#,
        host: .local,
        risk: .read
    )

    static let fileWrite = ToolDefinition(
        name: "host.file.write",
        description: "Write a UTF-8 file inside the project workspace.",
        parametersJSON: #"{"type":"object","properties":{"path":{"type":"string"},"content":{"type":"string"}},"required":["path","content"]}"#,
        host: .local,
        risk: .append
    )
}
