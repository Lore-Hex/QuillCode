import Foundation

@MainActor
public extension QuillCodeWorkspaceModel {
    func loadSubagentTranscript(
        parentThreadID: UUID,
        runID: UUID,
        workerID: String
    ) -> WorkspaceSubagentTranscriptSurface? {
        guard let store = subagentThreadStore,
              let parent = root.threads.first(where: { $0.id == parentThreadID })
        else {
            setLastError("The delegated transcript is not available in this workspace.")
            return nil
        }
        do {
            let surface = try WorkspaceSubagentTranscriptLoader.load(
                parentThread: parent,
                runID: runID,
                workerID: workerID,
                store: store
            )
            setLastError(surface == nil ? "The delegated worker is no longer available." : nil)
            return surface
        } catch {
            setLastError("Could not open the delegated transcript: \(error.localizedDescription)")
            return nil
        }
    }
}
