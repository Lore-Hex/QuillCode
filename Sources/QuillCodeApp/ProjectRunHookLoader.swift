import Foundation
import QuillCodeCore

public enum ProjectRunHookLoader {
    public static let defaultBeforeAgentRunDirectories = [
        ".quillcode/hooks/before-agent-run"
    ]
    public static let defaultAfterAgentRunDirectories = [
        ".quillcode/hooks/after-agent-run"
    ]
    public static let maxHooks = 8

    public static func load(
        from projectRoot: URL,
        beforeAgentRunDirectories: [String] = defaultBeforeAgentRunDirectories,
        afterAgentRunDirectories: [String] = defaultAfterAgentRunDirectories,
        maxHooks: Int = maxHooks
    ) -> [ProjectRunHook] {
        let root = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        let specs: [(ProjectRunHookTiming, [String])] = [
            (.beforeAgentRun, beforeAgentRunDirectories),
            (.afterAgentRun, afterAgentRunDirectories)
        ]
        var hooks: [ProjectRunHook] = []
        for (timing, directories) in specs {
            for directory in directories {
                hooks.append(contentsOf: load(timing: timing, root: root, directory: directory))
            }
        }
        return hooks
            .sorted(by: sortHooks)
            .prefix(maxHooks)
            .map { $0 }
    }

    private static func load(
        timing: ProjectRunHookTiming,
        root: URL,
        directory: String
    ) -> [ProjectRunHook] {
        guard !directory.contains("..") else { return [] }
        let directoryURL = root
            .appendingPathComponent(directory)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard directoryURL.path.hasPrefix(root.path + "/") else {
            return []
        }

        let files = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return files
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            .compactMap { hook(timing: timing, root: root, directory: directory, fileURL: $0) }
    }

    private static func hook(
        timing: ProjectRunHookTiming,
        root: URL,
        directory: String,
        fileURL: URL
    ) -> ProjectRunHook? {
        let resolved = fileURL.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.pathExtension == "sh",
              resolved.path.hasPrefix(root.path + "/")
        else {
            return nil
        }

        let relativePath = "\(directory)/\(resolved.lastPathComponent)"
        let metadata = ProjectScriptMetadataLoader.load(root: root, scriptURL: resolved)
        let environment = metadata?.environment ?? [:]
        let workingDirectory = metadata?.workingDirectory
        return ProjectRunHook(
            id: "\(timing.rawValue):\(relativePath)",
            timing: timing,
            title: metadata?.title ?? ProjectScriptMetadataLoader.title(
                from: resolved.deletingPathExtension().lastPathComponent
            ),
            detail: metadata?.description,
            relativePath: relativePath,
            command: ProjectScriptMetadataLoader.shellScriptCommand(
                relativePath: relativePath,
                workingDirectory: workingDirectory
            ),
            sortOrder: metadata?.order,
            environment: environment.isEmpty ? nil : environment,
            workingDirectory: workingDirectory,
            timeoutSeconds: metadata?.timeoutSeconds
        )
    }

    private static func sortHooks(_ lhs: ProjectRunHook, _ rhs: ProjectRunHook) -> Bool {
        if lhs.timing != rhs.timing {
            return lhs.timing == .beforeAgentRun
        }
        switch (lhs.sortOrder, rhs.sortOrder) {
        case let (left?, right?) where left != right:
            return left < right
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        default:
            return lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
        }
    }
}
