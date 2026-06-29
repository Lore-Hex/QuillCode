import Foundation
import QuillCodeTools

enum WorkspaceTerminalProcessLauncher {
    static func startSession(
        for context: WorkspaceTerminalExecutionContext,
        windowSize: TerminalWindowSize?
    ) -> any ShellInteractiveSession {
        guard context.remoteConnection == nil else {
            return ShellToolExecutor().startStreamingSession(context.request)
        }

        let session = PTYProcessSession(
            request: context.request,
            windowSize: windowSize?.ptyWindowSize
        )
        session.start()
        return session
    }
}
