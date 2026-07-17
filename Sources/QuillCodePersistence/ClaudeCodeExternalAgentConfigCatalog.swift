import Foundation
import QuillCodeCore

struct ClaudeCodeExternalAgentConfigCatalog: Sendable {
    var entries: [ClaudeCodeExternalAgentConfigEntry]

    var items: [ExternalAgentConfigMigrationItem] {
        entries.map(\.item)
    }

    func matching(_ requested: ExternalAgentConfigMigrationItem) -> ClaudeCodeExternalAgentConfigEntry? {
        entries.first {
            $0.item.itemType == requested.itemType
                && $0.item.cwd == requested.cwd
                && $0.accepts(requested.details)
        }
    }
}

struct ClaudeCodeExternalAgentConfigEntry: Sendable {
    enum Payload: Sendable {
        case agents(sources: [URL], target: URL)
        case config(source: URL, values: [String: ConfigValue], target: URL)
        case directories(sources: [NamedDirectory], target: URL)
        case workflows(sources: [NamedFile], target: URL, kind: AgentImportItemKind)
        case mcp(servers: [NamedConfig], target: URL)
        case hooks(source: URL, names: [String], data: Data, target: URL)
        case sessions([Session])
    }

    struct NamedDirectory: Sendable {
        var name: String
        var source: URL
        var sourceRoot: URL
    }

    struct NamedFile: Sendable {
        var name: String
        var source: URL
        var sourceRoot: URL
    }

    struct NamedConfig: Sendable {
        var name: String
        var value: ConfigValue
    }

    struct Session: Sendable {
        var source: URL
        var sourceRoot: URL
        var summary: ClaudeCodeTranscriptSummary
    }

    var item: ExternalAgentConfigMigrationItem
    var payload: Payload

    func accepts(_ requested: ExternalAgentConfigMigrationDetails?) -> Bool {
        guard let current = item.details else { return requested == nil }
        guard let requested else { return false }
        return plugins(requested.plugins, areSubsetOf: current.plugins)
            && Set(requested.sessions).isSubset(of: Set(current.sessions))
            && Set(requested.mcpServers).isSubset(of: Set(current.mcpServers))
            && Set(requested.hooks).isSubset(of: Set(current.hooks))
            && Set(requested.subagents).isSubset(of: Set(current.subagents))
            && Set(requested.commands).isSubset(of: Set(current.commands))
    }

    private func plugins(
        _ requested: [ExternalAgentConfigPluginsMigration],
        areSubsetOf current: [ExternalAgentConfigPluginsMigration]
    ) -> Bool {
        let available = Dictionary(grouping: current, by: \.marketplaceName).mapValues { groups in
            Set(groups.flatMap(\.pluginNames))
        }
        return requested.allSatisfy { group in
            guard let names = available[group.marketplaceName] else { return false }
            return Set(group.pluginNames).isSubset(of: names)
        }
    }
}

enum ClaudeCodeExternalAgentConfigCatalogBuilder {
    static let maximumCWDs = 64
    static let maximumSessions = 200
    static let recentSessionInterval: TimeInterval = 30 * 24 * 60 * 60

    static func build(
        sourceHomeDirectory: URL,
        destinationPaths: QuillCodePaths,
        cwds: [URL],
        includeHome: Bool,
        importedSessionPaths: Set<String>,
        now: Date
    ) throws -> ClaudeCodeExternalAgentConfigCatalog {
        var entries: [ClaudeCodeExternalAgentConfigEntry] = []
        if includeHome {
            try append(
                scope: .home,
                sourceHomeDirectory: sourceHomeDirectory,
                destinationPaths: destinationPaths,
                importedSessionPaths: importedSessionPaths,
                now: now,
                into: &entries
            )
        }
        var seen = Set<String>()
        for cwd in cwds.prefix(maximumCWDs) {
            guard let root = repositoryRoot(containing: cwd), seen.insert(root.path).inserted else {
                continue
            }
            try append(
                scope: .repository(root),
                sourceHomeDirectory: sourceHomeDirectory,
                destinationPaths: destinationPaths,
                importedSessionPaths: [],
                now: now,
                into: &entries
            )
        }
        return ClaudeCodeExternalAgentConfigCatalog(entries: entries)
    }

    enum Scope {
        case home
        case repository(URL)

