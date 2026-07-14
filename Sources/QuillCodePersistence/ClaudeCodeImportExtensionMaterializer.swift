import Foundation
import QuillCodeCore

extension ClaudeCodeImportMaterializer {
    static func materializeSettingsSnapshots(
        _ descriptors: [ClaudeCodeImportDescriptor],
        projectRoot: URL,
        runID: String,
        importedIDs: inout Set<String>,
        counts: inout [AgentImportItemKind: Int],
        createdArtifacts: inout [AgentImportCreatedArtifact],
        followUps: inout [String],
        diagnostics: inout [String]
    ) {
        for descriptor in descriptors where descriptor.candidate.kind == .settings {
            guard case .settings(let file) = descriptor.payload,
                  let data = AgentImportFileSystem.readData(file, inside: descriptor.sourceRoot),
                  let redacted = ClaudeCodeImportSanitizer.redactedJSON(data)
            else { continue }
            let suffix = String(descriptor.candidate.id.prefix(8))
            let destination = projectRoot
                .appendingPathComponent(".quillcode/imports/claude/\(runID)", isDirectory: true)
                .appendingPathComponent("settings-\(suffix).json")
            do {
                try AgentImportFileSystem.writeNew(redacted, to: destination, inside: projectRoot)
                createdArtifacts.append(createdArtifact(destination, projectRoot: projectRoot))
                markImported(
                    descriptor,
                    destinationProjectPath: projectRoot.path,
                    importedIDs: &importedIDs,
                    counts: &counts
                )
                followUps.append(
                    "Review imported Claude settings for \(projectRoot.lastPathComponent); "
                        + "secrets and provider-specific values were redacted rather than activated."
                )
            } catch {
                diagnostics.append(
                    "Could not preserve imported settings for \(projectRoot.lastPathComponent): \(error)"
                )
            }
        }
    }

    static func materializeImportedPlugins(
        _ descriptors: [ClaudeCodeImportDescriptor],
        projectRoot: URL,
        importedIDs: inout Set<String>,
        counts: inout [AgentImportItemKind: Int],
        createdArtifacts: inout [AgentImportCreatedArtifact],
        followUps: inout [String],
        diagnostics: inout [String]
    ) {
        for descriptor in descriptors where descriptor.candidate.kind == .plugins {
            guard case .plugin(let source) = descriptor.payload else { continue }
            let suffix = String(descriptor.candidate.id.prefix(8))
            let slug = AgentImportFileSystem.sanitizedComponent(
                descriptor.candidate.title,
                fallback: "plugin"
            )
            let destination = projectRoot
                .appendingPathComponent(".quillcode/plugins", isDirectory: true)
                .appendingPathComponent("\(slug)-imported-\(suffix)", isDirectory: true)
            do {
                _ = try AgentImportFileSystem.copyDirectory(
                    source,
                    sourceRoot: descriptor.sourceRoot,
                    to: destination,
                    destinationRoot: projectRoot
                )
                try ensureCodexPluginManifest(at: destination, projectRoot: projectRoot)
                createdArtifacts.append(createdArtifact(destination, projectRoot: projectRoot))
                markImported(
                    descriptor,
                    destinationProjectPath: projectRoot.path,
                    importedIDs: &importedIDs,
                    counts: &counts
                )
                followUps.append(
                    "Review and trust imported plugin \(descriptor.candidate.title) before running its tools or hooks."
                )
            } catch {
                try? FileManager.default.removeItem(at: destination)
                diagnostics.append("Could not import plugin \(descriptor.candidate.title): \(error)")
            }
        }
    }

