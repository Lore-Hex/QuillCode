import Foundation

final class WorkspaceThreadPersistenceIssueTracker {
    private var failedThreadIDs: Set<UUID> = []

    var failedThreadCount: Int {
        failedThreadIDs.count
    }

    var runtimeIssue: RuntimeIssueSurface? {
        guard !failedThreadIDs.isEmpty else { return nil }
        let chatLabel = failedThreadIDs.count == 1 ? "chat" : "chats"
        return RuntimeIssueSurface(
            severity: .error,
            title: failedThreadIDs.count == 1
                ? "A chat change is not saved"
                : "Some chat changes are not saved",
            message: "Quill Cowork could not update its saved-chat files for "
                + "\(failedThreadIDs.count) \(chatLabel). The current session can continue, "
                + "but affected changes may not survive a relaunch. Check available disk space "
                + "and app-data permissions, or compact a very large chat. Make another change "
                + "to retry its full snapshot.",
            diagnostics: [
                RuntimeDiagnosticSurface(
                    label: "Affected chats",
                    value: String(failedThreadIDs.count)
                ),
                RuntimeDiagnosticSurface(label: "Private content included", value: "No")
            ]
        )
    }

    func recordFailure(for threadID: UUID) {
        failedThreadIDs.insert(threadID)
    }

    func recordSuccess(for threadID: UUID) {
        failedThreadIDs.remove(threadID)
    }

    func hasFailure(for threadID: UUID) -> Bool {
        failedThreadIDs.contains(threadID)
    }
}
