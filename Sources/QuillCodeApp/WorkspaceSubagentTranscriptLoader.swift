import Foundation
import QuillCodeCore
import QuillCodePersistence

enum WorkspaceSubagentTranscriptLoader {
    static func load(
        parentThread: ChatThread,
        runID: UUID,
        workerID: String,
        store: SubagentThreadStore
    ) throws -> WorkspaceSubagentTranscriptSurface? {
        guard let run = parentThread.subagentRuns.first(where: { $0.id == runID }),
              let worker = run.workers.first(where: { $0.id == workerID })
        else {
            return nil
        }
        let child = try store.load(worker.childThreadID)
        return WorkspaceSubagentTranscriptSurface(
            parentThreadID: parentThread.id,
            run: run,
            worker: worker,
            thread: child
        )
    }
}
