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
            guard actions.count < maxActions,
                  !directory.contains("..")
            else {
                break
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
                guard actions.count < maxActions,
                      let action = action(root: root, directory: directory, fileURL: fileURL)
                else {
                    continue
                }
                actions.append(action)
            }
        }

        return actions
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
        return LocalEnvironmentAction(
            id: id,
            title: title(from: resolved.deletingPathExtension().lastPathComponent),
            relativePath: relativePath,
            command: "sh \(shellQuote(relativePath))"
        )
    }

    private static func title(from baseName: String) -> String {
        let words = baseName
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .map(String.init)
        guard !words.isEmpty else { return baseName }
        return words
            .map { word in
                guard let first = word.first else { return word }
                return first.uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
