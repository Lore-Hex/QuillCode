import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeHooks
import QuillCodePersistence
import QuillCodeTools

public struct QuillCodeWorkspaceBootstrap: Sendable {
    public typealias ModelCatalogFetcher = @Sendable (AppConfig) async -> TrustedRouterModelCatalog
    public typealias AccountCreditsFetcher = @Sendable (AppConfig) async -> TrustedRouterCreditsRefreshResult

    public var paths: QuillCodePaths
    public var runtimeFactory: QuillCodeRuntimeFactory
    public var modelCatalogFetcher: ModelCatalogFetcher?
    public var accountCreditsFetcher: AccountCreditsFetcher?
    public var now: @Sendable () -> Date

    public init(
        paths: QuillCodePaths = QuillCodePaths(),
        runtimeFactory: QuillCodeRuntimeFactory? = nil,
        modelCatalogFetcher: ModelCatalogFetcher? = nil,
        accountCreditsFetcher: AccountCreditsFetcher? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.paths = paths
        self.runtimeFactory = runtimeFactory ?? QuillCodeRuntimeFactory(paths: paths)
        self.modelCatalogFetcher = modelCatalogFetcher
        self.accountCreditsFetcher = accountCreditsFetcher
        self.now = now
    }

    @MainActor
    public func makeModel(
        automaticStartupPolicy: WorkspaceAutomaticStartupPolicy = .startImmediately
    ) throws -> QuillCodeWorkspaceModel {
        var unreadableDataKinds: [WorkspaceStartupDataKind] = []
        do {
            try paths.ensure()
        } catch {
            unreadableDataKinds.append(.workspaceStorage)
        }
        let config: AppConfig
        do {
            config = try ConfigStore(fileURL: paths.configFile).load()
        } catch {
            config = AppConfig()
            unreadableDataKinds.append(.configuration)
        }
        let threadStore = JSONThreadStore(directory: paths.threadsDirectory)
        let composerDraftStore = ComposerDraftCheckpointStore(directory: paths.composerDraftsDirectory)
        let projectStore = JSONProjectStore(fileURL: paths.projectsFile)
        let automationStore = JSONAutomationStore(fileURL: paths.automationsFile)
        let sidebarSavedSearchStore = JSONSidebarSavedSearchStore(fileURL: paths.sidebarSavedSearchesFile)
        let storedProjects: [ProjectRef]
        do {
            storedProjects = try projectStore.load()
        } catch {
            storedProjects = []
            unreadableDataKinds.append(.projects)
        }
        let childStore = SubagentThreadStore(directory: paths.subagentThreadsDirectory)
        let payloadStore = SubagentApprovalPayloadStore(directory: paths.subagentApprovalPayloadsDirectory)
        let currentDate = now()
        let calendar = Calendar.current
        let threadListing = threadStore.bootstrapListing(
            deferArchivedBefore: .distantFuture,
            maximumResidentActivePayloads: JSONThreadStore.defaultMaximumResidentActivePayloads,
            retainingUsageSince: ThreadPeriodUsageSnapshot.currentPeriodRetentionStart(
                now: currentDate,
                calendar: calendar
            ),
            calendar: calendar,
            now: currentDate
        )
        let reconciliation = WorkspaceSubagentRelaunchReconciler.reconcile(
            threadListing.threads,
            childStore: childStore,
            payloadStore: payloadStore
        )
        let threads = reconciliation.threads
        var projects = storedProjects
        if !WorkspaceBootstrapProjectMigration.isComplete(in: paths.home)
            && !unreadableDataKinds.contains(.projects) {
            let migratedProjects = WorkspaceBootstrapProjectMigration.removingUnusedLegacyRootProject(
                from: storedProjects,
                threads: threads,
                hasThreadLoadIssues: !threadListing.issues.isEmpty
            )
            if migratedProjects != storedProjects {
                do {
                    try projectStore.save(migratedProjects)
                    projects = migratedProjects
                    try? WorkspaceBootstrapProjectMigration.markComplete(in: paths.home)
                } catch {
                    unreadableDataKinds.append(.projects)
                }
            } else {
                try? WorkspaceBootstrapProjectMigration.markComplete(in: paths.home)
            }
        }
        for thread in threads where reconciliation.changedThreadIDs.contains(thread.id) {
            do {
                try threadStore.save(thread)
            } catch {
                unreadableDataKinds.append(.chats)
            }
        }
        let automations: [QuillAutomation]
        do {
            automations = try automationStore.load()
        } catch {
            automations = []
            unreadableDataKinds.append(.automations)
        }
        let sidebarSavedSearches: [SidebarSavedSearch]
        do {
            sidebarSavedSearches = try sidebarSavedSearchStore.load()
        } catch {
            sidebarSavedSearches = []
            unreadableDataKinds.append(.savedSearches)
        }
        let selectedThreadID = threads.first(where: { !$0.isArchived })?.id
        let selectedProjectID = selectedThreadID
            .flatMap { id in threads.first { $0.id == id }?.projectID }
            ?? projects.first?.id
        let runtime = runtimeFactory.makeRuntime(config: config)
        let hookTrustStore = ProjectHookTrustFileStore(directory: paths.hookTrustDirectory)
        let globalHookConfiguration = GlobalHookConfigurationLoader
            .load(from: paths.hookConfigurationPaths)
            .resolvingTrust(hookTrustStore.load(forWorkspaceRoot: paths.home))
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                config: config,
                projects: projects,
                selectedProjectID: selectedProjectID,
                threads: threads,
                selectedThreadID: selectedThreadID,
                globalMemories: MemoryNoteLoader.loadGlobal(from: paths.memoriesDirectory),
                topBar: TopBarState(
                    model: selectedThreadID.flatMap { id in
                        threads.first { $0.id == id }?.model
                    } ?? config.defaultModel,
                    mode: selectedThreadID.flatMap { id in
                        threads.first { $0.id == id }?.mode
                    } ?? config.mode,
                    agentStatus: runtime.statusLabel
                ),
                trustedRouterAPIKeyConfigured: runtimeFactory.hasTrustedRouterAPIKey()
            ),
            automations: AutomationsState(items: automations),
            sidebarSavedSearches: sidebarSavedSearches,
            runner: runtime.runner,
            contextSummaryGenerator: runtime.contextSummaryGenerator,
            threadStore: threadStore,
            composerDraftStore: composerDraftStore,
            startupLoadIssue: WorkspaceStartupLoadIssue(
                loadedThreadCount: threads.count,
                threadLoadIssue: WorkspaceThreadLoadIssue(listing: threadListing),
                unreadableDataKinds: unreadableDataKinds
            ),
            projectStore: unreadableDataKinds.contains(.projects) ? nil : projectStore,
            automationStore: unreadableDataKinds.contains(.automations) ? nil : automationStore,
            sidebarSavedSearchStore: unreadableDataKinds.contains(.savedSearches)
                ? nil
                : sidebarSavedSearchStore,
            agentImporter: ClaudeCodeAgentImporter(
                sourceHomeDirectory: FileManager.default.homeDirectoryForCurrentUser,
                destinationPaths: paths
            ),
            permissionRuleStore: PermissionRuleFileStore(directory: paths.permissionsDirectory),
            projectHookTrustStore: hookTrustStore,
            hookConfigurationPaths: paths.hookConfigurationPaths,
            globalHookTrustScope: paths.home,
            globalHookConfiguration: globalHookConfiguration,
            subagentSessionStoreDirectory: paths.subagentSessionsDirectory,
            globalMemoryDirectory: paths.memoriesDirectory,
            pluginDataBaseDirectory: paths.pluginDataDirectory,
            imageAttachmentStore: ImageAttachmentStore(directory: paths.attachmentsDirectory),
            worktreeSnapshotStore: ManagedWorktreeSnapshotStore(directory: paths.worktreeSnapshotsDirectory),
            subagentThreadStore: childStore,
            subagentApprovalPayloadStore: payloadStore,
            managedWorktreeDefaultRoot: paths.worktreesDirectory,
            mcpSecretStore: MCPSecretStoreAdapter(
                backing: FileSecretStore(directory: paths.secretsDirectory)
            )
        )
        if automaticStartupPolicy == .startImmediately {
            model.startAutomaticStartupWork()
        }
        return model
    }

    public func saveConfig(_ config: AppConfig) throws {
        try paths.ensure()
        try ConfigStore(fileURL: paths.configFile).save(config)
    }

    public func saveSettingsTransaction(
        currentConfig: AppConfig,
        proposedConfig: AppConfig,
        credentialMutation: WorkspaceTrustedRouterCredentialMutation
    ) throws {
        let normalizedMutation: WorkspaceTrustedRouterCredentialMutation
        switch credentialMutation {
        case .replace(let credential):
            let trimmed = credential.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw WorkspaceSettingsPersistenceError(
                    failedKinds: [.trustedRouterCredential],
                    rollbackFailed: false
                )
            }
            normalizedMutation = .replace(trimmed)
        case .unchanged, .clear:
            normalizedMutation = credentialMutation
        }

        do {
            try paths.ensure()
        } catch {
            var kinds: Set<WorkspaceSettingsPersistenceKind> = [.configuration]
            if normalizedMutation.changesCredential {
                kinds.insert(.trustedRouterCredential)
            }
            throw WorkspaceSettingsPersistenceError(
                failedKinds: kinds,
                rollbackFailed: false
            )
        }

        let credentialStore = FileSecretStore(directory: paths.secretsDirectory)
        let transaction = WorkspaceSettingsPersistenceTransaction(
            saveConfiguration: { config in
                try ConfigStore(fileURL: paths.configFile).save(config)
            },
            readCredential: {
                try credentialStore.read(QuillSecretKeys.trustedRouterAPIKey)
            },
            writeCredential: { credential in
                try credentialStore.write(credential, for: QuillSecretKeys.trustedRouterAPIKey)
            },
            clearCredential: {
                try credentialStore.delete(QuillSecretKeys.trustedRouterAPIKey)
            }
        )
        try transaction.apply(
            currentConfig: currentConfig,
            proposedConfig: proposedConfig,
            credentialMutation: normalizedMutation
        )
    }

    public func makeRuntime(config: AppConfig) -> QuillCodeRuntime {
        runtimeFactory.makeRuntime(config: config)
    }

    public func hasTrustedRouterAPIKey() -> Bool {
        runtimeFactory.hasTrustedRouterAPIKey()
    }

    public func saveTrustedRouterAPIKey(_ apiKey: String) throws {
        try paths.ensure()
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try FileSecretStore(directory: paths.secretsDirectory)
            .write(trimmed, for: QuillSecretKeys.trustedRouterAPIKey)
    }

    public func clearTrustedRouterAPIKey() throws {
        try paths.ensure()
        try FileSecretStore(directory: paths.secretsDirectory)
            .delete(QuillSecretKeys.trustedRouterAPIKey)
    }

    public func fetchModelCatalog(config: AppConfig) async -> TrustedRouterModelCatalog {
        if let modelCatalogFetcher {
            return await modelCatalogFetcher(config)
        }
        return await runtimeFactory.fetchModelCatalog(config: config)
    }

    public func fetchTrustedRouterCredits(config: AppConfig) async -> TrustedRouterCreditsRefreshResult {
        if let accountCreditsFetcher {
            return await accountCreditsFetcher(config)
        }
        return await runtimeFactory.fetchTrustedRouterCredits(config: config)
    }
}
