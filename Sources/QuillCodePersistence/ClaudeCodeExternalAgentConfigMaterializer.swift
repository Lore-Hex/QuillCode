import Foundation
import QuillCodeCore

enum ClaudeCodeExternalAgentConfigMaterializer {
    typealias SessionImporter = @Sendable (ExternalAgentConfigImportedSession) async throws -> UUID

    static func run(
        entry: ClaudeCodeExternalAgentConfigEntry,
        requested: ExternalAgentConfigMigrationItem,
        destinationPaths: QuillCodePaths,
        appConfig: AppConfig,
        importSession: SessionImporter
    ) async -> ExternalAgentConfigImportTypeResult {
        var result = ExternalAgentConfigImportTypeResult(itemType: requested.itemType)
        switch entry.payload {
        case .agents(let sources, let target):
            await capture(item: requested, source: sources.map(\.path).joined(separator: ", "), in: &result) {
                let contents = try sources.map { source -> String in
                    let root = source.deletingLastPathComponent()
                    guard let text = AgentImportFileSystem.readText(source, inside: root) else {
                        throw AgentImportError.invalidSourceOrDestination
                    }
                    return text
                }.joined(separator: "\n\n")
                guard let data = contents.data(using: .utf8) else {
                    throw AgentImportError.invalidSourceOrDestination
                }
                try writeMissingOrEmpty(data, to: target, requested: requested, paths: destinationPaths)
                return target.path
            }
        case .config(let source, let values, let target):
            await capture(item: requested, source: source.path, in: &result) {
                try mergeConfigValues(values, into: target, requested: requested, paths: destinationPaths)
                return target.path
            }
        case .directories(let sources, let target):
            let selected = selectedNames(for: requested)
            for source in sources where selected == nil || selected?.contains(source.name) == true {
                await capture(item: requested, source: source.name, in: &result) {
                    let destination = target.appendingPathComponent(source.name)
                    let boundary = destinationBoundary(
                        for: destination,
                        requested: requested,
                        paths: destinationPaths
                    )
                    _ = try AgentImportFileSystem.copyDirectory(
                        source.source,
                        sourceRoot: source.sourceRoot,
                        to: destination,
                        destinationRoot: boundary
                    )
                    if requested.itemType == .plugins {
                        do {
                            try ensureCodexPluginManifest(at: destination, boundary: boundary)
                        } catch {
                            AgentImportFileSystem.removeCreatedItem(destination, inside: boundary)
                            throw error
                        }
                    }
                    return source.name
                }
            }
        case .workflows(let sources, let target, let kind):
            let selected = selectedNames(for: requested)
            for source in sources where selected == nil || selected?.contains(source.name) == true {
                await capture(item: requested, source: source.name, in: &result) {
                    guard let content = AgentImportFileSystem.readText(source.source, inside: source.sourceRoot),
                          let data = convertedSkill(content, name: source.name, kind: kind).data(using: .utf8)
                    else { throw AgentImportError.invalidSourceOrDestination }
                    let destination = target.appendingPathComponent(source.name).appendingPathComponent("SKILL.md")
                    try AgentImportFileSystem.writeNew(
                        data,
                        to: destination,
                        inside: destinationBoundary(
                            for: destination,
                            requested: requested,
                            paths: destinationPaths
                        )
                    )
                    return source.name
                }
            }
        case .mcp(let servers, let target):
            let selected = requested.details.map { Set($0.mcpServers.map(\.name)) }
            for server in servers where selected == nil || selected?.contains(server.name) == true {
                await capture(item: requested, source: server.name, in: &result) {
                    try mergeMCPServer(
                        server,
                        into: target,
                        requested: requested,
                        paths: destinationPaths
                    )
                    return server.name
                }
            }
        case .hooks(let source, let names, let data, let target):
            let selected = requested.details.map { Set($0.hooks.map(\.name)) } ?? Set(names)
            let selectedNames = names.filter(selected.contains)
            guard !selectedNames.isEmpty,
                  let selectedData = selectedHookData(data, names: Set(selectedNames))
            else { break }
            await capture(item: requested, source: source.path, in: &result) {
                try writeMissingOrEmpty(
                    selectedData,
                    to: target,
                    requested: requested,
                    paths: destinationPaths
                )
                return target.path
            }
            if result.failures.isEmpty {
                result.successes = selectedNames.map {
                    success(item: requested, source: $0, target: $0)
                }
            }
        case .sessions(let sessions):
            let selected = requested.details.map { Set($0.sessions.map(\.path)) }
            for session in sessions where selected == nil || selected?.contains(session.source.path) == true {
                await capture(item: requested, source: session.source.path, in: &result) {
                    let imported = importedSession(session, appConfig: appConfig)
                    return try await importSession(imported).uuidString.lowercased()
                }
            }
        }
        return result
    }
}

private extension ClaudeCodeExternalAgentConfigMaterializer {
    static func capture(
        item: ExternalAgentConfigMigrationItem,
        source: String?,
        in result: inout ExternalAgentConfigImportTypeResult,
        operation: () async throws -> String?
    ) async {
        do {
            result.successes.append(success(item: item, source: source, target: try await operation()))
        } catch {
            result.failures.append(.init(
                itemType: item.itemType,
                cwd: item.cwd,
                source: source,
                errorType: "external_agent_config_import_error",
                failureStage: "import_request_failed",
                message: String(describing: error)
            ))
        }
    }

    static func success(
        item: ExternalAgentConfigMigrationItem,
        source: String?,
        target: String?
    ) -> ExternalAgentConfigImportSuccess {
        .init(itemType: item.itemType, cwd: item.cwd, source: source, target: target)
    }