    static func materializeGeneratedPlugin(
        _ descriptors: [ClaudeCodeImportDescriptor],
        projectRoot: URL,
        runID: String,
        importedIDs: inout Set<String>,
        counts: inout [AgentImportItemKind: Int],
        createdArtifacts: inout [AgentImportCreatedArtifact],
        followUps: inout [String],
        diagnostics: inout [String]
    ) {
        let supportedKinds: Set<AgentImportItemKind> = [
            .skills, .slashCommands, .subagents, .mcpServers, .hooks,
        ]
        let components = descriptors.filter { supportedKinds.contains($0.candidate.kind) }
        guard !components.isEmpty else { return }
        let packageRoot = projectRoot
            .appendingPathComponent(".quillcode/plugins", isDirectory: true)
            .appendingPathComponent("imported-claude-\(runID)", isDirectory: true)
        do {
            try AgentImportFileSystem.createDirectory(packageRoot, inside: projectRoot)
            let skillDescriptors = try materializeSkills(components, packageRoot: packageRoot)
            let mcpDescriptors = try materializeMCP(
                components,
                packageRoot: packageRoot,
                followUps: &followUps
            )
            let hookDescriptors = try materializeHooks(
                components,
                packageRoot: packageRoot,
                followUps: &followUps
            )
            let successful = skillDescriptors + mcpDescriptors + hookDescriptors
            guard !successful.isEmpty else {
                try? FileManager.default.removeItem(at: packageRoot)
                return
            }
            try writeGeneratedPluginManifest(
                packageRoot: packageRoot,
                projectRoot: projectRoot,
                runID: runID,
                hasSkills: !skillDescriptors.isEmpty,
                hasMCP: !mcpDescriptors.isEmpty,
                hasHooks: !hookDescriptors.isEmpty
            )
            createdArtifacts.append(createdArtifact(packageRoot, projectRoot: projectRoot))
            successful.forEach {
                markImported(
                    $0,
                    destinationProjectPath: projectRoot.path,
                    importedIDs: &importedIDs,
                    counts: &counts
                )
            }
        } catch {
            try? FileManager.default.removeItem(at: packageRoot)
            diagnostics.append(
                "Could not create the imported Claude extension package for "
                    + "\(projectRoot.lastPathComponent): \(error)"
            )
        }
    }

    private static func materializeSkills(
        _ descriptors: [ClaudeCodeImportDescriptor],
        packageRoot: URL
    ) throws -> [ClaudeCodeImportDescriptor] {
        var successful: [ClaudeCodeImportDescriptor] = []
        var usedNames = Set<String>()
        let skillKinds: Set<AgentImportItemKind> = [.skills, .slashCommands, .subagents]
        for descriptor in descriptors where skillKinds.contains(descriptor.candidate.kind) {
            let base = AgentImportFileSystem.sanitizedComponent(
                descriptor.candidate.title,
                fallback: "skill"
            )
            let destination = packageRoot.appendingPathComponent(
                "skills/\(uniqueName(base, used: &usedNames))",
                isDirectory: true
            )
            switch descriptor.payload {
            case .skill(let source):
                _ = try AgentImportFileSystem.copyDirectory(
                    source,
                    sourceRoot: descriptor.sourceRoot,
                    to: destination,
                    destinationRoot: packageRoot
                )
            case .slashCommand(let file), .subagent(let file):
                guard let text = AgentImportFileSystem.readText(file, inside: descriptor.sourceRoot),
                      let data = convertedSkill(text, descriptor: descriptor).data(using: .utf8)
                else { continue }
                try AgentImportFileSystem.writeNew(
                    data,
                    to: destination.appendingPathComponent("SKILL.md"),
                    inside: packageRoot
                )
            default:
                continue
            }
            successful.append(descriptor)
        }
        return successful
    }

    private static func materializeMCP(
        _ descriptors: [ClaudeCodeImportDescriptor],
        packageRoot: URL,
        followUps: inout [String]
    ) throws -> [ClaudeCodeImportDescriptor] {
        let selected = descriptors.filter { $0.candidate.kind == .mcpServers }
        guard !selected.isEmpty else { return [] }
        var servers: [String: Any] = [:]
        var successful: [ClaudeCodeImportDescriptor] = []
        for descriptor in selected {
            guard case .settingsSection(let file, let key) = descriptor.payload,
                  let object = ClaudeCodeImportSanitizer.jsonObject(
                    file,
                    sourceRoot: descriptor.sourceRoot
                  ),
                  let section = object[key] as? [String: Any]
            else { continue }
            for (name, value) in section.sorted(by: { $0.key < $1.key }) {
                guard let sanitized = ClaudeCodeImportSanitizer.sanitizedMCPServer(value) else {
                    continue
                }
                servers[uniqueDictionaryKey(name, existing: servers)] = sanitized
            }
            successful.append(descriptor)
        }
        guard !servers.isEmpty else { return [] }
        let data = try JSONSerialization.data(
            withJSONObject: ["mcpServers": servers],
            options: [.prettyPrinted, .sortedKeys]
        )
        try AgentImportFileSystem.writeNew(
            data,
            to: packageRoot.appendingPathComponent("mcp.json"),
            inside: packageRoot
        )
        followUps.append(
            "Reconnect credentials for imported MCP servers before enabling them; embedded secrets were not copied."
        )
        return successful
    }

