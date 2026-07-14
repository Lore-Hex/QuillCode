import Foundation
import QuillCodeCore
import QuillCodeTools

struct CodexPluginPackage: Sendable, Hashable {
    var plugin: ProjectExtensionManifest
    var components: [ProjectExtensionManifest]
    var hooks: [ProjectPluginHook]
}

/// Loads the standard Codex plugin package shape without executing package code.
/// Every referenced path is relative to the package root and is revalidated after symlink resolution.
enum CodexPluginPackageLoader {
    static let manifestRelativePath = ".codex-plugin/plugin.json"
    static let maxCollectionEntries = 64
    static let maxComponentsPerPackage = 48
    static let maxHooksPerPackage = 48
    static let defaultHooksRelativePath = "hooks/hooks.json"
    static let defaultHookTimeoutSeconds = 600
    static let maxHookTimeoutSeconds = 3_600

    static func load(
        from projectRoot: URL,
        pluginDirectory: String,
        maxPackages: Int,
        maxManifestBytes: Int
    ) -> [CodexPluginPackage] {
        guard maxPackages > 0,
              let directory = resolveDirectory(
                pluginDirectory,
                inside: projectRoot,
                requireExistingDirectory: true
              )
        else { return [] }

        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var packages: [CodexPluginPackage] = []
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let package = package(
                at: entry,
                projectRoot: projectRoot,
                maxManifestBytes: maxManifestBytes
            ) else { continue }
            packages.append(package)
            if packages.count == maxPackages { break }
        }
        return packages
    }

    static func loadPackage(
        at relativePath: String,
        in projectRoot: URL,
        maxManifestBytes: Int
    ) -> CodexPluginPackage? {
        guard let candidate = resolveDirectory(
            relativePath,
            inside: projectRoot,
            requireExistingDirectory: true
        ) else { return nil }
        return package(
            at: candidate,
            projectRoot: projectRoot,
            maxManifestBytes: maxManifestBytes
        )
    }

    private static func package(
        at candidate: URL,
        projectRoot: URL,
        maxManifestBytes: Int
    ) -> CodexPluginPackage? {
        let values = try? candidate.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values?.isDirectory == true,
              values?.isSymbolicLink != true
        else { return nil }

        let root = candidate.standardizedFileURL.resolvingSymlinksInPath()
        let projectRoot = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        guard WorkspaceBoundary.isWithin(root, root: projectRoot),
              let manifestURL = resolveFile(
                manifestRelativePath,
                inside: root,
                maxBytes: maxManifestBytes
              ),
              let data = try? Data(contentsOf: manifestURL),
              let payload = try? JSONDecoder().decode(CodexPluginPayload.self, from: data),
              let pluginID = normalizedIdentifier(payload.name)
        else { return nil }

        let packageRoot = relativePath(of: root, inside: projectRoot)
        let displayName = normalizedText(payload.interface?.displayName, maxLength: 120)
            ?? displayName(from: payload.name)
        let summary = normalizedText(
            payload.interface?.shortDescription ?? payload.description,
            maxLength: 2_000
        ) ?? ""
        let skillDirectories = payload.skills.flatMap {
            resolveDirectory($0, inside: root, requireExistingDirectory: true)
        }.map { [relativePath(of: $0, inside: projectRoot)] }

        let plugin = ProjectExtensionManifest(
            id: "plugin:\(pluginID)",
            kind: .plugin,
            name: displayName,
            summary: summary,
            version: normalizedText(payload.version, maxLength: 80),
            sourceURL: normalizedText(payload.homepage ?? payload.repository, maxLength: 500),
            relativePath: "\(packageRoot)/\(manifestRelativePath)",
            packageRootRelativePath: packageRoot,
            skillDirectoryRelativePaths: skillDirectories
        )
        let components = skillComponents(
            skillDirectory: skillDirectories?.first,
            pluginID: pluginID,
            pluginName: displayName,
            projectRoot: projectRoot
        ) + mcpComponents(
            payload: payload,
            pluginID: pluginID,
            pluginName: displayName,
            packageRoot: root,
            packageRootRelativePath: packageRoot,
            projectRoot: projectRoot,
            maxManifestBytes: maxManifestBytes
        )
        return CodexPluginPackage(
            plugin: plugin,
            components: Array(components.prefix(maxComponentsPerPackage)),
            hooks: hookDefinitions(
                payload: payload,
                pluginID: pluginID,
                pluginName: displayName,
                packageRoot: root,
                projectRoot: projectRoot,
                maxManifestBytes: maxManifestBytes
            )
        )
    }

    private static func hookDefinitions(
        payload: CodexPluginPayload,
        pluginID: String,
        pluginName: String,
        packageRoot: URL,
        projectRoot: URL,
        maxManifestBytes: Int
    ) -> [ProjectPluginHook] {
        let reference = payload.hooks ?? defaultHooksRelativePath
        guard let configURL = resolveFile(reference, inside: packageRoot, maxBytes: maxManifestBytes),
              let data = try? Data(contentsOf: configURL),
              let configuration = try? JSONDecoder().decode(CodexPluginHookConfiguration.self, from: data)
        else { return [] }

        let configPath = relativePath(of: configURL, inside: projectRoot)
        let packageRootRelativePath = relativePath(of: packageRoot, inside: projectRoot)
        var definitions: [ProjectPluginHook] = []
        for event in configuration.hooks.keys.sorted() {
            guard let eventID = normalizedIdentifier(event),
                  let groups = configuration.hooks[event]
            else { continue }
            for (groupIndex, group) in groups.enumerated() {
                let matcher = normalizedOptionalText(group.matcher, maxLength: 1_000)
                for (handlerIndex, handler) in group.hooks.enumerated() {
                    guard definitions.count < maxHooksPerPackage,
                          let handlerType = normalizedOptionalText(handler.type, maxLength: 80)?.lowercased()
                    else { continue }
                    let command = normalizedOptionalText(handler.command, maxLength: 8_000)
                    let commandWindows = normalizedOptionalText(handler.commandWindows, maxLength: 8_000)
                    let statusMessage = normalizedOptionalText(handler.statusMessage, maxLength: 240)
                    let timeoutSeconds = normalizedHookTimeout(handler.timeout)
                    let isAsync = handler.isAsync ?? false
                    let definitionHash = hookDefinitionHash(
                        event: event,
                        matcher: matcher,
                        handlerType: handlerType,
                        command: command,
                        commandWindows: commandWindows,
                        statusMessage: statusMessage,
                        timeoutSeconds: timeoutSeconds,
                        isAsync: isAsync,
                        pluginRootRelativePath: packageRootRelativePath
                    )
                    definitions.append(ProjectPluginHook(
                        id: "plugin_hook:\(pluginID).\(eventID).\(groupIndex).\(handlerIndex)",
                        pluginID: "plugin:\(pluginID)",
                        pluginName: pluginName,
                        event: event,
                        matcher: matcher,
                        handlerType: handlerType,
                        command: command,
                        commandWindows: commandWindows,
                        statusMessage: statusMessage,
                        timeoutSeconds: timeoutSeconds,
                        isAsync: isAsync,
                        relativePath: "\(configPath)#\(event)/\(groupIndex)/\(handlerIndex)",
                        pluginRootRelativePath: packageRootRelativePath,
                        definitionHash: definitionHash,
                        supportStatus: hookSupportStatus(
                            event: event,
                            matcher: matcher,
                            handlerType: handlerType,
                            command: command,
                            isAsync: isAsync
                        )
                    ))
                }
                if definitions.count == maxHooksPerPackage { break }
            }
            if definitions.count == maxHooksPerPackage { break }
        }
        return definitions
    }

    private static func hookSupportStatus(
        event: String,
        matcher: String?,
        handlerType: String,
        command: String?,
        isAsync: Bool
    ) -> ProjectHookSupportStatus {
        if isAsync { return .asynchronousHandler }
        if handlerType != "command" { return .unsupportedHandler }
        if command == nil { return .missingCommand }
        switch event {
        case "UserPromptSubmit", "Stop":
            if let matcher, matcher != "*" { return .unsupportedMatcher }
            return .supported
        case "PreToolUse", "PostToolUse", "PermissionRequest", "PreCompact", "PostCompact":
            return ProjectPluginHookMatcher.isValid(matcher)
                ? .supported
                : .unsupportedMatcher
        default:
            return .unsupportedEvent
        }
    }

    private static func hookDefinitionHash(
        event: String,
        matcher: String?,
        handlerType: String,
        command: String?,
        commandWindows: String?,
        statusMessage: String?,
        timeoutSeconds: Int,
        isAsync: Bool,
        pluginRootRelativePath: String
    ) -> String {
        let canonical = [
            event,
            matcher ?? "",
            handlerType,
            command ?? "",
            commandWindows ?? "",
            statusMessage ?? "",
            String(timeoutSeconds),
            isAsync ? "true" : "false",
            pluginRootRelativePath
        ].joined(separator: "\u{1F}")
        return MCPCrypto.sha256(Array(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func normalizedHookTimeout(_ value: Int?) -> Int {
        min(max(value ?? defaultHookTimeoutSeconds, 1), maxHookTimeoutSeconds)
    }

    private static func skillComponents(
        skillDirectory: String?,
        pluginID: String,
        pluginName: String,
        projectRoot: URL
    ) -> [ProjectExtensionManifest] {
        guard let skillDirectory,
              let root = resolveDirectory(skillDirectory, inside: projectRoot, requireExistingDirectory: true)
        else { return [] }

        let entries = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        var skills: [ProjectExtensionManifest] = []
        for candidate in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let values = try? candidate.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true,
                  values?.isSymbolicLink != true,
                  WorkspaceBoundary.isWithin(candidate, root: root),
                  let skillID = normalizedIdentifier(candidate.lastPathComponent),
                  let skillFile = resolveFile(
                    SkillResolver.manifestFileName,
                    inside: candidate,
                    maxBytes: SkillLoadToolExecutor.defaultManifestMaxBytes
                  )
            else { continue }
            skills.append(ProjectExtensionManifest(
                id: "skill:\(pluginID).\(skillID)",
                kind: .skill,
                name: "\(pluginName) · \(displayName(from: candidate.lastPathComponent))",
                summary: "Bundled by \(pluginName).",
                relativePath: relativePath(of: skillFile, inside: projectRoot),
                packageRootRelativePath: relativePath(of: candidate, inside: projectRoot)
            ))
            if skills.count == maxComponentsPerPackage { break }
        }
        return skills
    }

    private static func mcpComponents(
        payload: CodexPluginPayload,
        pluginID: String,
        pluginName: String,
        packageRoot: URL,
        packageRootRelativePath: String,
        projectRoot: URL,
        maxManifestBytes: Int
    ) -> [ProjectExtensionManifest] {
        guard let reference = payload.mcpServers,
              let configURL = resolveFile(reference, inside: packageRoot, maxBytes: maxManifestBytes),
              let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(CodexPluginMCPConfiguration.self, from: data)
        else { return [] }

        let configPath = relativePath(of: configURL, inside: projectRoot)
        return config.mcpServers.keys.sorted().prefix(maxComponentsPerPackage).compactMap { serverName in
            guard let server = config.mcpServers[serverName],
                  let serverID = normalizedIdentifier(serverName),
                  let transport = server.transportKind
            else { return nil }

            let command = normalizedText(server.command, maxLength: 1_200)
            let arguments = normalizedArguments(server.args)
            let url = normalizedText(server.url ?? server.httpURL, maxLength: 2_000)
            guard transport != .stdio || command != nil,
                  transport == .stdio || url != nil
            else { return nil }

            return ProjectExtensionManifest(
                id: "mcp_server:\(pluginID).\(serverID)",
                kind: .mcpServer,
                name: "\(pluginName) · \(displayName(from: serverName))",
                summary: "Bundled by \(pluginName).",
                relativePath: "\(configPath)#\(serverName)",
                isEnabled: server.enabled ?? true,
                transport: transport,
                serverURL: url,
                headers: normalizedDictionary(server.headers, keyLimit: 200, valueLimit: 4_000),
                oauthClientID: normalizedText(server.oauthClientID ?? server.oauth_client_id, maxLength: 500),
                launchExecutable: command,
                launchCommand: command.map { ([ $0 ] + arguments).joined(separator: " ") },
                launchArguments: arguments.isEmpty ? nil : arguments,
                packageRootRelativePath: packageRootRelativePath,
                launchEnvironment: normalizedEnvironment(server.env),
                inheritedEnvironmentVariableNames: normalizedEnvironmentNames(server.envVars ?? server.env_vars)
            )
        }
    }

    private static func resolveDirectory(
        _ relativePath: String,
        inside root: URL,
        requireExistingDirectory: Bool
    ) -> URL? {
        guard let candidate = resolve(relativePath, inside: root) else { return nil }
        guard requireExistingDirectory else { return candidate }
        let values = try? candidate.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values?.isDirectory == true, values?.isSymbolicLink != true else { return nil }
        return candidate
    }

    private static func resolveFile(_ relativePath: String, inside root: URL, maxBytes: Int) -> URL? {
        guard maxBytes > 0,
              let candidate = resolve(relativePath, inside: root)
        else { return nil }
        let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values?.isRegularFile == true,
              values?.isSymbolicLink != true,
              (values?.fileSize ?? 0) <= maxBytes
        else { return nil }
        return candidate
    }

    private static func resolve(_ relativePath: String, inside root: URL) -> URL? {
        var normalized = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalized.hasPrefix("./") {
            normalized.removeFirst(2)
        }
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        guard !normalized.isEmpty,
              !normalized.hasPrefix("/"),
              !normalized.contains("\0")
        else { return nil }
        let components = normalized.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return nil }
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = components.reduce(canonicalRoot) { url, component in
            url.appendingPathComponent(component)
        }.standardizedFileURL.resolvingSymlinksInPath()
        return WorkspaceBoundary.isWithin(candidate, root: canonicalRoot) ? candidate : nil
    }

    private static func relativePath(of url: URL, inside root: URL) -> String {
        String(url.path.dropFirst(root.path.count + 1))
    }

    private static func normalizedIdentifier(_ value: String) -> String? {
        let result = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-" }
        return result.isEmpty || result.count > 128 ? nil : result
    }

    private static func normalizedText(_ value: String?, maxLength: Int) -> String? {
        guard let result = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !result.isEmpty,
              result.count <= maxLength
        else { return nil }
        return result
    }

    private static func normalizedOptionalText(_ value: String?, maxLength: Int) -> String? {
        guard let result = normalizedText(value, maxLength: maxLength),
              !result.contains("\0")
        else { return nil }
        return result
    }

    private static func normalizedArguments(_ arguments: [String]?) -> [String] {
        Array((arguments ?? []).lazy.compactMap {
            normalizedText($0, maxLength: 4_000)
        }.prefix(128))
    }

    private static func normalizedDictionary(
        _ values: [String: String]?,
        keyLimit: Int,
        valueLimit: Int
    ) -> [String: String]? {
        guard let values else { return nil }
        let pairs = values.keys.sorted().lazy.compactMap { key -> (String, String)? in
            guard let value = values[key],
                  let key = normalizedText(key, maxLength: keyLimit),
                  let value = normalizedText(value, maxLength: valueLimit)
            else { return nil }
            return (key, value)
        }.prefix(maxCollectionEntries)
        let result = Dictionary(uniqueKeysWithValues: pairs)
        return result.isEmpty ? nil : result
    }

    private static func normalizedEnvironment(_ values: [String: String]?) -> [String: String]? {
        let result = normalizedDictionary(values, keyLimit: 128, valueLimit: 8_000)?
            .filter { isEnvironmentName($0.key) }
        return result?.isEmpty == false ? result : nil
    }

    private static func normalizedEnvironmentNames(_ values: [String]?) -> [String]? {
        let result = Array(Set((values ?? []).lazy.compactMap {
            normalizedText($0, maxLength: 128)
        }.filter(isEnvironmentName)).sorted().prefix(maxCollectionEntries))
        return result.isEmpty ? nil : result
    }

    private static func isEnvironmentName(_ value: String) -> Bool {
        guard let first = value.first, first == "_" || first.isASCII && first.isLetter else { return false }
        return value.allSatisfy { $0 == "_" || $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    private static func displayName(from value: String) -> String {
        value.replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .map { word in
                guard let first = word.first else { return String(word) }
                return first.uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }
}

private struct CodexPluginPayload: Decodable {
    var name: String
    var version: String?
    var description: String?
    var homepage: String?
    var repository: String?
    var skills: String?
    var mcpServers: String?
    var hooks: String?
    var interface: CodexPluginInterfacePayload?
}

private struct CodexPluginInterfacePayload: Decodable {
    var displayName: String?
    var shortDescription: String?
}

private struct CodexPluginMCPConfiguration: Decodable {
    var mcpServers: [String: CodexPluginMCPServerPayload]
}

private struct CodexPluginMCPServerPayload: Decodable {
    var type: String?
    var transport: String?
    var command: String?
    var args: [String]?
    var env: [String: String]?
    var envVars: [String]?
    var env_vars: [String]?
    var url: String?
    var httpURL: String?
    var headers: [String: String]?
    var oauthClientID: String?
    var oauth_client_id: String?
    var enabled: Bool?

    var transportKind: ProjectExtensionTransport? {
        let raw = (transport ?? type)?.lowercased()
        if raw == nil { return command == nil ? .http : .stdio }
        switch raw {
        case "stdio": return .stdio
        case "http", "streamable-http", "streamable_http", "streamablehttp": return .http
        case "sse": return .sse
        default: return nil
        }
    }

}

private struct CodexPluginHookConfiguration: Decodable {
    var hooks: [String: [CodexPluginHookGroupPayload]]
}

private struct CodexPluginHookGroupPayload: Decodable {
    var matcher: String?
    var hooks: [CodexPluginHookHandlerPayload]
}

private struct CodexPluginHookHandlerPayload: Decodable {
    var type: String?
    var command: String?
    var commandWindows: String?
    var statusMessage: String?
    var timeout: Int?
    var isAsync: Bool?

    private enum CodingKeys: String, CodingKey {
        case type
        case command
        case commandWindows
        case statusMessage
        case timeout
        case isAsync = "async"
    }
}
