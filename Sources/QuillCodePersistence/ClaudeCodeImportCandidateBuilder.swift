import Foundation
import QuillCodeCore

enum ClaudeCodeImportCandidateBuilder {
    static func appendProjects(
        _ projects: [URL],
        receipt: AgentImportReceipt,
        into descriptors: inout [String: ClaudeCodeImportDescriptor]
    ) {
        for project in projects {
            let id = AgentImportFileSystem.fingerprint(
                kind: .projects,
                path: project.path,
                data: Data(project.path.utf8)
            )
            let candidate = AgentImportCandidate(
                id: id,
                kind: .projects,
                title: project.lastPathComponent.isEmpty ? project.path : project.lastPathComponent,
                detail: project.path,
                projectPath: project.path,
                isPreviouslyImported: receipt.candidateIDs.contains(id)
            )
            descriptors[id] = ClaudeCodeImportDescriptor(
                candidate: candidate,
                payload: .project(project),
                sourceRoot: project
            )
        }
    }

    static func appendSetup(
        root: URL,
        projectPath: String?,
        receipt: AgentImportReceipt,
        into descriptors: inout [String: ClaudeCodeImportDescriptor]
    ) {
        guard let root = AgentImportFileSystem.directory(
            root,
            inside: root.deletingLastPathComponent()
        ) else { return }
        let scope = projectPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Global"
        appendInstruction(
            root.appendingPathComponent("CLAUDE.md"),
            sourceRoot: root,
            projectPath: projectPath,
            title: "\(scope) instructions",
            receipt: receipt,
            into: &descriptors
        )
        appendSettings(
            root.appendingPathComponent("settings.json"),
            sourceRoot: root,
            projectPath: projectPath,
            scope: scope,
            receipt: receipt,
            into: &descriptors
        )
        appendDirectories(
            root.appendingPathComponent("skills"),
            sourceRoot: root,
            projectPath: projectPath,
            kind: .skills,
            manifestNames: ["SKILL.md"],
            receipt: receipt,
            into: &descriptors
        )
        appendDirectories(
            root.appendingPathComponent("plugins"),
            sourceRoot: root,
            projectPath: projectPath,
            kind: .plugins,
            manifestNames: [".codex-plugin/plugin.json", ".claude-plugin/plugin.json"],
            requiresSetup: true,
            receipt: receipt,
            into: &descriptors
        )
        appendMarkdownFiles(
            root.appendingPathComponent("commands"),
            sourceRoot: root,
            projectPath: projectPath,
            kind: .slashCommands,
            receipt: receipt,
            into: &descriptors
        )
        appendMarkdownFiles(
            root.appendingPathComponent("agents"),
            sourceRoot: root,
            projectPath: projectPath,
            kind: .subagents,
            requiresSetup: true,
            receipt: receipt,
            into: &descriptors
        )
    }

    static func appendInstruction(
        _ file: URL,
        sourceRoot: URL,
        projectPath: String?,
        title: String,
        receipt: AgentImportReceipt,
        into descriptors: inout [String: ClaudeCodeImportDescriptor]
    ) {
        guard let data = AgentImportFileSystem.readData(file, inside: sourceRoot),
              String(data: data, encoding: .utf8) != nil
        else { return }
        append(
            kind: .instructions,
            title: title,
            detail: projectPath ?? "Applies to imported projects",
            projectPath: projectPath,
            sourcePath: file.path,
            fingerprintData: data,
            payload: .instruction(file),
            sourceRoot: sourceRoot,
            receipt: receipt,
            into: &descriptors
        )
    }

    static func appendTranscripts(
        _ transcripts: [(URL, ClaudeCodeTranscriptSummary)],
        sourceRoot: URL,
        projectPaths: Set<String>,
        receipt: AgentImportReceipt,
        into descriptors: inout [String: ClaudeCodeImportDescriptor]
    ) {
        for (file, summary) in transcripts {
            guard let projectPath = summary.cwd,
                  projectPaths.contains(projectPath),
                  let data = AgentImportFileSystem.readData(
                    file,
                    inside: sourceRoot,
                    maximumBytes: ClaudeCodeTranscriptParser.maximumFileBytes
                  )
            else { continue }
            append(
                kind: .chats,
                title: summary.title,
                detail: "\(summary.messages.count) messages | \(projectPath)",
                projectPath: projectPath,
                sourcePath: file.path,
                fingerprintData: data,
                payload: .transcript(file, summary),
                sourceRoot: sourceRoot,
                receipt: receipt,
                into: &descriptors
            )
        }
    }

