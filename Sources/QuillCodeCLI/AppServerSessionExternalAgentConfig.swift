import Foundation
import QuillCodeCore
import QuillCodePersistence

struct AppServerExternalAgentConfigImportLaunch: Sendable {
    var importID: UUID
    var request: AppServerExternalAgentConfigImportRequest
}

extension AppServerSession {
    func detectExternalAgentConfig(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let request = try AppServerExternalAgentConfigDetectRequest(raw)
        let items = try await externalAgentConfigService.detect(
            cwds: request.cwds,
            includeHome: request.includeHome
        )
        return .object(["items": .array(items.map(\.appServerJSONValue))])
    }

    func readExternalAgentConfigImportHistories(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        try AppServerDiscoveryParams.requireEmpty(
            raw,
            method: "externalAgentConfig/import/readHistories"
        )
        let histories = try await externalAgentConfigService.histories()
        return .object(["data": .array(histories.map(\.appServerJSONValue))])
    }

    func prepareExternalAgentConfigImport(
        _ raw: CLIJSONValue
    ) throws -> AppServerExternalAgentConfigImportLaunch {
        .init(importID: UUID(), request: try AppServerExternalAgentConfigImportRequest(raw))
    }

    func launchExternalAgentConfigImport(_ launch: AppServerExternalAgentConfigImportLaunch) {
        guard !launch.request.migrationItems.isEmpty else { return }
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.performExternalAgentConfigImport(launch)
        }
        activeExternalAgentConfigImports[launch.importID] = task
    }

    func cancelAllExternalAgentConfigImports() {
        activeExternalAgentConfigImports.values.forEach { $0.cancel() }
    }
}

private extension AppServerSession {
    func performExternalAgentConfigImport(_ launch: AppServerExternalAgentConfigImportLaunch) async {
        defer { activeExternalAgentConfigImports[launch.importID] = nil }
        var itemResults: [ExternalAgentConfigImportTypeResult] = []
        for item in launch.request.migrationItems {
            guard !Task.isCancelled, !inputFinished else { return }
            let result = await externalAgentConfigService.importItem(item) { [weak self] session in
                guard let self else { throw CancellationError() }
                return try await self.persistExternalAgentSession(session)
            }
            guard !Task.isCancelled, !inputFinished else { return }
            itemResults.append(result)
            await sendNotification(
                "externalAgentConfig/import/progress",
                params: importNotification(importID: launch.importID, results: [result])
            )
        }
        guard !Task.isCancelled, !inputFinished else { return }

        let grouped = groupedImportResults(itemResults)
        let history = ExternalAgentConfigImportHistory(
            importId: launch.importID,
            completedAtMs: Int64((Date().timeIntervalSince1970 * 1_000).rounded()),
            successes: grouped.flatMap(\.successes),
            failures: grouped.flatMap(\.failures)
        )
        do {
            try await externalAgentConfigService.record(history)
        } catch {
            guard let item = launch.request.migrationItems.first else { return }
            let failure = ExternalAgentConfigImportFailure(
                itemType: item.itemType,
                cwd: item.cwd,
                errorType: "import_history_persistence_error",
                failureStage: "history_persistence",
                message: String(describing: error)
            )
            itemResults.append(.init(itemType: item.itemType, failures: [failure]))
        }

        await refreshExternalAgentConfigRuntimeState()
        let completed = groupedImportResults(itemResults)
        await sendNotification(
            "externalAgentConfig/import/completed",
            params: importNotification(importID: launch.importID, results: completed)
        )
    }

    func persistExternalAgentSession(_ imported: ExternalAgentConfigImportedSession) async throws -> UUID {
        let sourceID = AgentImportThreadProvenance.value(in: imported.thread)?.sourceID
        if let sourceID,
           let existing = await repository.list().first(where: {
               guard let provenance = AgentImportThreadProvenance.value(in: $0.thread) else {
                   return false
               }
               return provenance.source == .claudeCode && provenance.sourceID == sourceID
           }) {
            return existing.thread.id
        }

        let cwd = (imported.cwd ?? currentDirectory).standardizedFileURL.resolvingSymlinksInPath()
        let projectStore = JSONProjectStore(fileURL: paths.projectsFile)
        let originalProjects = try projectStore.load()
        var projects = originalProjects
        let project: ProjectRef
        if let existing = projects.first(where: { project in
            !project.connection.isRemote
                && URL(fileURLWithPath: project.path).standardizedFileURL.resolvingSymlinksInPath() == cwd
        }) {
            project = existing
        } else {
            project = ProjectRef(
                name: cwd.lastPathComponent.isEmpty ? cwd.path : cwd.lastPathComponent,
                path: cwd.path
            )
            projects.append(project)
            try projectStore.save(projects)
        }

        var thread = imported.thread
        thread.projectID = project.id
        do {
            try await repository.create(.init(
                thread: thread,
                settings: .init(
                    cwd: cwd,
                    approvalPolicy: .string("on-request"),
                    approvalsReviewer: appConfig.mode == .auto ? "auto_review" : "user",
                    sandbox: appConfig.mode == .readOnly ? .readOnly : .workspaceWrite
                )
            ))
        } catch {
            if projects != originalProjects { try? projectStore.save(originalProjects) }
            throw error
        }
        return thread.id
    }

    func groupedImportResults(
        _ results: [ExternalAgentConfigImportTypeResult]
    ) -> [ExternalAgentConfigImportTypeResult] {
        ExternalAgentConfigItemType.importOrder.compactMap { type in
            let matching = results.filter { $0.itemType == type }
            guard !matching.isEmpty else { return nil }
            return .init(
                itemType: type,
                successes: matching.flatMap(\.successes),
                failures: matching.flatMap(\.failures)
            )
        }
    }

    func importNotification(
        importID: UUID,
        results: [ExternalAgentConfigImportTypeResult]
    ) -> CLIJSONValue {
        .object([
            "importId": .string(importID.uuidString.lowercased()),
            "itemTypeResults": .array(results.map(\.appServerJSONValue)),
        ])
    }

    func refreshExternalAgentConfigRuntimeState() async {
        if let config = try? ConfigStore(fileURL: paths.configFile).load() {
            appConfig = config
        }
        cachedSkillSnapshots.removeAll()
        refreshSkillWatcher()
        await mcpRegistry.reload()
    }
}
