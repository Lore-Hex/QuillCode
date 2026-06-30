import Foundation
import QuillCodeCore

public struct FileWorkspacePathResolver: Sendable {
    public var workspaceRoot: URL

    public init(workspaceRoot: URL) {
        self.workspaceRoot = workspaceRoot.standardizedFileURL
    }

    public func resolve(_ path: String) throws -> URL {
        let candidate = candidateURL(for: path)
        guard WorkspaceBoundary.isWithin(candidate, root: workspaceRoot) else {
            throw FileToolError.outsideWorkspace(path)
        }
        return candidate.standardizedFileURL
    }

    func normalizedDirectoryPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "." : trimmed
    }

    func relativePath(for url: URL) -> String {
        let standardized = url.standardizedFileURL
        let rootPath = workspaceRoot.path.hasSuffix("/") ? workspaceRoot.path : "\(workspaceRoot.path)/"
        guard standardized.path.hasPrefix(rootPath) else {
            return "."
        }
        let relative = String(standardized.path.dropFirst(rootPath.count))
        return relative.isEmpty ? "." : relative
    }

    private func candidateURL(for path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return workspaceRoot.appendingPathComponent(path)
    }
}