        var cwd: String? {
            guard case .repository(let root) = self else { return nil }
            return root.path
        }
    }

    private static func append(
        scope: Scope,
        sourceHomeDirectory: URL,
        destinationPaths: QuillCodePaths,
        importedSessionPaths: Set<String>,
        now: Date,
        into entries: inout [ClaudeCodeExternalAgentConfigEntry]
    ) throws {
        let locations = Locations(
            scope: scope,
            sourceHomeDirectory: sourceHomeDirectory,
            destinationPaths: destinationPaths
        )
        let settings = effectiveSettings(in: locations.sourceConfigDirectory)

        if let values = configValues(from: settings),
           containsMissing(
               values,
               in: locations.targetConfig,
               boundary: locations.targetConfigBoundary
           ) {
            entries.append(entry(
                type: .config,
                description: "Migrate \(locations.sourceSettings.path) into \(locations.targetConfig.path)",
                scope: scope,
                payload: .config(
                    source: locations.sourceSettings,
                    values: values,
                    target: locations.targetConfig
                )
            ))
        }

        let servers = missingMCPServers(
            locations: locations,
            settings: settings,
            sourceHomeDirectory: sourceHomeDirectory
        )
        if !servers.isEmpty {
            let details = ExternalAgentConfigMigrationDetails(
                mcpServers: servers.map { .init(name: $0.name) }
            )
            entries.append(entry(
                type: .mcpServerConfig,
                description: "Migrate MCP servers from \(locations.sourceRoot.path) into \(locations.targetConfig.path)",
                scope: scope,
                details: details,
                payload: .mcp(servers: servers, target: locations.targetConfig)
            ))
        }

        if let hooks = hooksPayload(settings: settings),
           isMissingOrEmpty(locations.targetHooks) {
            let details = ExternalAgentConfigMigrationDetails(
                hooks: hooks.names.map { .init(name: $0) }
            )
            entries.append(entry(
                type: .hooks,
                description: "Migrate hooks from \(locations.sourceConfigDirectory.path) to \(locations.targetHooks.path)",
                scope: scope,
                details: details,
                payload: .hooks(
                    source: locations.sourceSettings,
                    names: hooks.names,
                    data: hooks.data,
                    target: locations.targetHooks
                )
            ))
        }

        let skills = missingDirectories(
            source: locations.sourceConfigDirectory.appendingPathComponent("skills"),
            target: locations.targetSkills,
            requiredManifest: "SKILL.md"
        )
        if !skills.isEmpty {
            entries.append(entry(
                type: .skills,
                description: "Migrate skills from \(locations.sourceConfigDirectory.path)/skills to \(locations.targetSkills.path)",
                scope: scope,
                payload: .directories(sources: skills, target: locations.targetSkills)
            ))
        }

        appendWorkflow(
            type: .commands,
            kind: .slashCommands,
            directoryName: "commands",
            locations: locations,
            scope: scope,
            into: &entries
        )
        appendWorkflow(
            type: .subagents,
            kind: .subagents,
            directoryName: "agents",
            locations: locations,
            scope: scope,
            into: &entries
        )

        if let instruction = instructionSource(scope: scope, locations: locations),
           isMissingOrEmpty(locations.targetAgents) {
            entries.append(entry(
                type: .agentsMD,
                description: "Migrate \(instruction.path) to \(locations.targetAgents.path)",
                scope: scope,
                payload: .agents(sources: [instruction], target: locations.targetAgents)
            ))
        }

        let plugins = missingDirectories(
            source: locations.sourceConfigDirectory.appendingPathComponent("plugins"),
            target: locations.targetPlugins,
            requiredManifest: ".claude-plugin/plugin.json"
        )
        if !plugins.isEmpty {
            let details = ExternalAgentConfigMigrationDetails(plugins: [
                .init(marketplaceName: "local", pluginNames: plugins.map(\.name)),
            ])
            entries.append(entry(
                type: .plugins,
                description: "Migrate plugins from \(locations.sourceConfigDirectory.path)/plugins to \(locations.targetPlugins.path)",
                scope: scope,
                details: details,
                payload: .directories(sources: plugins, target: locations.targetPlugins)
            ))
        }

        if case .home = scope {
            let sessions = recentSessions(
                sourceRoot: locations.sourceConfigDirectory,
                importedPaths: importedSessionPaths,
                now: now
            )
            if !sessions.isEmpty {
                let details = ExternalAgentConfigMigrationDetails(sessions: sessions.map {
                    .init(path: $0.source.path, cwd: $0.summary.cwd ?? "", title: $0.summary.title)
                })
                entries.append(entry(
                    type: .sessions,
                    description: "Migrate recent sessions from \(locations.sourceConfigDirectory.path)/projects",
                    scope: scope,
                    details: details,
                    payload: .sessions(sessions)
                ))
            }
        }
    }