    static func sort(_ lhs: AgentImportCandidate, _ rhs: AgentImportCandidate) -> Bool {
        if lhs.kind.sortOrder != rhs.kind.sortOrder {
            return lhs.kind.sortOrder < rhs.kind.sortOrder
        }
        if lhs.projectPath != rhs.projectPath {
            return (lhs.projectPath ?? "") < (rhs.projectPath ?? "")
        }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private static func appendSettings(
        _ file: URL,
        sourceRoot: URL,
        projectPath: String?,
        scope: String,
        receipt: AgentImportReceipt,
        into descriptors: inout [String: ClaudeCodeImportDescriptor]
    ) {
        guard let data = AgentImportFileSystem.readData(file, inside: sourceRoot),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        append(
            kind: .settings,
            title: "\(scope) settings",
            detail: "Preserved for review; secrets and provider-specific model settings are not activated.",
            projectPath: projectPath,
            sourcePath: file.path,
            fingerprintData: data,
            payload: .settings(file),
            sourceRoot: sourceRoot,
            requiresSetup: true,
            receipt: receipt,
            into: &descriptors
        )
        appendSettingsSection(
            "mcpServers",
            kind: .mcpServers,
            object: object,
            file: file,
            sourceRoot: sourceRoot,
            projectPath: projectPath,
            scope: scope,
            receipt: receipt,
            into: &descriptors
        )
        appendSettingsSection(
            "hooks",
            kind: .hooks,
            object: object,
            file: file,
            sourceRoot: sourceRoot,
            projectPath: projectPath,
            scope: scope,
            receipt: receipt,
            into: &descriptors
        )
    }

    private static func appendSettingsSection(
        _ key: String,
        kind: AgentImportItemKind,
        object: [String: Any],
        file: URL,
        sourceRoot: URL,
        projectPath: String?,
        scope: String,
        receipt: AgentImportReceipt,
        into descriptors: inout [String: ClaudeCodeImportDescriptor]
    ) {
        guard let section = object[key],
              JSONSerialization.isValidJSONObject(section),
              let data = try? JSONSerialization.data(withJSONObject: section, options: [.sortedKeys]),
              !data.isEmpty
        else { return }
        append(
            kind: kind,
            title: "\(scope) \(kind.displayName.lowercased())",
            detail: setupDetail(for: kind),
            projectPath: projectPath,
            sourcePath: "\(file.path)#\(key)",
            fingerprintData: data,
            payload: .settingsSection(file, key),
            sourceRoot: sourceRoot,
            requiresSetup: true,
            receipt: receipt,
            into: &descriptors
        )
    }

    private static func appendDirectories(
        _ directory: URL,
        sourceRoot: URL,
        projectPath: String?,
        kind: AgentImportItemKind,
        manifestNames: [String],
        requiresSetup: Bool = false,
        receipt: AgentImportReceipt,
        into descriptors: inout [String: ClaudeCodeImportDescriptor]
    ) {
        guard let directory = AgentImportFileSystem.directory(directory, inside: sourceRoot),
              let entries = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
              )
        else { return }
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard AgentImportFileSystem.directory(entry, inside: directory) != nil,
                  manifestNames.contains(where: {
                    AgentImportFileSystem.regularFile(entry.appendingPathComponent($0), inside: entry) != nil
                  }),
                  let fingerprintData = directoryFingerprint(entry, sourceRoot: directory)
            else { continue }
            append(
                kind: kind,
                title: entry.lastPathComponent,
                detail: projectPath ?? "Global \(kind.displayName.lowercased())",
                projectPath: projectPath,
                sourcePath: entry.path,
                fingerprintData: fingerprintData,
                payload: kind == .skills ? .skill(entry) : .plugin(entry),
                sourceRoot: directory,
                requiresSetup: requiresSetup,
                receipt: receipt,
                into: &descriptors
            )
        }
    }

    private static func appendMarkdownFiles(
        _ directory: URL,
        sourceRoot: URL,
        projectPath: String?,
        kind: AgentImportItemKind,
        requiresSetup: Bool = false,
        receipt: AgentImportReceipt,
        into descriptors: inout [String: ClaudeCodeImportDescriptor]
    ) {
        guard let directory = AgentImportFileSystem.directory(directory, inside: sourceRoot),
              let entries = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
              )
        else { return }
        for file in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            where file.pathExtension.lowercased() == "md" {
            guard let data = AgentImportFileSystem.readData(file, inside: directory),
                  String(data: data, encoding: .utf8) != nil
            else { continue }
            append(
                kind: kind,
                title: file.deletingPathExtension().lastPathComponent,
                detail: projectPath ?? "Global \(kind.displayName.lowercased())",
                projectPath: projectPath,
                sourcePath: file.path,
                fingerprintData: data,
                payload: kind == .slashCommands ? .slashCommand(file) : .subagent(file),
                sourceRoot: directory,
                requiresSetup: requiresSetup,
                receipt: receipt,
                into: &descriptors
            )
        }
    }

    private static func append(
        kind: AgentImportItemKind,
        title: String,
        detail: String,
        projectPath: String?,
        sourcePath: String,
        fingerprintData: Data,
        payload: ClaudeCodeImportDescriptor.Payload,
        sourceRoot: URL,
        requiresSetup: Bool = false,
        receipt: AgentImportReceipt,
        into descriptors: inout [String: ClaudeCodeImportDescriptor]
    ) {
        let id = AgentImportFileSystem.fingerprint(
            kind: kind,
            path: sourcePath,
            data: fingerprintData
        )
        let candidate = AgentImportCandidate(
            id: id,
            kind: kind,
            title: String(title.prefix(160)),
            detail: String(detail.prefix(500)),
            projectPath: projectPath,
            requiresSetup: requiresSetup,
            isPreviouslyImported: receipt.candidateIDs.contains(id)
        )
        descriptors[id] = ClaudeCodeImportDescriptor(
            candidate: candidate,
            payload: payload,
            sourceRoot: sourceRoot
        )
    }

    private static func directoryFingerprint(_ directory: URL, sourceRoot: URL) -> Data? {
        guard let files = AgentImportFileSystem.boundedDirectoryFiles(at: directory, root: sourceRoot) else {
            return nil
        }
        var data = Data()
        for file in files {
            let relative = AgentImportFileSystem.relativePath(file, inside: directory)
            guard let contents = AgentImportFileSystem.readData(file, inside: directory) else {
                return nil
            }
            data.append(Data(relative.utf8))
            data.append(0)
            data.append(contents)
            data.append(0)
        }
        return data
    }

    private static func setupDetail(for kind: AgentImportItemKind) -> String {
        kind == .mcpServers
            ? "Connection credentials may need to be entered again."
            : "Imported hooks require explicit trust before they run."
    }
}
