import Foundation

public enum WorkspaceMemoryPressureLevel: Sendable, Equatable {
    case warning
    case critical
}

public struct WorkspaceMemoryReclamation: Sendable, Equatable {
    public var releasedThreadPayloadCount: Int
    public var releasedFileMentionEntryCount: Int
    public var releasedInactiveProjectSurfaceCount: Int
    public var shouldReleaseLanguageServices: Bool

    public init(
        releasedThreadPayloadCount: Int = 0,
        releasedFileMentionEntryCount: Int = 0,
        releasedInactiveProjectSurfaceCount: Int = 0,
        shouldReleaseLanguageServices: Bool = false
    ) {
        self.releasedThreadPayloadCount = releasedThreadPayloadCount
        self.releasedFileMentionEntryCount = releasedFileMentionEntryCount
        self.releasedInactiveProjectSurfaceCount = releasedInactiveProjectSurfaceCount
        self.shouldReleaseLanguageServices = shouldReleaseLanguageServices
    }
}

@MainActor
public extension QuillCodeWorkspaceModel {
    /// Relinquishes state that can be rebuilt from durable storage or the active workspace.
    /// Selected, running, ephemeral, and persistence-failed chat payloads remain resident.
    func releaseReconstructibleMemory(
        for level: WorkspaceMemoryPressureLevel
    ) -> WorkspaceMemoryReclamation {
        ToolArtifactJSONDocumentReader.purgeCache()
        ToolArtifactTextPreviewBuilder.purgeCache()

        let loadedThreadPayloadCountBefore = loadedThreadPayloadCount
        enforceThreadPayloadResidency(
            maximumResidentActivePayloads: level == .warning ? 2 : 0
        )

        let projectSurfaceCountBefore = worktreeEnvironmentSurfacesByProjectID.count
        if let selectedProjectID = selectedProject?.id,
           let selectedSurface = worktreeEnvironmentSurfacesByProjectID[selectedProjectID] {
            worktreeEnvironmentSurfacesByProjectID = [selectedProjectID: selectedSurface]
        } else {
            worktreeEnvironmentSurfacesByProjectID.removeAll(keepingCapacity: false)
        }

        var releasedFileMentionEntryCount = 0
        if level == .critical {
            releasedFileMentionEntryCount = releaseFileMentionIndexForMemoryPressure()
        }

        return WorkspaceMemoryReclamation(
            releasedThreadPayloadCount: max(0, loadedThreadPayloadCountBefore - loadedThreadPayloadCount),
            releasedFileMentionEntryCount: releasedFileMentionEntryCount,
            releasedInactiveProjectSurfaceCount: max(
                0,
                projectSurfaceCountBefore - worktreeEnvironmentSurfacesByProjectID.count
            ),
            shouldReleaseLanguageServices: level == .critical && activeAgentRunCount == 0
        )
    }

    private var loadedThreadPayloadCount: Int {
        root.threads.lazy.filter { $0.payloadResidency.isLoaded }.count
    }
}
