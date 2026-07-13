import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools

public struct QuillCodeWorkspaceBootstrap: Sendable {
    public typealias ModelCatalogFetcher = @Sendable (AppConfig) async -> TrustedRouterModelCatalog

    public var paths: QuillCodePaths
    public var runtimeFactory: QuillCodeRuntimeFactory
    public var modelCatalogFetcher: ModelCatalogFetcher?

    public init(
        paths: QuillCodePaths = QuillCodePaths(),
        runtimeFactory: QuillCodeRuntimeFactory? = nil,
        modelCatalogFetcher: ModelCatalogFetcher? = nil
    ) {
        self.paths = paths
        self.runtimeFactory = runtimeFactory ?? QuillCodeRuntimeFactory(paths: paths)
        self.modelCatalogFetcher = modelCatalogFetcher
    }

    @MainActor
    public func makeModel() throws -> QuillCodeWorkspaceModel {
        try paths.ensure()
        let config = try ConfigStore(fileURL: paths.configFile).load()
        let threadStore = JSONThreadStore(directory: paths.threadsDirectory)
        let projectStore = JSONProjectStore(fileURL: paths.projectsFile)
        let automationStore = JSONAutomationStore(fileURL: paths.automationsFile)
        let sidebarSavedSearchStore = JSONSidebarSavedSearchStore(fileURL: paths.sidebarSavedSearchesFile)
        let projects = try projectStore.load()
        let threads = try threadStore.list()
        let automations = try automationStore.load()
        let sidebarSavedSearches = try sidebarSavedSearchStore.load()
        let selectedThreadID = threads.first(where: { !$0.isArchived })?.id
        let selectedProjectID = selectedThreadID
            .flatMap { id in threads.first { $0.id == id }?.projectID }
            ?? projects.first?.id
        let runtime = runtimeFactory.makeRuntime(config: config)
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
            projectStore: projectStore,
            automationStore: automationStore,
            sidebarSavedSearchStore: sidebarSavedSearchStore,
            permissionRuleStore: PermissionRuleFileStore(directory: paths.permissionsDirectory),
            globalMemoryDirectory: paths.memoriesDirectory,
            imageAttachmentStore: ImageAttachmentStore(directory: paths.attachmentsDirectory),
            worktreeSnapshotStore: ManagedWorktreeSnapshotStore(directory: paths.worktreeSnapshotsDirectory),
            managedWorktreeDefaultRoot: paths.worktreesDirectory,
            mcpSecretStore: MCPSecretStoreAdapter(
                backing: FileSecretStore(directory: paths.secretsDirectory)
            )
        )
        model.refreshSelectedProjectInstructions()
        model.enforceManagedWorktreeRetention()
        return model
    }

    public func saveConfig(_ config: AppConfig) throws {
        try paths.ensure()
        try ConfigStore(fileURL: paths.configFile).save(config)
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
}
