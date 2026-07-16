import Foundation
import QuillCodeCore

public struct PluginHookCatalogDiscovery: Sendable, Hashable {
    public var definitions: [HookCatalogDefinition]
    public var warnings: [String]

    public init(
        definitions: [HookCatalogDefinition] = [],
        warnings: [String] = []
    ) {
        self.definitions = definitions
        self.warnings = warnings
    }
}

/// Discovers plugin hook definitions without loading instructions or executing package code.
public enum CodexPluginHookConfigurationLoader {
    public static let maximumPackagesPerDirectory = 128
    public static let maximumManifestBytes = 100_000
    public static let maximumHookFileBytes = 100_000
    public static let maximumHooks = 192

    private static let manifestRelativePaths = [
        ".codex-plugin/plugin.json",
        ".claude-plugin/plugin.json"
    ]
    private static let defaultHooksRelativePath = "hooks/hooks.json"

    public static func discover(
        packageDirectories: [URL],
        scopeRoot: URL,
        trustScope: ProjectHookTrustScope = .workspace,
        maximumHooks: Int = maximumHooks
    ) -> PluginHookCatalogDiscovery {
        guard maximumHooks > 0 else { return PluginHookCatalogDiscovery() }
        let scopeRoot = scopeRoot.standardizedFileURL.resolvingSymlinksInPath()
        var result = PluginHookCatalogDiscovery()
        var seenPackages = Set<String>()

        for directory in packageDirectories {
            guard let directory = boundedDirectory(directory, inside: scopeRoot) else { continue }
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for packageRoot in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
                .prefix(maximumPackagesPerDirectory) {
                let canonicalPackage = packageRoot.standardizedFileURL.resolvingSymlinksInPath()
                guard seenPackages.insert(canonicalPackage.path).inserted else { continue }
                let remaining = maximumHooks - result.definitions.count
                guard remaining > 0 else { return result }
                let package = loadPackage(
                    at: packageRoot,
                    scopeRoot: scopeRoot,
                    trustScope: trustScope,
                    maximumHooks: remaining
                )
                result.definitions.append(contentsOf: package.definitions)
                result.warnings.append(contentsOf: package.warnings)
            }
        }
        return result
    }

    public static func loadPackage(
        at packageRoot: URL,
        scopeRoot: URL,
        pluginIdentifier: String? = nil,
        pluginName: String? = nil,
        trustScope: ProjectHookTrustScope = .workspace,
        maximumHooks: Int = maximumHooks
    ) -> PluginHookCatalogDiscovery {
        guard maximumHooks > 0 else { return PluginHookCatalogDiscovery() }
        let scopeRoot = scopeRoot.standardizedFileURL.resolvingSymlinksInPath()
        guard let packageRoot = boundedDirectory(packageRoot, inside: scopeRoot),
              let manifest = manifest(in: packageRoot)
        else { return PluginHookCatalogDiscovery() }

        guard let manifestData = boundedRegularFileData(
            at: manifest,
            maximumBytes: maximumManifestBytes
        ) else {
            return PluginHookCatalogDiscovery(warnings: [
                "failed to read plugin manifest: \(manifest.path)"
            ])
        }
        let manifestObject: [String: Any]
        do {
            guard let object = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any] else {
                throw PluginHookConfigurationError.invalidManifest
            }
            manifestObject = object
        } catch {
            return PluginHookCatalogDiscovery(warnings: [
                "failed to parse plugin manifest \(manifest.path): \(error.localizedDescription)"
            ])
        }

        guard let identifier = normalizedIdentifier(
            pluginIdentifier ?? manifestObject["name"] as? String
        ) else {
            return PluginHookCatalogDiscovery(warnings: [
                "plugin manifest has no valid name: \(manifest.path)"
            ])
        }
        let displayName = boundedText(pluginName, maximumCharacters: 120)
            ?? interfaceDisplayName(from: manifestObject)
            ?? identifier
        let sources = hookSources(
            from: manifestObject["hooks"],
            manifest: manifest,
            packageRoot: packageRoot
        )
        var result = PluginHookCatalogDiscovery(warnings: sources.warnings)
        let packageRelativePath = relativePath(of: packageRoot, inside: scopeRoot)

