import Foundation

public enum ToolArtifactLocalPreviewAccess {
    public static func configure(projectRoots: [URL], readableProjectRoots: [URL]) {
        state.configure(
            ToolArtifactLocalPreviewAccessConfiguration(
                projectRoots: projectRoots,
                readableProjectRoots: readableProjectRoots
            )
        )
    }

    public static func permitsPreview(for value: String, kind: ToolArtifactKind) -> Bool {
        guard kind == .file, let path = localFilePath(for: value) else {
            return true
        }
        return state.permits(path: path)
    }

    static func reset() {
        state.configure(nil)
    }

    private static let state = State()

    private static func localFilePath(for value: String) -> String? {
        if value.hasPrefix("/") {
            return URL(fileURLWithPath: value).standardizedFileURL.path
        }
        guard let url = URL(string: value), url.isFileURL else { return nil }
        return url.standardizedFileURL.path
    }

    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var configuration: ToolArtifactLocalPreviewAccessConfiguration?

        func configure(_ configuration: ToolArtifactLocalPreviewAccessConfiguration?) {
            lock.lock()
            self.configuration = configuration
            lock.unlock()
        }

        func permits(path: String) -> Bool {
            lock.lock()
            let configuration = self.configuration
            lock.unlock()
            return configuration?.permits(path: path) ?? true
        }
    }
}

struct ToolArtifactLocalPreviewAccessConfiguration: Sendable {
    private let projectRootPaths: [String]
    private let readableProjectRootPaths: [String]

    init(projectRoots: [URL], readableProjectRoots: [URL]) {
        self.projectRootPaths = Self.paths(from: projectRoots)
        self.readableProjectRootPaths = Self.paths(from: readableProjectRoots)
    }

    func permits(path: String) -> Bool {
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        guard projectRootPaths.contains(where: { Self.contains(standardizedPath, root: $0) }) else {
            return true
        }
        return readableProjectRootPaths.contains(where: { Self.contains(standardizedPath, root: $0) })
    }

    private static func paths(from urls: [URL]) -> [String] {
        Array(Set(urls.map { $0.standardizedFileURL.path })).sorted()
    }

    private static func contains(_ path: String, root: String) -> Bool {
        path == root || path.hasPrefix(root == "/" ? root : root + "/")
    }
}
