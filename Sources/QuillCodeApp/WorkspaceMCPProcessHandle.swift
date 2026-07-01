final class WorkspaceMCPProcessHandle: @unchecked Sendable {
    let process: any WorkspaceMCPProcessControlling
    let session: any WorkspaceMCPSession

    init(
        process: any WorkspaceMCPProcessControlling,
        session: any WorkspaceMCPSession
    ) {
        self.process = process
        self.session = session
    }
}
