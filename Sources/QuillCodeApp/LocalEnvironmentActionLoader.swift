import Foundation
import QuillCodeCore

public enum LocalEnvironmentActionLoader {
    public static let defaultDirectories = [
        ".quillcode/actions",
        ".quillcode/local-env"
    ]

    public static let maxActions = 16
    private static let maxMetadataBytes = 16 * 1024

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
        let metadata = metadata(root: root, scriptURL: resolved)
        return LocalEnvironmentAction(
            id: id,
            title: metadata?.title ?? title(from: resolved.deletingPathExtension().lastPathComponent),
            detail: metadata?.description,
            relativePath: relativePath,
            command: "sh \(shellQuote(relativePath))",
            sortOrder: metadata?.order
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

    private static func metadata(root: URL, scriptURL: URL) -> ActionMetadata? {
        let metadataURL = scriptURL.deletingPathExtension().appendingPathExtension("json")
        let resolvedMetadataURL = metadataURL.standardizedFileURL.resolvingSymlinksInPath()
        guard resolvedMetadataURL.path.hasPrefix(root.path + "/"),
              resolvedMetadataURL.pathExtension == "json",
              let values = try? resolvedMetadataURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let size = values.fileSize,
              size <= maxMetadataBytes,
              let data = try? Data(contentsOf: resolvedMetadataURL),
              let decoded = try? JSONDecoder().decode(ActionMetadataFile.self, from: data)
        else {
            return nil
        }

        return ActionMetadata(
            title: normalized(decoded.title, maxLength: 80),
            description: normalized(decoded.description, maxLength: 200),
            order: decoded.order
        )
    }

    private static func normalized(_ value: String?, maxLength: Int) -> String? {
        guard let value else { return nil }
        let collapsed = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(maxLength))
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

    private struct ActionMetadataFile: Decodable {
        var title: String?
        var description: String?
        var order: Int?
    }

    private struct ActionMetadata {
        var title: String?
        var description: String?
        var order: Int?
    }
}
