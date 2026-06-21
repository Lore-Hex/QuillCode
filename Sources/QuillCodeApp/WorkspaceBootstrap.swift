import Foundation
import QuillCodeCore
import QuillCodePersistence

public struct QuillCodeWorkspaceBootstrap: Sendable {
    public var paths: QuillCodePaths
    public var runtimeFactory: QuillCodeRuntimeFactory

    public init(
        paths: QuillCodePaths = QuillCodePaths(),
        runtimeFactory: QuillCodeRuntimeFactory? = nil
    ) {
        self.paths = paths
        self.runtimeFactory = runtimeFactory ?? QuillCodeRuntimeFactory(paths: paths)
    }

    @MainActor
    public func makeModel() throws -> QuillCodeWorkspaceModel {
        try paths.ensure()
        let config = try ConfigStore(fileURL: paths.configFile).load()
        let threadStore = JSONThreadStore(directory: paths.threadsDirectory)
        let projectStore = JSONProjectStore(fileURL: paths.projectsFile)
        let secretStore = FileSecretStore(directory: paths.secretsDirectory)
        let projects = try projectStore.load()
        let threads = try threadStore.list()
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
                trustedRouterAPIKeyConfigured: Self.hasTrustedRouterAPIKey(secretStore: secretStore)
            ),
            runner: runtime.runner,
            threadStore: threadStore,
            projectStore: projectStore,
            globalMemoryDirectory: paths.memoriesDirectory
        )
        model.refreshSelectedProjectInstructions()
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
        Self.hasTrustedRouterAPIKey(secretStore: FileSecretStore(directory: paths.secretsDirectory))
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

    public func fetchModelCatalog(config: AppConfig) async -> [ModelInfo] {
        await runtimeFactory.fetchModelCatalog(config: config).models
    }

    private static func hasTrustedRouterAPIKey(secretStore: FileSecretStore) -> Bool {
        let value = try? secretStore.read(QuillSecretKeys.trustedRouterAPIKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false
    }
}
