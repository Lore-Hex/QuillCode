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
        guard model.disconnectAll() else {
            refresh()
            return
        }

        draft = ""
        refresh()
    }

    private func cancelInteractiveTasks(_ tasks: QuillCodeDesktopTaskCoordinator) {
        tasks.cancel([.send, .terminal, .browserPreview])
    }
}
