import Foundation
import QuillCodeCore

/// Reads plugin capability metadata without loading instructions or executing package code.
public enum CodexPluginPackageDetailLoader {
    public static let maximumComponentFileBytes = 100_000
    public static let maximumComponentsPerKind = 128

    private static let manifestPaths = [
        ".codex-plugin/plugin.json",
        ".claude-plugin/plugin.json"
    ]
    private static let defaultSkillsPath = "skills"
    private static let defaultHooksPath = "hooks/hooks.json"
    private static let defaultAppsPath = ".app.json"
    private static let defaultMCPPath = ".mcp.json"

    public static func load(
        at pluginRoot: URL,
        pluginIdentifier: String,
        maximumManifestBytes: Int = CodexPluginMarketplaceCatalogLoader.maximumPackageManifestBytes,
        maximumComponentFileBytes: Int = maximumComponentFileBytes
    ) -> CodexPluginPackageDetail? {
        guard maximumManifestBytes > 0,
              maximumComponentFileBytes > 0,
              isBoundedPluginIdentifier(pluginIdentifier)
        else { return nil }

        let requestedRoot = pluginRoot.standardizedFileURL
        let rootValues = try? requestedRoot.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard rootValues?.isDirectory == true,
              rootValues?.isSymbolicLink != true
        else { return nil }

        let root = requestedRoot.resolvingSymlinksInPath()
        guard let manifest = manifestFile(in: root, maximumBytes: maximumManifestBytes),
              let data = boundedRegularFileData(at: manifest, maximumBytes: maximumManifestBytes),
              let payload = try? JSONDecoder().decode(ComponentManifestPayload.self, from: data)
        else { return nil }

        let skills = loadSkills(payload.skills, root: root)
        let hooks = loadHooks(
            payload.hooks,
            root: root,
            pluginIdentifier: pluginIdentifier,
            maximumBytes: maximumComponentFileBytes
        )
        let apps = loadApps(
            payload.apps,
            root: root,
            maximumBytes: maximumComponentFileBytes
        )
        let mcpServerNames = loadMCPServerNames(
            payload.mcpServers,
            root: root,
            maximumBytes: maximumComponentFileBytes
        )
        return CodexPluginPackageDetail(
            skills: skills,
            hooks: hooks,
            apps: apps,
            mcpServerNames: mcpServerNames
        )
    }

    private static func manifestFile(in root: URL, maximumBytes: Int) -> URL? {
        manifestPaths.lazy.compactMap {
            boundedFile($0, root: root, maximumBytes: maximumBytes)
        }.first
    }

    private static func loadSkills(_ reference: StringOrStringArray?, root: URL) -> [SkillCatalogMetadata] {
        let roots: [URL]
        if let reference {
            roots = reference.values.compactMap { boundedDirectory($0, root: root) }
        } else if let fallback = boundedDirectory(defaultSkillsPath, root: root) {
            roots = [fallback]
        } else {
            roots = []
        }
        guard !roots.isEmpty else { return [] }

        let snapshot = SkillCatalog(roots: roots.map { SkillRoot(kind: .system, url: $0) }).load()
        return Array(snapshot.skills.lazy.filter { skill in
            skill.productRestrictions.isEmpty || skill.productRestrictions.contains("CODEX")
        }.prefix(maximumComponentsPerKind))
    }

