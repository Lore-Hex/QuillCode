import Foundation
import QuillCodeApp

@MainActor
struct QuillCodeDesktopWorkflowRecordingCoordinator {
    func stopAndCreateSkill(
        model: QuillCodeWorkspaceModel,
        fallbackWorkspaceRoot: URL,
        tasks: QuillCodeDesktopTaskCoordinator,
        refresh: @escaping @MainActor () -> Void,
        onSlotFree: @escaping @MainActor () -> Void
    ) {
        tasks.startIfIdle(.workflowRecording) {
            do {
                let capture = try await model.stopWorkflowRecordingCapture()
                refresh()
                let originThreadID = capture.originThreadID.flatMap(UUID.init(uuidString:))
                    ?? model.selectedThread?.id
                tasks.enqueue(.send(originThreadID)) {
                    let runRoot = model.workspaceRoot(forThreadID: originThreadID)
                        ?? capture.workspaceRoot.map { URL(fileURLWithPath: $0, isDirectory: true) }
                        ?? fallbackWorkspaceRoot
                    await model.submitWorkflowRecordingCapture(
                        capture,
                        workspaceRoot: runRoot,
                        onStarted: refresh,
                        onProgressUpdated: refresh
                    )
                } onFinish: {
                    refresh()
                    onSlotFree()
                }
            } catch {
                refresh()
            }
        } onFinish: {
            refresh()
        }
    }
}
