import Foundation
import QuillCodeCore

struct WorkspaceTopBarSurfaceBuilder: Sendable, Hashable {
    var topBarState: TopBarState
    var thread: ChatThread?
    var projectName: String?
    var instructions: [ProjectInstruction]
    var memories: [MemoryNote]
    var modelCatalog: [ModelInfo]
    var defaultModelID: String
    var favoriteModelIDs: [String]
    var recentThreads: [ChatThread]
    var runtimeIssue: RuntimeIssueSurface?

    func surface() -> TopBarSurface {
        let modelCatalog = modelCatalogBuilder()
        return TopBarSurface(
            appName: topBarState.appName,
            primaryTitle: thread?.title ?? "QuillCode",
            subtitle: WorkspaceStatusTextBuilder.topBarSubtitle(
                projectName: projectName ?? "No project",
                thread: thread
            ),
            instructionLabel: WorkspaceStatusTextBuilder.instructionLabel(for: instructions),
            instructionSources: instructions.map(\.path),
            memoryLabel: WorkspaceStatusTextBuilder.memoryLabel(for: memories),
            memorySources: memories.map(\.relativePath),
            modelLabel: modelCatalog.modelLabel(),
            selectedModelID: topBarState.model,
            modelCategories: modelCatalog.categories(),
            modeLabel: WorkspaceStatusTextBuilder.modeLabel(topBarState.mode),
            agentStatus: topBarState.agentStatus,
            runtimeIssueLabel: runtimeIssue?.title,
            runtimeIssueSeverity: runtimeIssue?.severity,
            computerUseLabel: topBarState.computerUseStatus.message,
            showsComputerUseSetup: !topBarState.computerUseStatus.available,
            branchStatusLabel: topBarState.branchStatus.flatMap { status in
                let label = status.compactLabel
                return label.isEmpty ? nil : label
            },
            usageStatusLabel: thread.flatMap { thread in
                WorkspaceTokenUsageLabelBuilder.label(
                    for: WorkspaceContextBannerBuilder.latestProviderUsage(for: thread)
                )
            }
        )
    }

    private func modelCatalogBuilder() -> WorkspaceModelCatalogSurfaceBuilder {
        WorkspaceModelCatalogSurfaceBuilder(
            catalog: modelCatalog,
            selectedModelID: topBarState.model,
            defaultModelID: defaultModelID,
            favoriteModelIDs: favoriteModelIDs,
            recentModelIDs: recentModelIDs()
        )
    }

    private func recentModelIDs() -> [String] {
        recentThreads
            .filter { !$0.isArchived }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map(\.model)
    }
}
