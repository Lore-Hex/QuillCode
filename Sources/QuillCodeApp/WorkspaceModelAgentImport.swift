import Foundation
import QuillCodeCore
import QuillCodePersistence

@MainActor
extension QuillCodeWorkspaceModel {
    public func discoverAgentImport() async -> AgentImportPreview {
        guard let agentImporter else {
            return AgentImportPreview(
                source: .claudeCode,
                diagnostics: ["Import is unavailable in this QuillCode session."]
            )
        }
        let projects = root.projects
        return await Task.detached(priority: .userInitiated) {
            agentImporter.discover(existingProjects: projects)
        }.value
    }

    public func performAgentImport(_ selection: AgentImportSelection) async -> AgentImportOutcome {
        guard let agentImporter else {
            return AgentImportOutcome(
                source: selection.source,
                diagnostics: ["Import is unavailable in this QuillCode session."]
            )
        }
        let projectSnapshot = root.projects
        let threadSnapshot = root.threads
        let configSnapshot = root.config
        let mutation = await Task.detached(priority: .userInitiated) {
            agentImporter.prepareImport(
                selection: selection,
                existingProjects: projectSnapshot,
                existingThreads: threadSnapshot,
                config: configSnapshot
            )
        }.value
        guard !mutation.importedCandidateIDs.isEmpty else { return mutation.outcome }

        let merge = mergeAgentImport(mutation, sourceProjects: projectSnapshot)
        do {
            try persistAgentImport(merge)
        } catch {
            agentImporter.rollbackArtifacts(in: mutation)
            return mutation.outcome.addingDiagnostic(
                "The import could not be committed: \(error.localizedDescription)"
            )
        }

        do {
            try agentImporter.commit(mutation.importedCandidateIDs)
        } catch {
            rollbackAgentImportPersistence(merge, previousProjects: projectSnapshot)
            agentImporter.rollbackArtifacts(in: mutation)
            return mutation.outcome.addingDiagnostic(
                "The import could not be committed: \(error.localizedDescription)"
            )
        }

        root.projects = merge.projects
        root.threads.append(contentsOf: merge.threads)
        refreshImportedProjectMetadata(selection.projectPaths)
        refreshImportedThreadContext(Set(merge.threads.map(\.id)))
        saveProjects()
        refreshFileMentionIndex()
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        setLastError(nil)
        return mutation.outcome
    }

    private func mergeAgentImport(
        _ mutation: AgentImportMutation,
        sourceProjects: [ProjectRef]
    ) -> AgentImportWorkspaceMerge {
        var projects = root.projects
        var currentProjectByPath = Dictionary(
            projects.compactMap { project in
                normalizedImportProjectPath(project).map { ($0, project) }
            },
            uniquingKeysWith: { current, _ in current }
        )
        for project in mutation.projects {
            guard let path = normalizedImportProjectPath(project), currentProjectByPath[path] == nil else {
                continue
            }
            projects.append(project)
            currentProjectByPath[path] = project
        }

        let sourceProjectByID = Dictionary(
            (sourceProjects + mutation.projects).map { ($0.id, $0) },
            uniquingKeysWith: { current, _ in current }
        )
        let existingProvenance = Set(root.threads.compactMap(AgentImportThreadProvenance.value))
        let threads = mutation.threads.compactMap { imported -> ChatThread? in
            guard let provenance = AgentImportThreadProvenance.value(in: imported),
                  !existingProvenance.contains(provenance)
            else { return nil }
            var imported = imported
            if let sourceID = imported.projectID,
               let source = sourceProjectByID[sourceID],
               let path = normalizedImportProjectPath(source),
               let current = currentProjectByPath[path] {
                imported.projectID = current.id
            }
            return imported
        }
        return AgentImportWorkspaceMerge(projects: projects, threads: threads)
    }

    private func persistAgentImport(_ merge: AgentImportWorkspaceMerge) throws {
        let previousProjects = root.projects
        var savedThreadIDs: [UUID] = []
        do {
            try saveProjectsOrThrow(merge.projects)
            for thread in merge.threads {
                try threadPersistence.saveOrThrow(thread)
                savedThreadIDs.append(thread.id)
            }
        } catch {
            savedThreadIDs.forEach(threadPersistence.delete)
            try? saveProjectsOrThrow(previousProjects)
            throw error
        }
    }

    private func rollbackAgentImportPersistence(
        _ merge: AgentImportWorkspaceMerge,
        previousProjects: [ProjectRef]
    ) {
        merge.threads.forEach { threadPersistence.delete($0.id) }
        try? saveProjectsOrThrow(previousProjects)
    }

    private func refreshImportedProjectMetadata(_ importedPaths: Set<String>) {
        let normalizedPaths = Set(importedPaths.map {
            URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath().path
        })
        for project in root.projects {
            guard let path = normalizedImportProjectPath(project), normalizedPaths.contains(path) else { continue }
            refreshProjectMetadata(project.id)
        }
    }

    private func refreshImportedThreadContext(_ threadIDs: Set<UUID>) {
        for index in root.threads.indices where threadIDs.contains(root.threads[index].id) {
            let context = workspaceThreadContext(root.threads[index].projectID)
            root.threads[index].instructions = context.instructions
            root.threads[index].memories = context.memories
            threadPersistence.save(root.threads[index])
        }
    }

    private func normalizedImportProjectPath(_ project: ProjectRef) -> String? {
        guard !project.isRemote else { return nil }
        return URL(fileURLWithPath: project.path).standardizedFileURL.resolvingSymlinksInPath().path
    }
}

private struct AgentImportWorkspaceMerge {
    var projects: [ProjectRef]
    var threads: [ChatThread]
}

private extension AgentImportOutcome {
    func addingDiagnostic(_ diagnostic: String) -> AgentImportOutcome {
        AgentImportOutcome(
            source: source,
            imported: imported,
            skippedCount: skippedCount,
            setupFollowUps: setupFollowUps,
            diagnostics: diagnostics + [diagnostic]
        )
    }
}