    private static func materializeHooks(
        _ descriptors: [ClaudeCodeImportDescriptor],
        packageRoot: URL,
        followUps: inout [String]
    ) throws -> [ClaudeCodeImportDescriptor] {
        let selected = descriptors.filter { $0.candidate.kind == .hooks }
        guard !selected.isEmpty else { return [] }
        var hooks: [String: [Any]] = [:]
        var successful: [ClaudeCodeImportDescriptor] = []
        for descriptor in selected {
            guard case .settingsSection(let file, let key) = descriptor.payload,
                  let object = ClaudeCodeImportSanitizer.jsonObject(
                    file,
                    sourceRoot: descriptor.sourceRoot
                  ),
                  let section = object[key] as? [String: Any]
            else { continue }
            for (event, value) in section {
                guard let groups = value as? [Any] else { continue }
                hooks[event, default: []].append(
                    contentsOf: groups.map { ClaudeCodeImportSanitizer.redact($0, key: nil) }
                )
            }
            successful.append(descriptor)
        }
        guard !hooks.isEmpty else { return [] }
        let data = try JSONSerialization.data(
            withJSONObject: ["hooks": hooks],
            options: [.prettyPrinted, .sortedKeys]
        )
        try AgentImportFileSystem.writeNew(
            data,
            to: packageRoot.appendingPathComponent("hooks/hooks.json"),
            inside: packageRoot
        )
        followUps.append("Review and trust imported hooks in Extensions before they can run.")
        return successful
    }

    private static func writeGeneratedPluginManifest(
        packageRoot: URL,
        projectRoot: URL,
        runID: String,
        hasSkills: Bool,
        hasMCP: Bool,
        hasHooks: Bool
    ) throws {
        var payload: [String: Any] = [
            "name": "imported-claude-\(runID)",
            "version": "1.0.0",
            "description": "Setup imported additively from Claude Code.",
        ]
        if hasSkills { payload["skills"] = "./skills" }
        if hasMCP { payload["mcpServers"] = "./mcp.json" }
        if hasHooks { payload["hooks"] = "./hooks/hooks.json" }
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
        try AgentImportFileSystem.writeNew(
            data,
            to: packageRoot.appendingPathComponent(".codex-plugin/plugin.json"),
            inside: projectRoot
        )
    }

    private static func ensureCodexPluginManifest(at packageRoot: URL, projectRoot: URL) throws {
        let codex = packageRoot.appendingPathComponent(".codex-plugin/plugin.json")
        if AgentImportFileSystem.regularFile(codex, inside: packageRoot) != nil { return }
        let claude = packageRoot.appendingPathComponent(".claude-plugin/plugin.json")
        guard let data = AgentImportFileSystem.readData(claude, inside: packageRoot) else {
            throw AgentImportError.invalidSourceOrDestination
        }
        try AgentImportFileSystem.writeNew(data, to: codex, inside: projectRoot)
    }

    private static func convertedSkill(
        _ content: String,
        descriptor: ClaudeCodeImportDescriptor
    ) -> String {
        let origin = descriptor.candidate.kind == .subagents ? "subagent" : "slash command"
        return """
        ---
        name: \(AgentImportFileSystem.sanitizedComponent(descriptor.candidate.title, fallback: "imported-workflow"))
        description: Imported Claude Code \(origin). Review tool and permission assumptions before first use.
        ---

        # Imported from Claude Code

        \(content)
        """
    }
}
