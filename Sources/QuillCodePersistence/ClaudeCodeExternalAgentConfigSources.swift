import Foundation
import QuillCodeCore

extension ClaudeCodeExternalAgentConfigCatalogBuilder {
    static func effectiveSettings(in directory: URL) -> [String: Any]? {
        let base = jsonObject(
            at: directory.appendingPathComponent("settings.json"),
            inside: directory
        )
        guard let local = jsonObject(
            at: directory.appendingPathComponent("settings.local.json"),
            inside: directory
        ) else { return base }
        return recursivelyMerging(base ?? [:], with: local)
    }

    static func configValues(from settings: [String: Any]?) -> [String: ConfigValue]? {
        guard let sandbox = settings?["sandbox"] as? [String: Any],
              sandbox["enabled"] as? Bool == true
        else { return nil }
        return ["sandbox_mode": .string("workspace-write")]
    }

    static func containsMissing(
        _ values: [String: ConfigValue],
        in target: URL,
        boundary: URL
    ) -> Bool {
        guard let existing = configDocument(at: target, inside: boundary) else { return false }
        return values.contains { existing.values[$0.key] == nil }
    }

    static func missingMCPServers(
        locations: Locations,
        settings: [String: Any]?,
        sourceHomeDirectory: URL
    ) -> [ClaudeCodeExternalAgentConfigEntry.NamedConfig] {
        var rawServers: [String: Any] = [:]
        appendMCPServers(
            from: locations.sourceRoot.appendingPathComponent(".mcp.json"),
            inside: locations.sourceRoot,
            into: &rawServers
        )
        appendMCPServers(
            from: locations.sourceRoot.appendingPathComponent(".claude.json"),
            inside: locations.sourceRoot,
            matchingProject: locations.sourceRoot,
            into: &rawServers
        )
        if locations.sourceRoot != sourceHomeDirectory {
            appendMCPServers(
                from: sourceHomeDirectory.appendingPathComponent(".claude.json"),
                inside: sourceHomeDirectory,
                matchingProject: locations.sourceRoot,
                preservesExisting: true,
                into: &rawServers
            )
        }
        if let settingsServers = settings?["mcpServers"] as? [String: Any] {
            rawServers.merge(settingsServers) { _, incoming in incoming }
        }

        guard let existingNames = existingMCPServerNames(
            in: locations.targetConfig,
            boundary: locations.targetConfigBoundary
        ) else { return [] }
        return rawServers.keys.sorted().compactMap { name in
            guard !existingNames.contains(name),
                  var object = ClaudeCodeImportSanitizer.sanitizedMCPServer(rawServers[name] as Any),
                  object["enabled"] as? Bool != false,
                  object["disabled"] as? Bool != true
            else { return nil }
            object.removeValue(forKey: "enabled")
            object.removeValue(forKey: "disabled")
            object.removeValue(forKey: "type")
            guard let value = configValue(from: object), value.objectValue != nil else { return nil }
            return .init(name: name, value: value)
        }
    }

    static func hooksPayload(settings: [String: Any]?) -> (names: [String], data: Data)? {
        guard let hooks = settings?["hooks"] as? [String: Any], !hooks.isEmpty else { return nil }
        let names = hooks.keys.sorted()
        let payload = ["hooks": ClaudeCodeImportSanitizer.redact(hooks, key: nil)]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(
                  withJSONObject: payload,
                  options: [.prettyPrinted, .sortedKeys]
              )
        else { return nil }
        return (names, data)
    }

    static func missingDirectories(
        source: URL,
        target: URL,
        requiredManifest: String
    ) -> [ClaudeCodeExternalAgentConfigEntry.NamedDirectory] {
        guard let source = AgentImportFileSystem.directory(source, inside: source.deletingLastPathComponent()),
              let entries = try? FileManager.default.contentsOfDirectory(
                  at: source,
                  includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                  options: [.skipsHiddenFiles]
              )
        else { return [] }
        return entries.sorted { $0.lastPathComponent < $1.lastPathComponent }.prefix(200).compactMap {
            guard AgentImportFileSystem.directory($0, inside: source) != nil,
                  hasManifest(requiredManifest, in: $0),
                  !FileManager.default.fileExists(
                      atPath: target.appendingPathComponent($0.lastPathComponent).path
                  )
            else { return nil }
            return .init(name: $0.lastPathComponent, source: $0, sourceRoot: source)
        }
    }

    static func missingMarkdownFiles(
        source: URL,
        target: URL
    ) -> [ClaudeCodeExternalAgentConfigEntry.NamedFile] {
        guard let source = AgentImportFileSystem.directory(source, inside: source.deletingLastPathComponent()),
              let entries = try? FileManager.default.contentsOfDirectory(
                  at: source,
                  includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
                  options: [.skipsHiddenFiles]
              )
        else { return [] }
        return entries.sorted { $0.lastPathComponent < $1.lastPathComponent }.prefix(200).compactMap {
            guard $0.pathExtension.lowercased() == "md",
                  AgentImportFileSystem.readText($0, inside: source) != nil
            else { return nil }
            let name = AgentImportFileSystem.sanitizedComponent(
                $0.deletingPathExtension().lastPathComponent,
                fallback: "imported-workflow"
            )
            guard !FileManager.default.fileExists(atPath: target.appendingPathComponent(name).path) else {
                return nil
            }
            return .init(name: name, source: $0, sourceRoot: source)
        }
    }