    private static func loadHooks(
        _ reference: HookReference?,
        root: URL,
        pluginIdentifier: String,
        maximumBytes: Int
    ) -> [CodexPluginHookDeclaration] {
        let sources: [HookSource]
        switch reference {
        case .paths(let paths):
            sources = paths.compactMap { path in
                guard let url = boundedFile(path, root: root, maximumBytes: maximumBytes),
                      let data = boundedRegularFileData(at: url, maximumBytes: maximumBytes),
                      let file = try? JSONDecoder().decode(HookFilePayload.self, from: data),
                      let relativePath = relativePath(of: url, inside: root)
                else { return nil }
                return HookSource(keyPath: relativePath, file: file)
            }
        case .inline(let files):
            sources = files.enumerated().map { index, file in
                HookSource(keyPath: "plugin.json#hooks[\(index)]", file: file)
            }
        case nil:
            guard let url = boundedFile(defaultHooksPath, root: root, maximumBytes: maximumBytes),
                  let data = boundedRegularFileData(at: url, maximumBytes: maximumBytes),
                  let file = try? JSONDecoder().decode(HookFilePayload.self, from: data)
            else { return [] }
            sources = [HookSource(keyPath: defaultHooksPath, file: file)]
        }

        var declarations: [CodexPluginHookDeclaration] = []
        for source in sources {
            for event in CodexPluginHookEvent.allCases {
                for (groupIndex, group) in source.file.groups(for: event).enumerated() {
                    for handlerIndex in group.hooks.indices {
                        declarations.append(CodexPluginHookDeclaration(
                            key: "\(pluginIdentifier):\(source.keyPath):\(event.keyLabel):"
                                + "\(groupIndex):\(handlerIndex)",
                            event: event
                        ))
                        if declarations.count == maximumComponentsPerKind { return declarations }
                    }
                }
            }
        }
        return declarations
    }

    private static func loadApps(
        _ reference: String?,
        root: URL,
        maximumBytes: Int
    ) -> [CodexPluginAppDeclaration] {
        let requested = reference ?? defaultAppsPath
        guard let url = boundedFile(requested, root: root, maximumBytes: maximumBytes),
              let data = boundedRegularFileData(at: url, maximumBytes: maximumBytes),
              let payload = try? JSONDecoder().decode(AppFilePayload.self, from: data)
        else { return [] }

        return payload.apps.keys.sorted().lazy.compactMap { name in
            guard let app = payload.apps[name],
                  let id = boundedText(app.id, maximumCharacters: 256),
                  let name = boundedText(name, maximumCharacters: 256)
            else { return nil }
            return CodexPluginAppDeclaration(
                id: id,
                name: name,
                category: boundedText(app.category, maximumCharacters: 120)
            )
        }.prefix(maximumComponentsPerKind).map { $0 }
    }

    private static func loadMCPServerNames(
        _ reference: MCPReference?,
        root: URL,
        maximumBytes: Int
    ) -> [String] {
        let servers: [String: MCPServerPayload]
        switch reference {
        case .servers(let values):
            servers = values
        case .path(let path):
            servers = mcpServers(at: path, root: root, maximumBytes: maximumBytes)
        case nil:
            servers = mcpServers(at: defaultMCPPath, root: root, maximumBytes: maximumBytes)
        }
        return Array(servers.keys.sorted().lazy.filter { name in
            guard let server = servers[name] else { return false }
            return boundedText(name, maximumCharacters: 256) != nil && server.isUsable
        }.prefix(maximumComponentsPerKind))
    }

    private static func mcpServers(
        at path: String,
        root: URL,
        maximumBytes: Int
    ) -> [String: MCPServerPayload] {
        guard let url = boundedFile(path, root: root, maximumBytes: maximumBytes),
              let data = boundedRegularFileData(at: url, maximumBytes: maximumBytes),
              let payload = try? JSONDecoder().decode(MCPFilePayload.self, from: data)
        else { return [:] }
        return payload.mcpServers
    }

    private static func boundedDirectory(_ path: String, root: URL) -> URL? {
        guard let candidate = boundedURL(path, root: root) else { return nil }
        let values = try? candidate.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values?.isDirectory == true, values?.isSymbolicLink != true else { return nil }
        return candidate
    }

    private static func boundedFile(_ path: String, root: URL, maximumBytes: Int) -> URL? {
        guard let candidate = boundedURL(path, root: root),
              boundedRegularFileData(at: candidate, maximumBytes: maximumBytes) != nil
        else { return nil }
        return candidate
    }

