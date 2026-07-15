import Foundation
import QuillCodeCore

public struct FileWorkspacePathResolver: Sendable {
    public var workspaceRoot: URL
    public let accessScope: HostToolAccessScope

    public init(
        workspaceRoot: URL,
        accessScope: HostToolAccessScope = .workspaceOnly
    ) {
        self.workspaceRoot = workspaceRoot.standardizedFileURL
        self.accessScope = accessScope
    }

    public func resolve(_ path: String) throws -> URL {
        let candidate = candidateURL(for: path)
        guard accessScope.allowsPathsOutsideWorkspace
                || WorkspaceBoundary.isWithin(candidate, root: workspaceRoot)
        else {
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
        guard WorkspaceBoundary.isWithin(standardized, root: workspaceRoot) else {
            return standardized.path
        }
        let rootPath = workspaceRoot.path.hasSuffix("/") ? workspaceRoot.path : "\(workspaceRoot.path)/"
        let relative = String(standardized.path.dropFirst(rootPath.count))
        return relative.isEmpty ? "." : relative
    }

    func artifactPath(for displayedPath: String) -> String {
        if NSString(string: displayedPath).isAbsolutePath {
            return URL(fileURLWithPath: displayedPath).standardizedFileURL.path
        }
        return workspaceRoot.appendingPathComponent(displayedPath).standardizedFileURL.path
    }

    private func candidateURL(for path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return workspaceRoot.appendingPathComponent(path)
    }
}