    static func instructionSource(scope: Scope, locations: Locations) -> URL? {
        let candidates: [URL]
        switch scope {
        case .home:
            candidates = [locations.sourceConfigDirectory.appendingPathComponent("CLAUDE.md")]
        case .repository(let root):
            candidates = [
                root.appendingPathComponent("CLAUDE.md"),
                locations.sourceConfigDirectory.appendingPathComponent("CLAUDE.md"),
            ]
        }
        return candidates.first {
            guard let root = sourceBoundary(for: $0, locations: locations),
                  let text = AgentImportFileSystem.readText($0, inside: root)
            else { return false }
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    static func recentSessions(
        sourceRoot: URL,
        importedPaths: Set<String>,
        now: Date
    ) -> [ClaudeCodeExternalAgentConfigEntry.Session] {
        let projects = sourceRoot.appendingPathComponent("projects")
        guard let projects = AgentImportFileSystem.directory(projects, inside: sourceRoot),
              let enumerator = FileManager.default.enumerator(
                  at: projects,
                  includingPropertiesForKeys: [
                      .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey,
                  ],
                  options: [.skipsHiddenFiles]
              )
        else { return [] }

        var candidates: [(URL, Date)] = []
        for case let file as URL in enumerator where file.pathExtension.lowercased() == "jsonl" {
            let canonicalFile = file.standardizedFileURL.resolvingSymlinksInPath()
            guard !importedPaths.contains(canonicalFile.path),
                  let values = try? file.resourceValues(forKeys: [
                      .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey,
                  ]),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  (values.fileSize ?? Int.max) <= ClaudeCodeTranscriptParser.maximumFileBytes,
                  let modified = values.contentModificationDate,
                  now.timeIntervalSince(modified) <= recentSessionInterval
            else { continue }
            candidates.append((canonicalFile, modified))
        }
        return candidates.sorted { $0.1 > $1.1 }.prefix(maximumSessions).compactMap { file, _ in
            ClaudeCodeTranscriptParser.parse(fileURL: file, sourceRoot: sourceRoot).map {
                .init(source: file, sourceRoot: sourceRoot, summary: $0)
            }
        }
    }
}

private extension ClaudeCodeExternalAgentConfigCatalogBuilder {
    static func jsonObject(at file: URL, inside root: URL) -> [String: Any]? {
        guard let data = AgentImportFileSystem.readData(file, inside: root),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }

    static func recursivelyMerging(
        _ existing: [String: Any],
        with incoming: [String: Any]
    ) -> [String: Any] {
        var result = existing
        for (key, value) in incoming {
            if let current = result[key] as? [String: Any], let nested = value as? [String: Any] {
                result[key] = recursivelyMerging(current, with: nested)
            } else {
                result[key] = value
            }
        }
        return result
    }

    static func configValue(from object: [String: Any]) -> ConfigValue? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let value = try? JSONDecoder().decode(ConfigValue.self, from: data)
        else { return nil }
        return value
    }

    static func existingMCPServerNames(in target: URL, boundary: URL) -> Set<String>? {
        guard let document = configDocument(at: target, inside: boundary) else { return nil }
        return Set(document.values["mcp_servers"]?.objectValue.map { Array($0.keys) } ?? [])
    }

    static func configDocument(at target: URL, inside boundary: URL) -> ConfigDocument? {
        if !FileManager.default.fileExists(atPath: target.path) { return ConfigDocument() }
        guard let validated = AgentImportFileSystem.regularFile(
            target,
            inside: boundary,
            maximumBytes: ConfigDocumentStore.maximumBytes
        ) else { return nil }
        return try? ConfigDocumentStore(fileURL: validated).load()
    }

    static func appendMCPServers(
        from file: URL,
        inside root: URL,
        matchingProject: URL? = nil,
        preservesExisting: Bool = false,
        into servers: inout [String: Any]
    ) {
        guard let object = jsonObject(at: file, inside: root) else { return }
        func merge(_ values: [String: Any]) {
            servers.merge(values) { existing, incoming in preservesExisting ? existing : incoming }
        }
        if let direct = object["mcpServers"] as? [String: Any] { merge(direct) }
        guard let matchingProject,
              let projects = object["projects"] as? [String: Any]
        else { return }
        for (path, value) in projects where pathsReferToSameLocation(path, matchingProject.path) {
            if let project = value as? [String: Any],
               let projectServers = project["mcpServers"] as? [String: Any] {
                merge(projectServers)
            }
        }
    }

    static func pathsReferToSameLocation(_ lhs: String, _ rhs: String) -> Bool {
        URL(fileURLWithPath: lhs).standardizedFileURL.resolvingSymlinksInPath()
            == URL(fileURLWithPath: rhs).standardizedFileURL.resolvingSymlinksInPath()
    }

    static func hasManifest(_ manifest: String, in directory: URL) -> Bool {
        if AgentImportFileSystem.regularFile(directory.appendingPathComponent(manifest), inside: directory) != nil {
            return true
        }
        guard manifest == ".claude-plugin/plugin.json" else { return false }
        return AgentImportFileSystem.regularFile(
            directory.appendingPathComponent(".codex-plugin/plugin.json"),
            inside: directory
        ) != nil
    }

    static func sourceBoundary(for file: URL, locations: Locations) -> URL? {
        WorkspaceBoundary.isWithin(file, root: locations.sourceConfigDirectory)
            ? locations.sourceConfigDirectory
            : (WorkspaceBoundary.isWithin(file, root: locations.sourceRoot) ? locations.sourceRoot : nil)
    }
}
