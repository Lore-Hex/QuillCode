import Foundation
import QuillCodeApp

@MainActor
struct QuillCodeDesktopActiveWorkCoordinator {
    func stopAll(
        draft: inout String,
        model: QuillCodeWorkspaceModel,
        tasks: QuillCodeDesktopTaskCoordinator,
        refresh: @escaping @MainActor () -> Void
    ) {
        cancelInteractiveTasks(tasks)
        cancelWorkflowRecording(model: model, tasks: tasks, refresh: refresh)
        model.cancelActiveWork()
        draft = ""
        refresh()
    }

    func disconnectAll(
        draft: inout String,
        model: QuillCodeWorkspaceModel,
        tasks: QuillCodeDesktopTaskCoordinator,
        refresh: @escaping @MainActor () -> Void
    ) {
        cancelInteractiveTasks(tasks)
        cancelWorkflowRecording(model: model, tasks: tasks, refresh: refresh)
        guard model.disconnectAll() else {
            refresh()
            return
        }

        draft = ""
        refresh()
    }

    private func cancelInteractiveTasks(_ tasks: QuillCodeDesktopTaskCoordinator) {
        tasks.cancelAllSends()
        tasks.cancelAllCodeReviews()
        tasks.cancel([.terminal, .browserPreview])
    }

    private func cancelWorkflowRecording(
        model: QuillCodeWorkspaceModel,
        tasks: QuillCodeDesktopTaskCoordinator,
        refresh: @escaping @MainActor () -> Void
    ) {
        tasks.replace(.workflowRecording) {
            await model.cancelWorkflowRecording()
        } onFinish: {
            refresh()
        }
    }
}
