import Foundation
import QuillCodeCore

enum ClaudeCodeImportMaterializer {
    static func materialize(
        catalog: ClaudeCodeImportCatalog,
        selection: AgentImportSelection,
        existingProjects: [ProjectRef],
        existingThreads: [ChatThread],
        config: AppConfig
    ) -> AgentImportMutation {
        guard selection.source == .claudeCode else {
            return failureMutation(.unsupportedSource)
        }
        let selectedDescriptors = selection.candidateIDs.compactMap { catalog.descriptors[$0] }
            .filter { !$0.candidate.isPreviouslyImported }
        let allowedProjectPaths = Set(catalog.preview.projects.map(\.path))
        let selectedProjectPaths = selection.projectPaths.intersection(allowedProjectPaths)
        let runID = String(UUID().uuidString.lowercased().prefix(12))

        var diagnostics: [String] = []
        var followUps: [String] = []
        var importedIDs = Set<String>()
        var importedProjects: [ProjectRef] = []
        var importedThreads: [ChatThread] = []
        var createdArtifacts: [AgentImportCreatedArtifact] = []
        var counts: [AgentImportItemKind: Int] = [:]

        var existingProjectsByPath: [String: ProjectRef] = [:]
        for project in existingProjects {
            guard let path = normalizedLocalPath(project), existingProjectsByPath[path] == nil else { continue }
            existingProjectsByPath[path] = project
        }
        var projectsByPath = existingProjectsByPath
        for descriptor in selectedDescriptors where descriptor.candidate.kind == .projects {
            guard case .project(let url) = descriptor.payload,
                  selectedProjectPaths.contains(url.path)
            else { continue }
            if projectsByPath[url.path] != nil {
                importedIDs.insert(descriptor.candidate.id)
                continue
            }
            let project = ProjectRef(
                name: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent,
                path: url.path,
                runHooks: []
            )
            importedProjects.append(project)
            projectsByPath[url.path] = project
            markImported(descriptor, importedIDs: &importedIDs, counts: &counts)
        }

        for projectPath in selectedProjectPaths.sorted() {
            guard projectsByPath[projectPath] != nil else {
                diagnostics.append("Skipped setup for \(projectPath) because the project was not imported or already registered.")
                continue
            }
            let applicable = selectedDescriptors.filter {
                $0.candidate.projectPath == nil || $0.candidate.projectPath == projectPath
            }
            materializeProjectSetup(
                applicable,
                projectRoot: URL(fileURLWithPath: projectPath),
                runID: runID,
                existingReceiptIDs: catalog.receiptIDs,
                importedIDs: &importedIDs,
                counts: &counts,
                createdArtifacts: &createdArtifacts,
                followUps: &followUps,
                diagnostics: &diagnostics
            )
        }

        let importedSessionIDs = Set(existingThreads.compactMap(importedSessionID))
        var seenSessionIDs = importedSessionIDs
        for descriptor in selectedDescriptors where descriptor.candidate.kind == .chats {
            guard case .transcript(_, let transcript) = descriptor.payload,
                  let projectPath = descriptor.candidate.projectPath,
                  selectedProjectPaths.contains(projectPath),
                  let project = projectsByPath[projectPath],
                  seenSessionIDs.insert(transcript.sessionID).inserted
            else { continue }
            importedThreads.append(importedThread(transcript, project: project, config: config))
            markImported(descriptor, importedIDs: &importedIDs, counts: &counts)
        }

        let selectedFreshCount = selectedDescriptors.count
        let selectedWorkCount = selectedDescriptors.reduce(into: 0) { count, descriptor in
            if descriptor.candidate.kind.isProjectSetupItem {
                let targets = descriptor.candidate.projectPath.map { [$0] } ?? selectedProjectPaths.sorted()
                count += targets.lazy.filter {
                    !catalog.receiptIDs.contains(
                        AgentImportReceiptKey.value(
                            for: descriptor.candidate,
                            destinationProjectPath: $0
                        )
                    )
                }.count
            } else {
                count += 1
            }
        }
        let skippedCount = max(0, max(selectedFreshCount, selectedWorkCount) - importedIDs.count)
        return AgentImportMutation(
            projects: importedProjects,
            threads: importedThreads,
            createdArtifacts: createdArtifacts,
            importedCandidateIDs: importedIDs,
            outcome: AgentImportOutcome(
                source: .claudeCode,
                imported: counts.map { AgentImportCount(kind: $0.key, count: $0.value) },
                skippedCount: skippedCount,
                setupFollowUps: unique(followUps),
                diagnostics: unique(diagnostics)
            )
        )
    }

    private static func materializeProjectSetup(
        _ descriptors: [ClaudeCodeImportDescriptor],
        projectRoot: URL,
        runID: String,
        existingReceiptIDs: Set<String>,
        importedIDs: inout Set<String>,
        counts: inout [AgentImportItemKind: Int],
        createdArtifacts: inout [AgentImportCreatedArtifact],
        followUps: inout [String],
        diagnostics: inout [String]
    ) {
        let projectRoot = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        guard let values = try? projectRoot.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true,
              values.isSymbolicLink != true
        else {
            diagnostics.append("Skipped unavailable project \(projectRoot.path).")
            return
        }

        let pendingDescriptors = descriptors.filter {
            !existingReceiptIDs.contains(
                AgentImportReceiptKey.value(for: $0.candidate, destinationProjectPath: projectRoot.path)
            )
        }

        materializeInstructions(
            pendingDescriptors,
            projectRoot: projectRoot,
            runID: runID,
            importedIDs: &importedIDs,
            counts: &counts,
            createdArtifacts: &createdArtifacts,
            diagnostics: &diagnostics
        )
        materializeSettingsSnapshots(
            pendingDescriptors,
            projectRoot: projectRoot,
            runID: runID,
            importedIDs: &importedIDs,
            counts: &counts,
            createdArtifacts: &createdArtifacts,
            followUps: &followUps,
            diagnostics: &diagnostics
        )
        materializeImportedPlugins(
            pendingDescriptors,
            projectRoot: projectRoot,
            importedIDs: &importedIDs,
            counts: &counts,
            createdArtifacts: &createdArtifacts,
            followUps: &followUps,
            diagnostics: &diagnostics
        )
        materializeGeneratedPlugin(
            pendingDescriptors,
            projectRoot: projectRoot,
            runID: runID,
            importedIDs: &importedIDs,
            counts: &counts,
            createdArtifacts: &createdArtifacts,
            followUps: &followUps,
            diagnostics: &diagnostics
        )
    }