    private static func boundedURL(_ rawPath: String, root: URL) -> URL? {
        var path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.hasPrefix("./") { path.removeFirst(2) }
        guard !path.isEmpty,
              path.utf8.count <= 4_096,
              !NSString(string: path).isAbsolutePath,
              !path.contains("\0")
        else { return nil }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }
        guard let candidate = WorkspaceBoundary.safeURL(path, root: root) else { return nil }
        let resolved = candidate.resolvingSymlinksInPath()
        guard resolved.path == candidate.path,
              WorkspaceBoundary.isInside(resolved.path, root: root.path)
        else { return nil }
        return resolved
    }

    private static func boundedRegularFileData(at url: URL, maximumBytes: Int) -> Data? {
        let values = try? url.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        )
        guard values?.isRegularFile == true,
              values?.isSymbolicLink != true,
              (values?.fileSize ?? maximumBytes + 1) <= maximumBytes,
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              data.count <= maximumBytes
        else { return nil }
        return data
    }

    private static func relativePath(of url: URL, inside root: URL) -> String? {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard WorkspaceBoundary.isInside(path, root: rootPath), path != rootPath else { return nil }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private static func isBoundedPluginIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 320 && !value.contains(":") && !value.contains("\0")
    }

    private static func boundedText(_ value: String?, maximumCharacters: Int) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              !value.contains("\0"),
              value.count <= maximumCharacters
        else { return nil }
        return value
    }
}

private struct ComponentManifestPayload: Decodable {
    var skills: StringOrStringArray?
    var mcpServers: MCPReference?
    var apps: String?
    var hooks: HookReference?

    private enum CodingKeys: String, CodingKey {
        case skills
        case mcpServers
        case apps
        case hooks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        skills = try? container.decode(StringOrStringArray.self, forKey: .skills)
        mcpServers = try? container.decode(MCPReference.self, forKey: .mcpServers)
        apps = try? container.decode(String.self, forKey: .apps)
        hooks = try? container.decode(HookReference.self, forKey: .hooks)
    }
}

private struct StringOrStringArray: Decodable {
    var values: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            values = [value]
        } else {
            values = try container.decode([String].self)
        }
    }
}

private enum HookReference: Decodable {
    case paths([String])
    case inline([HookFilePayload])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let path = try? container.decode(String.self) {
            self = .paths([path])
        } else if let paths = try? container.decode([String].self) {
            self = .paths(paths)
        } else if let file = try? container.decode(HookFilePayload.self) {
            self = .inline([file])
        } else {
            self = .inline(try container.decode([HookFilePayload].self))
        }
    }
}

private struct HookSource {
    var keyPath: String
    var file: HookFilePayload
}

private struct HookFilePayload: Decodable {
    private var groupsByEvent: [CodexPluginHookEvent: [HookGroupPayload]]

    private enum CodingKeys: String, CodingKey { case hooks }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hooks = try container.nestedContainer(
            keyedBy: DynamicCodingKey.self,
            forKey: .hooks
        )
        var result: [CodexPluginHookEvent: [HookGroupPayload]] = [:]
        for key in hooks.allKeys {
            guard let event = CodexPluginHookEvent(manifestName: key.stringValue),
                  let groups = try? hooks.decode([HookGroupPayload].self, forKey: key)
            else { continue }
            result[event] = groups
        }
        groupsByEvent = result
    }

    func groups(for event: CodexPluginHookEvent) -> [HookGroupPayload] {
        groupsByEvent[event] ?? []
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

private struct HookGroupPayload: Decodable {
    var hooks: [HookHandlerPayload]
}

private struct HookHandlerPayload: Decodable {
    private enum CodingKeys: String, CodingKey { case type }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type).lowercased()
        guard ["command", "prompt", "agent"].contains(type) else {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "unsupported hook handler type"
            )
        }
    }
}

private struct AppFilePayload: Decodable {
    var apps: [String: AppPayload]
}

private struct AppPayload: Decodable {
    var id: String?
    var category: String?
}

private enum MCPReference: Decodable {
    case path(String)
    case servers([String: MCPServerPayload])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let path = try? container.decode(String.self) {
            self = .path(path)
        } else {
            self = .servers(try container.decode([String: MCPServerPayload].self))
        }
    }
}

private struct MCPFilePayload: Decodable {
    var mcpServers: [String: MCPServerPayload]
}

private struct MCPServerPayload: Decodable {
    var command: String?
    var url: String?
    var httpURL: String?

    var isUsable: Bool {
        [command, url, httpURL].contains { value in
            value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }
}