    private static func appendWorkflow(
        type: ExternalAgentConfigItemType,
        kind: AgentImportItemKind,
        directoryName: String,
        locations: Locations,
        scope: Scope,
        into entries: inout [ClaudeCodeExternalAgentConfigEntry]
    ) {
        let files = missingMarkdownFiles(
            source: locations.sourceConfigDirectory.appendingPathComponent(directoryName),
            target: locations.targetSkills
        )
        guard !files.isEmpty else { return }
        var details = ExternalAgentConfigMigrationDetails()
        let names = files.map { ExternalAgentConfigNamedMigration(name: $0.name) }
        if type == .commands { details.commands = names } else { details.subagents = names }
        entries.append(entry(
            type: type,
            description: "Migrate \(directoryName) from \(locations.sourceConfigDirectory.path)/\(directoryName) to \(locations.targetSkills.path)",
            scope: scope,
            details: details,
            payload: .workflows(sources: files, target: locations.targetSkills, kind: kind)
        ))
    }

    private static func entry(
        type: ExternalAgentConfigItemType,
        description: String,
        scope: Scope,
        details: ExternalAgentConfigMigrationDetails? = nil,
        payload: ClaudeCodeExternalAgentConfigEntry.Payload
    ) -> ClaudeCodeExternalAgentConfigEntry {
        .init(
            item: .init(itemType: type, description: description, cwd: scope.cwd, details: details),
            payload: payload
        )
    }
}

extension ClaudeCodeExternalAgentConfigCatalogBuilder {
    struct Locations {
        var sourceRoot: URL
        var sourceConfigDirectory: URL
        var sourceSettings: URL
        var targetConfig: URL
        var targetConfigBoundary: URL
        var targetHooks: URL
        var targetSkills: URL
        var targetPlugins: URL
        var targetAgents: URL

        init(scope: Scope, sourceHomeDirectory: URL, destinationPaths: QuillCodePaths) {
            switch scope {
            case .home:
                sourceRoot = sourceHomeDirectory
                sourceConfigDirectory = sourceHomeDirectory.appendingPathComponent(".claude")
                targetConfig = destinationPaths.configFile
                targetConfigBoundary = destinationPaths.home
                targetHooks = destinationPaths.home.appendingPathComponent("hooks.json")
                targetSkills = destinationPaths.home.deletingLastPathComponent()
                    .appendingPathComponent(".agents/skills")
                targetPlugins = destinationPaths.home.appendingPathComponent("plugins")
                targetAgents = destinationPaths.home.appendingPathComponent("AGENTS.md")
            case .repository(let root):
                sourceRoot = root
                sourceConfigDirectory = root.appendingPathComponent(".claude")
                targetConfig = root.appendingPathComponent(".quillcode/config.toml")
                targetConfigBoundary = root
                targetHooks = root.appendingPathComponent(".quillcode/hooks.json")
                targetSkills = root.appendingPathComponent(".agents/skills")
                targetPlugins = root.appendingPathComponent(".quillcode/plugins")
                targetAgents = root.appendingPathComponent("AGENTS.md")
            }
            sourceSettings = sourceConfigDirectory.appendingPathComponent("settings.json")
        }
    }

    static func repositoryRoot(containing rawURL: URL) -> URL? {
        var url = rawURL.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
        if !isDirectory.boolValue { url.deleteLastPathComponent() }
        let fallback = url
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) {
                return url
            }
            let parent = url.deletingLastPathComponent()
            guard parent != url else { break }
            url = parent
        }
        return fallback
    }

    static func isMissingOrEmpty(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        guard let values = try? url.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        ),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let size = values.fileSize,
              size >= 0,
              size <= AgentImportFileSystem.maximumFileBytes,
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe])
        else { return false }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
    }
}
