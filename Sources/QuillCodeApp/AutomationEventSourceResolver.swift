import Foundation
import QuillCodeCore

enum AutomationEventSourceResolver {
    static func eventSource(
        for definition: QuillAutomationEventSource,
        project: ProjectRef?
    ) -> (any AutomationEventSource)? {
        switch definition.kind {
        case .fileChange:
            guard let url = fileChangeURL(for: definition.path, project: project) else {
                return nil
            }
            return FileChangeEventSource(path: url)
        case .directoryChange:
            guard let url = directoryChangeURL(for: definition.path, project: project) else {
                return nil
            }
            return DirectoryChangeEventSource(path: url)
        case .urlLastModified:
            guard let url = httpURL(for: definition.path) else {
                return nil
            }
            return URLLastModifiedEventSource(url: url)
        case .urlFeedUpdate:
            guard let url = httpURL(for: definition.path) else {
                return nil
            }
            return URLFeedUpdateEventSource(url: url)
        }
    }

    static func fileChangeURL(for path: String, project: ProjectRef?) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\0") else { return nil }

        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed).standardizedFileURL
        }

        guard let project, !project.isRemote else { return nil }
        let root = URL(fileURLWithPath: project.path).standardizedFileURL
        let candidate = root.appendingPathComponent(trimmed).standardizedFileURL
        guard isContained(candidate, inside: root) else { return nil }
        return candidate
    }

    static func directoryChangeURL(for path: String, project: ProjectRef?) -> URL? {
        fileChangeURL(for: path, project: project)
    }

    static func urlLastModifiedURL(for rawURL: String) -> URL? {
        httpURL(for: rawURL)
    }

    static func urlFeedUpdateURL(for rawURL: String) -> URL? {
        httpURL(for: rawURL)
    }

    private static func httpURL(for rawURL: String) -> URL? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\0"),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host?.isEmpty == false
        else {
            return nil
        }
        return url
    }

    private static func isContained(_ candidate: URL, inside root: URL) -> Bool {
        let rootPath = root.path
        let candidatePath = candidate.path
        if candidatePath == rootPath {
            return true
        }
        let prefix = rootPath.hasSuffix("/") ? rootPath : "\(rootPath)/"
        return candidatePath.hasPrefix(prefix)
    }
}