        for source in sources.values {
            let remaining = maximumHooks - result.definitions.count
            guard remaining > 0 else { break }
            let relativeSourcePath = relativePath(of: source.sourcePath, inside: scopeRoot)
                ?? source.keyPath
            let definitions: [HookCatalogDefinition]
            do {
                definitions = try CodexHookDefinitionLoader.validatedCatalogDefinitions(
                    fromJSON: source.data,
                    source: CodexHookDefinitionSource(
                        idPrefix: "plugin_hook:\(identifier)",
                        ownerID: "plugin:\(identifier)",
                        ownerName: displayName,
                        relativePath: relativeSourcePath,
                        pluginRootRelativePath: packageRelativePath,
                        trustScope: trustScope,
                        sourcePath: source.sourcePath,
                        catalogSource: .plugin,
                        keyPrefix: "\(identifier):\(source.keyPath)",
                        pluginIdentifier: identifier
                    ),
                    limit: remaining
                )
            } catch {
                result.warnings.append(
                    "failed to parse plugin hooks \(source.sourcePath.path): \(error.localizedDescription)"
                )
                continue
            }
            result.definitions.append(contentsOf: definitions)
            result.warnings.append(contentsOf: definitions.compactMap(unsupportedWarning))
        }
        return result
    }

    private struct HookSource {
        var keyPath: String
        var sourcePath: URL
        var data: Data
    }

    private struct HookSources {
        var values: [HookSource] = []
        var warnings: [String] = []
    }

    private static func hookSources(
        from reference: Any?,
        manifest: URL,
        packageRoot: URL
    ) -> HookSources {
        guard let reference else {
            return fileHookSources(
                paths: [defaultHooksRelativePath],
                packageRoot: packageRoot,
                reportMissing: false
            )
        }
        if let path = reference as? String {
            return fileHookSources(paths: [path], packageRoot: packageRoot, reportMissing: true)
        }
        if let paths = reference as? [String] {
            return fileHookSources(paths: paths, packageRoot: packageRoot, reportMissing: true)
        }
        if let object = reference as? [String: Any] {
            return inlineHookSources(objects: [object], manifest: manifest)
        }
        if let values = reference as? [Any],
           values.allSatisfy({ $0 is [String: Any] }) {
            return inlineHookSources(
                objects: values.compactMap { $0 as? [String: Any] },
                manifest: manifest
            )
        }
        return HookSources(warnings: [
            "plugin hooks must be a path, path array, hook object, or hook object array: \(manifest.path)"
        ])
    }

    private static func fileHookSources(
        paths: [String],
        packageRoot: URL,
        reportMissing: Bool
    ) -> HookSources {
        var result = HookSources()
        for path in paths.prefix(32) {
            guard let file = boundedFile(path, root: packageRoot) else {
                if reportMissing {
                    result.warnings.append("plugin hook file is missing or unsafe: \(path)")
                }
                continue
            }
            guard let data = boundedRegularFileData(at: file, maximumBytes: maximumHookFileBytes) else {
                result.warnings.append("failed to read plugin hook file: \(file.path)")
                continue
            }
            result.values.append(HookSource(
                keyPath: relativePath(of: file, inside: packageRoot) ?? path,
                sourcePath: file,
                data: data
            ))
        }
        return result
    }

    private static func inlineHookSources(
        objects: [[String: Any]],
        manifest: URL
    ) -> HookSources {
        var result = HookSources()
        for (index, object) in objects.prefix(32).enumerated() {
            guard JSONSerialization.isValidJSONObject(object),
                  let data = try? JSONSerialization.data(
                    withJSONObject: object,
                    options: [.sortedKeys]
                  ),
                  data.count <= maximumHookFileBytes
            else {
                result.warnings.append("invalid inline plugin hook at index \(index): \(manifest.path)")
                continue
            }
            result.values.append(HookSource(
                keyPath: "plugin.json#hooks[\(index)]",
                sourcePath: manifest,
                data: data
            ))
        }
        return result
    }

    private static func manifest(in packageRoot: URL) -> URL? {
        manifestRelativePaths.lazy.compactMap {
            boundedFile($0, root: packageRoot, maximumBytes: maximumManifestBytes)
        }.first
    }

    private static func boundedDirectory(_ candidate: URL, inside root: URL) -> URL? {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        let requested = candidate.standardizedFileURL
        let values = try? requested.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values?.isDirectory == true,
              values?.isSymbolicLink != true
        else { return nil }
        let resolved = requested.resolvingSymlinksInPath()
        guard resolved.path == requested.path,
              WorkspaceBoundary.isWithin(resolved, root: root)
        else { return nil }
        return resolved
    }

    private static func boundedFile(
        _ path: String,
        root: URL,
        maximumBytes: Int = maximumHookFileBytes
    ) -> URL? {
        guard let candidate = boundedURL(path, root: root),
              isBoundedRegularFile(candidate, maximumBytes: maximumBytes)
        else { return nil }
        return candidate
    }

    private static func boundedURL(_ rawPath: String, root: URL) -> URL? {
        var path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        while path.hasPrefix("./") { path.removeFirst(2) }
        guard !path.isEmpty,
              path.utf8.count <= 4_096,
              !NSString(string: path).isAbsolutePath,
              !path.contains("\0")
        else { return nil }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              let candidate = WorkspaceBoundary.safeURL(path, root: root)
        else { return nil }
        let resolved = candidate.resolvingSymlinksInPath()
        guard resolved.path == candidate.path,
              WorkspaceBoundary.isWithin(resolved, root: root)
        else { return nil }
        return resolved
    }

    private static func boundedRegularFileData(at file: URL, maximumBytes: Int) -> Data? {
        guard isBoundedRegularFile(file, maximumBytes: maximumBytes),
              let data = try? Data(contentsOf: file, options: [.mappedIfSafe]),
              data.count <= maximumBytes
        else { return nil }
        return data
    }

    private static func isBoundedRegularFile(_ file: URL, maximumBytes: Int) -> Bool {
        let values = try? file.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        )
        return values?.isRegularFile == true
            && values?.isSymbolicLink != true
            && (values?.fileSize ?? maximumBytes + 1) <= maximumBytes
    }

    private static func relativePath(of url: URL, inside root: URL) -> String? {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard WorkspaceBoundary.isInside(path, root: rootPath), path != rootPath else { return nil }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private static func normalizedIdentifier(_ value: String?) -> String? {
        guard let value = boundedText(value, maximumCharacters: 128) else { return nil }
        let normalized = value.lowercased().filter {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-")
        }
        return normalized.isEmpty ? nil : normalized
    }

    private static func interfaceDisplayName(from manifest: [String: Any]) -> String? {
        let interface = manifest["interface"] as? [String: Any]
        return boundedText(interface?["displayName"] as? String, maximumCharacters: 120)
    }

    private static func boundedText(_ value: String?, maximumCharacters: Int) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              !value.contains("\0"),
              value.count <= maximumCharacters
        else { return nil }
        return value
    }

    private static func unsupportedWarning(_ definition: HookCatalogDefinition) -> String? {
        guard !definition.hook.supportStatus.isSupported else { return nil }
        return "ignored unsupported plugin hook \(definition.key): "
            + definition.hook.supportStatus.rawValue
    }
}

private enum PluginHookConfigurationError: LocalizedError {
    case invalidManifest

    var errorDescription: String? {
        "plugin manifest must contain a JSON object"
    }
}
