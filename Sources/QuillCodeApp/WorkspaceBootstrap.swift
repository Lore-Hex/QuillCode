import Foundation
import QuillCodeCore
import QuillCodePersistence

public struct QuillCodeWorkspaceBootstrap: Sendable {
    public var paths: QuillCodePaths

    public init(paths: QuillCodePaths = QuillCodePaths()) {
        self.paths = paths
    }

    @MainActor
    public func makeModel() throws -> QuillCodeWorkspaceModel {
        try paths.ensure()
        let config = try ConfigStore(fileURL: paths.configFile).load()
        let threadStore = JSONThreadStore(directory: paths.threadsDirectory)
        let threads = try threadStore.list()
        let selectedThreadID = threads.first(where: { !$0.isArchived })?.id
        return QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                config: config,
                threads: threads,
                selectedThreadID: selectedThreadID
            ),
            threadStore: threadStore
        )
    }
}
