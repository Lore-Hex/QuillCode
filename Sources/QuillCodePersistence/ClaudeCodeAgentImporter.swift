import Foundation
import QuillCodeCore

public struct ClaudeCodeAgentImporter: Sendable {
    public var sourceHomeDirectory: URL
    public var destinationPaths: QuillCodePaths

    public init(
        sourceHomeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        destinationPaths: QuillCodePaths = QuillCodePaths()
    ) {
        self.sourceHomeDirectory = sourceHomeDirectory.standardizedFileURL
        self.destinationPaths = destinationPaths
    }

    public func discover(existingProjects: [ProjectRef], now: Date = Date()) -> AgentImportPreview {
        let receipt = receiptStore.load(source: .claudeCode)
        return ClaudeCodeImportDiscovery.discover(
            sourceHomeDirectory: sourceHomeDirectory,
            existingProjects: existingProjects,
            receipt: receipt,
            now: now
        ).preview
    }

    public func prepareImport(
        selection: AgentImportSelection,
        existingProjects: [ProjectRef],
        existingThreads: [ChatThread],
        config: AppConfig,
        now: Date = Date()
    ) -> AgentImportMutation {
        let receipt = receiptStore.load(source: .claudeCode)
        let catalog = ClaudeCodeImportDiscovery.discover(
            sourceHomeDirectory: sourceHomeDirectory,
            existingProjects: existingProjects,
            receipt: receipt,
            now: now
        )
        return ClaudeCodeImportMaterializer.materialize(
            catalog: catalog,
            selection: selection,
            existingProjects: existingProjects,
            existingThreads: existingThreads,
            config: config
        )
    }

    public func commit(_ candidateIDs: Set<String>, at date: Date = Date()) throws {
        try destinationPaths.ensure()
        try receiptStore.record(candidateIDs, source: .claudeCode, at: date)
    }

    public func rollbackArtifacts(in mutation: AgentImportMutation) {
        AgentImportFileSystem.removeCreatedArtifacts(mutation.createdArtifacts)
    }

    private var receiptStore: AgentImportReceiptStore {
        AgentImportReceiptStore(fileURL: destinationPaths.agentImportReceiptFile)
    }
}
