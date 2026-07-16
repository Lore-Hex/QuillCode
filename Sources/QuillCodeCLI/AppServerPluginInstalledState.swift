import Foundation
import QuillCodeCore
import QuillCodeTools

struct AppServerInstalledPluginState: Sendable, Equatable {
    var version: String?
    var enabled: Bool
}

enum AppServerInstalledPluginStateLoader {
    private static let maximumManifestBytes = 20_000
    private static let maximumEntriesPerDirectory = 256

    static func load(roots: [URL], quillCodeHome: URL) -> [String: AppServerInstalledPluginState] {
        let home = quillCodeHome.standardizedFileURL.resolvingSymlinksInPath()
        var result: [String: AppServerInstalledPluginState] = [:]
        var seenDirectories = Set<String>()

        for package in CodexInstalledPluginStore.packages(in: home) {
            result[package.pluginName] = AppServerInstalledPluginState(
                version: package.metadata.version,
                enabled: true
            )
        }

        for root in canonicalRoots(roots) {
            let directories = pluginDirectories(for: root, home: home)
            for directory in directories where seenDirectories.insert(directory.path).inserted {
                let local = states(in: directory, root: root)
                for (name, state) in local {
                    if let existing = result[name] {
                        result[name] = AppServerInstalledPluginState(
                            version: existing.version ?? state.version,
                            enabled: existing.enabled || state.enabled
                        )
                    } else {
                        result[name] = state
                    }
                }
            }
        }
        return result
    }

    private static func canonicalRoots(_ roots: [URL]) -> [URL] {
        var seen = Set<String>()
        return roots.compactMap { value in
            let root = value.standardizedFileURL.resolvingSymlinksInPath()
            return seen.insert(root.path).inserted ? root : nil
        }
    }

    private static func pluginDirectories(for root: URL, home: URL) -> [URL] {
        let relativePaths = root.path == home.path
            ? ["plugins", ".quillcode/plugins"]
            : [".quillcode/plugins"]
        return relativePaths.compactMap { WorkspaceBoundary.safeURL($0, root: root) }
    }

    private static func states(
        in directory: URL,
        root: URL
    ) -> [String: AppServerInstalledPluginState] {
        let directoryValues = try? directory.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard directoryValues?.isDirectory == true,
              directoryValues?.isSymbolicLink != true,
              WorkspaceBoundary.isWithin(directory, root: root)
        else { return [:] }

        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [
                .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey
            ],
            options: [.skipsHiddenFiles]
        )) ?? []
        var result: [String: AppServerInstalledPluginState] = [:]

        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            .prefix(maximumEntriesPerDirectory) {
            let values = try? entry.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            )
            guard values?.isSymbolicLink != true else { continue }

            if values?.isDirectory == true,
               let package = CodexPluginMarketplaceCatalogLoader.loadPackageMetadata(at: entry),
               let name = normalizedPluginName(package.name) {
                result[name] = AppServerInstalledPluginState(
                    version: package.version,
                    enabled: true
                )
            }
        }

        // Explicit manifests are project policy and therefore override package defaults in the
        // same directory. This mirrors the desktop loader's direct-manifest precedence.
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            .prefix(maximumEntriesPerDirectory) where entry.pathExtension == "json" {
            guard let payload = manifestPayload(at: entry),
                  let name = normalizedPluginName(payload.id ?? payload.name)
            else { continue }
            result[name] = AppServerInstalledPluginState(
                version: boundedText(payload.version, maximumLength: 80),
                enabled: payload.enabled ?? true
            )
        }
        return result
    }

    private static func manifestPayload(at path: URL) -> InstalledManifestPayload? {
        let values = try? path.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        )
        guard values?.isRegularFile == true,
              values?.isSymbolicLink != true,
              (values?.fileSize ?? 0) <= maximumManifestBytes,
              let data = try? Data(contentsOf: path),
              data.count <= maximumManifestBytes
        else { return nil }
        return try? JSONDecoder().decode(InstalledManifestPayload.self, from: data)
    }

    private static func normalizedPluginName(_ value: String?) -> String? {
        guard var result = boundedText(value, maximumLength: 160)?.lowercased() else { return nil }
        if result.hasPrefix("plugin:") { result.removeFirst("plugin:".count) }
        if let separator = result.firstIndex(of: "@") {
            result = String(result[..<separator])
        }
        guard !result.isEmpty,
              result.count <= 128,
              result.allSatisfy({
                  $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-")
              })
        else { return nil }
        return result
    }

    private static func boundedText(_ value: String?, maximumLength: Int) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              !text.contains("\0"),
              text.count <= maximumLength
        else { return nil }
        return text
    }
}

private struct InstalledManifestPayload: Decodable {
    var id: String?
    var name: String?
    var version: String?
    var enabled: Bool?
}
