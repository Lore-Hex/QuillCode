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
        let threads = try threadStore.list()
        let selectedThreadID = threads.first(where: { !$0.isArchived })?.id
        let runtime = runtimeFactory.makeRuntime(config: config)
        return QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                config: config,
                threads: threads,
                selectedThreadID: selectedThreadID,
                topBar: TopBarState(
                    model: selectedThreadID.flatMap { id in
                        threads.first { $0.id == id }?.model
                    } ?? config.defaultModel,
                    mode: selectedThreadID.flatMap { id in
                        threads.first { $0.id == id }?.mode
                    } ?? config.mode,
                    agentStatus: runtime.statusLabel
                )
            ),
            runner: runtime.runner,
            threadStore: threadStore
        )
    }

    public func saveConfig(_ config: AppConfig) throws {
        try paths.ensure()
        try ConfigStore(fileURL: paths.configFile).save(config)
    }

    public func fetchModelCatalog(config: AppConfig) async -> [ModelInfo] {
        await runtimeFactory.fetchModelCatalog(config: config).models
    }
}
