import Foundation
import QuillCodeCore

public enum ProjectExtensionManifestLoader {
    public static let defaultDirectories: [(relativePath: String, kind: ProjectExtensionKind)] = [
        (".quillcode/plugins", .plugin),
        (".quillcode/skills", .skill),
        (".quillcode/mcp", .mcpServer)
    ]

    public static let maxManifests = 48
    public static let maxManifestBytes = 20_000

    public static func load(
        from projectRoot: URL,
        directories: [(relativePath: String, kind: ProjectExtensionKind)] = defaultDirectories,
        maxManifests: Int = maxManifests,
        maxManifestBytes: Int = maxManifestBytes
    ) -> [ProjectExtensionManifest] {
        let root = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        var manifests: [ProjectExtensionManifest] = []
        var seenIDs = Set<String>()

        for directory in directories {
            guard manifests.count < maxManifests,
                  !directory.relativePath.contains("..")
            else {
                break
            }

            let directoryURL = root
                .appendingPathComponent(directory.relativePath)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            guard directoryURL.path.hasPrefix(root.path + "/") else {
                continue
            }

            let files = (try? FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for fileURL in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard manifests.count < maxManifests,
                      let manifest = manifest(
                        root: root,
                        directory: directory.relativePath,
                        kind: directory.kind,
                        fileURL: fileURL,
                        maxManifestBytes: maxManifestBytes
                      ),
                      !seenIDs.contains(manifest.id)
                else {
                    continue
                }
                seenIDs.insert(manifest.id)
                manifests.append(manifest)
            }
        }

        return manifests
    }

    private static func manifest(
        root: URL,
        directory: String,
        kind: ProjectExtensionKind,
        fileURL: URL,
        maxManifestBytes: Int
    ) -> ProjectExtensionManifest? {
        guard maxManifestBytes > 0,
              fileURL.pathExtension == "json"
        else {
            return nil
        }

        let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values?.isRegularFile == true,
              values?.isSymbolicLink != true,
              (values?.fileSize ?? 0) <= maxManifestBytes
        else {
            return nil
        }

        let resolved = fileURL.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(root.path + "/") else {
            return nil
        }

        guard let data = try? Data(contentsOf: resolved),
              data.count <= maxManifestBytes,
              let payload = try? JSONDecoder().decode(ManifestPayload.self, from: data)
        else {
            return nil
        }

        let manifestID = payload.normalizedID
        guard !manifestID.isEmpty else {
            return nil
        }

        let relativePath = "\(directory)/\(resolved.lastPathComponent)"
        let title = payload.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = title?.isEmpty == false
            ? title!
            : displayName(from: resolved.deletingPathExtension().lastPathComponent)
        return ProjectExtensionManifest(
            id: "\(kind.rawValue):\(manifestID)",
            kind: kind,
            name: name,
            summary: payload.summaryText,
            relativePath: relativePath,
            isEnabled: payload.enabled ?? true,
            transport: payload.transportKind(for: kind),
            launchExecutable: payload.launchExecutable,
            launchCommand: payload.launchCommand,
            launchArguments: payload.launchArguments
        )
    }

    private static func displayName(from baseName: String) -> String {
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
}

private struct ManifestPayload: Decodable {
    var id: String?
    var name: String?
    var description: String?
    var summary: String?
    var enabled: Bool?
    var command: String?
    var args: [String]?
    var transport: String?

    var normalizedID: String {
        (id ?? name ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-" }
    }

    var summaryText: String {
        let text = summary ?? description ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var launchCommand: String? {
        guard let command = launchExecutable
        else {
            return nil
        }
        let args = (args ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !args.isEmpty else {
            return command
        }
        return ([command] + args).joined(separator: " ")
    }

    var launchExecutable: String? {
        guard let command = command?.trimmingCharacters(in: .whitespacesAndNewlines),
              !command.isEmpty
        else {
            return nil
        }
        return command
    }

    var launchArguments: [String]? {
        let args = (args ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return args.isEmpty ? nil : args
    }

    func transportKind(for kind: ProjectExtensionKind) -> ProjectExtensionTransport? {
        if let transport = transport?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           let parsed = ProjectExtensionTransport(rawValue: transport) {
            return parsed
        }
        return kind == .mcpServer && launchCommand != nil ? .stdio : nil
    }
}
