import Foundation
import QuillCodeCore

public enum LocalEnvironmentActionLoader {
    public static let defaultDirectories = [
        ".quillcode/actions",
        ".quillcode/local-env"
    ]

    public static let maxActions = 16

    public static func load(
        from projectRoot: URL,
        directories: [String] = defaultDirectories,
        maxActions: Int = maxActions
    ) -> [LocalEnvironmentAction] {
        let root = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        var actions: [LocalEnvironmentAction] = []

        for directory in directories {
            guard !directory.contains("..")
            else {
                continue
            }

            let directoryURL = root
                .appendingPathComponent(directory)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            guard directoryURL.path.hasPrefix(root.path + "/") else {
                continue
            }

            let files = (try? FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for fileURL in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard let action = action(root: root, directory: directory, fileURL: fileURL)
                else {
                    continue
                }
                actions.append(action)
            }
        }

        return actions
            .sorted(by: sortActions)
            .prefix(maxActions)
            .map { $0 }
    }

    private static func action(root: URL, directory: String, fileURL: URL) -> LocalEnvironmentAction? {
        let resolved = fileURL.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.pathExtension == "sh",
              resolved.path.hasPrefix(root.path + "/")
        else {
            return nil
        }

        let relativePath = "\(directory)/\(resolved.lastPathComponent)"
        let id = "local-env:\(relativePath)"
        let metadata = ProjectScriptMetadataLoader.load(root: root, scriptURL: resolved)
        let environment = metadata?.environment ?? [:]
        let workingDirectory = metadata?.workingDirectory
        return LocalEnvironmentAction(
            id: id,
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

    private static func sortActions(_ lhs: LocalEnvironmentAction, _ rhs: LocalEnvironmentAction) -> Bool {
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
