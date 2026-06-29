import Foundation
import QuillCodeTools

enum WorkspaceTerminalProcessLauncher {
    static func startSession(for context: WorkspaceTerminalExecutionContext) -> any ShellInteractiveSession {
        guard context.remoteConnection == nil else {
            return ShellToolExecutor().startStreamingSession(context.request)
        }

        let session = PTYProcessSession(request: context.request)
        session.start()
        return session
    }
}