    private static func materializeInstructions(
        _ descriptors: [ClaudeCodeImportDescriptor],
        projectRoot: URL,
        runID: String,
        importedIDs: inout Set<String>,
        counts: inout [AgentImportItemKind: Int],
        createdArtifacts: inout [AgentImportCreatedArtifact],
        diagnostics: inout [String]
    ) {
        let instructions = descriptors.filter { $0.candidate.kind == .instructions }
        guard !instructions.isEmpty else { return }
        var sections: [String] = []
        var successful: [ClaudeCodeImportDescriptor] = []
        for descriptor in instructions {
            guard case .instruction(let file) = descriptor.payload,
                  let text = AgentImportFileSystem.readText(file, inside: descriptor.sourceRoot)
            else { continue }
            sections.append("## Imported from \(file.path)\n\n\(text)")
            successful.append(descriptor)
        }
        guard !sections.isEmpty,
              let data = ("# Imported Claude Code instructions\n\n" + sections.joined(separator: "\n\n"))
                .data(using: .utf8)
        else { return }
        let destination = projectRoot
            .appendingPathComponent(".quillcode/rules", isDirectory: true)
            .appendingPathComponent("imported-claude-\(runID).md")
        do {
            try AgentImportFileSystem.writeNew(data, to: destination, inside: projectRoot)
            createdArtifacts.append(createdArtifact(destination, projectRoot: projectRoot))
            successful.forEach {
                markImported(
                    $0,
                    destinationProjectPath: projectRoot.path,
                    importedIDs: &importedIDs,
                    counts: &counts
                )
            }
        } catch {
            diagnostics.append("Could not import instructions into \(projectRoot.lastPathComponent): \(error)")
        }
    }

    private static func importedThread(
        _ transcript: ClaudeCodeTranscriptSummary,
        project: ProjectRef,
        config: AppConfig
    ) -> ChatThread {
        let provenance = AgentImportThreadProvenance(source: .claudeCode, sourceID: transcript.sessionID)
        let payload = (try? JSONEncoder().encode([AgentImportThreadProvenance.payloadKey: provenance]))
            .flatMap { String(data: $0, encoding: .utf8) }
        return ChatThread(
            title: transcript.title,
            projectID: project.id,
            mode: config.mode,
            model: config.defaultModel,
            messages: transcript.messages,
            events: [
                ThreadEvent(
                    kind: .notice,
                    createdAt: transcript.updatedAt,
                    summary: "Imported from Claude Code",
                    payloadJSON: payload
                )
            ],
            createdAt: transcript.createdAt,
            updatedAt: transcript.updatedAt,
            instructions: project.instructions,
            memories: project.memories
        )
    }

    private static func importedSessionID(_ thread: ChatThread) -> String? {
        guard let provenance = AgentImportThreadProvenance.value(in: thread),
              provenance.source == .claudeCode
        else { return nil }
        return provenance.sourceID
    }

    private static func normalizedLocalPath(_ project: ProjectRef) -> String? {
        guard !project.connection.isRemote else { return nil }
        return URL(fileURLWithPath: project.path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func markImported(
        _ descriptor: ClaudeCodeImportDescriptor,
        destinationProjectPath: String? = nil,
        importedIDs: inout Set<String>,
        counts: inout [AgentImportItemKind: Int]
    ) {
        let receiptID = AgentImportReceiptKey.value(
            for: descriptor.candidate,
            destinationProjectPath: destinationProjectPath
        )
        guard importedIDs.insert(receiptID).inserted else { return }
        counts[descriptor.candidate.kind, default: 0] += 1
    }

    static func uniqueName(_ base: String, used: inout Set<String>) -> String {
        if used.insert(base).inserted { return base }
        for index in 2...999 {
            let candidate = "\(base)-\(index)"
            if used.insert(candidate).inserted { return candidate }
        }
        return "\(base)-\(UUID().uuidString.lowercased().prefix(8))"
    }

    static func uniqueDictionaryKey(_ base: String, existing: [String: Any]) -> String {
        if existing[base] == nil { return base }
        for index in 2...999 where existing["\(base)-\(index)"] == nil {
            return "\(base)-\(index)"
        }
        return "\(base)-imported"
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func failureMutation(_ error: AgentImportError) -> AgentImportMutation {
        AgentImportMutation(
            outcome: AgentImportOutcome(source: .claudeCode, diagnostics: [error.description])
        )
    }

    static func createdArtifact(_ url: URL, projectRoot: URL) -> AgentImportCreatedArtifact {
        AgentImportCreatedArtifact(projectRootPath: projectRoot.path, path: url.path)
    }
}