    static func selectedNames(for item: ExternalAgentConfigMigrationItem) -> Set<String>? {
        guard let details = item.details else { return nil }
        let names: [String]
        switch item.itemType {
        case .plugins: names = details.plugins.flatMap(\.pluginNames)
        case .commands: names = details.commands.map(\.name)
        case .subagents: names = details.subagents.map(\.name)
        default: return nil
        }
        return Set(names)
    }

    static func mergeConfigValues(
        _ values: [String: ConfigValue],
        into target: URL,
        requested: ExternalAgentConfigMigrationItem,
        paths: QuillCodePaths
    ) throws {
        let boundary = destinationBoundary(for: target, requested: requested, paths: paths)
        let store = try configStore(for: target, inside: boundary)
        var document = try store.load()
        var changed = false
        for (key, value) in values where document.values[key] == nil {
            document.values[key] = value
            changed = true
        }
        if changed { try store.save(document) }
    }

    static func mergeMCPServer(
        _ server: ClaudeCodeExternalAgentConfigEntry.NamedConfig,
        into target: URL,
        requested: ExternalAgentConfigMigrationItem,
        paths: QuillCodePaths
    ) throws {
        let boundary = destinationBoundary(for: target, requested: requested, paths: paths)
        let store = try configStore(for: target, inside: boundary)
        var document = try store.load()
        var servers = document.values["mcp_servers"]?.objectValue ?? [:]
        guard servers[server.name] == nil else { return }
        servers[server.name] = server.value
        document.values["mcp_servers"] = .object(servers)
        try store.save(document)
    }

    static func writeMissingOrEmpty(
        _ data: Data,
        to target: URL,
        requested: ExternalAgentConfigMigrationItem,
        paths: QuillCodePaths
    ) throws {
        let boundary = destinationBoundary(for: target, requested: requested, paths: paths)
        if FileManager.default.fileExists(atPath: target.path) {
            guard let validated = AgentImportFileSystem.regularFile(target, inside: boundary),
                  let existing = AgentImportFileSystem.readData(validated, inside: boundary),
                  String(data: existing, encoding: .utf8)?
                      .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
            else { throw AgentImportError.destinationAlreadyExists }
            try data.write(to: validated, options: .atomic)
            return
        }
        try AgentImportFileSystem.writeNew(data, to: target, inside: boundary)
    }

    static func destinationBoundary(
        for target: URL,
        requested: ExternalAgentConfigMigrationItem,
        paths: QuillCodePaths
    ) -> URL {
        if let cwd = requested.cwd, !cwd.isEmpty {
            return URL(fileURLWithPath: cwd).standardizedFileURL.resolvingSymlinksInPath()
        }
        if WorkspaceBoundary.isWithin(target, root: paths.home) { return paths.home }
        return paths.home.deletingLastPathComponent()
    }

    static func ensureCodexPluginManifest(at plugin: URL, boundary: URL) throws {
        let codex = plugin.appendingPathComponent(".codex-plugin/plugin.json")
        if AgentImportFileSystem.regularFile(codex, inside: plugin) != nil { return }
        let claude = plugin.appendingPathComponent(".claude-plugin/plugin.json")
        guard let data = AgentImportFileSystem.readData(claude, inside: plugin) else {
            throw AgentImportError.invalidSourceOrDestination
        }
        try AgentImportFileSystem.writeNew(data, to: codex, inside: boundary)
    }

    static func convertedSkill(
        _ content: String,
        name: String,
        kind: AgentImportItemKind
    ) -> String {
        let origin = kind == .subagents ? "subagent" : "slash command"
        return """
        ---
        name: \(name)
        description: Imported Claude Code \(origin). Review tool and permission assumptions before first use.
        ---

        # Imported from Claude Code

        \(content)
        """
    }

    static func importedSession(
        _ session: ClaudeCodeExternalAgentConfigEntry.Session,
        appConfig: AppConfig
    ) -> ExternalAgentConfigImportedSession {
        let provenance = AgentImportThreadProvenance(
            source: .claudeCode,
            sourceID: session.summary.sessionID
        )
        let payload = (try? JSONEncoder().encode([AgentImportThreadProvenance.payloadKey: provenance]))
            .flatMap { String(data: $0, encoding: .utf8) }
        let thread = ChatThread(
            title: session.summary.title,
            mode: appConfig.mode,
            model: appConfig.defaultModel,
            messages: session.summary.messages,
            events: [.init(
                kind: .notice,
                createdAt: session.summary.updatedAt,
                summary: "Imported from Claude Code",
                payloadJSON: payload
            )],
            createdAt: session.summary.createdAt,
            updatedAt: session.summary.updatedAt
        )
        return .init(
            thread: thread,
            cwd: session.summary.cwd.map { URL(fileURLWithPath: $0).standardizedFileURL },
            sourcePath: session.source.path
        )
    }

    static func configStore(
        for target: URL,
        inside boundary: URL
    ) throws -> ConfigDocumentStore {
        if FileManager.default.fileExists(atPath: target.path) {
            guard let validated = AgentImportFileSystem.regularFile(
                target,
                inside: boundary,
                maximumBytes: ConfigDocumentStore.maximumBytes
            ) else {
                throw AgentImportError.invalidSourceOrDestination
            }
            return ConfigDocumentStore(fileURL: validated)
        }
        try AgentImportFileSystem.createDirectory(target.deletingLastPathComponent(), inside: boundary)
        return ConfigDocumentStore(fileURL: target)
    }

    static func selectedHookData(_ data: Data, names: Set<String>) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = object["hooks"] as? [String: Any]
        else { return nil }
        let selected = hooks.filter { names.contains($0.key) }
        guard !selected.isEmpty else { return nil }
        return try? JSONSerialization.data(
            withJSONObject: ["hooks": selected],
            options: [.prettyPrinted, .sortedKeys]
        )
    }
}
