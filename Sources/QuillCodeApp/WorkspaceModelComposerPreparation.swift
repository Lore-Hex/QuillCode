import Foundation

@MainActor
extension QuillCodeWorkspaceModel {
    public var canRetryLastUserTurn: Bool {
        WorkspaceRetryPlanner.canRetryLastUserTurn(
            in: selectedThread,
            isSending: composer.isSending
        )
    }

    public func setDraft(_ draft: String) {
        composer.draft = draft
        persistCurrentComposerDraft()
    }

    /// Gives a first agent turn a stable chat owner before the desktop creates its task slot.
    /// View-only slash commands remain projectless and do not create an otherwise empty chat.
    @discardableResult
    public func prepareComposerSubmissionThread() -> UUID? {
        let submission = WorkspaceComposerSubmissionPlanner.plan(
            draft: composer.draft,
            hasAttachments: !composer.attachments.isEmpty
        )
        guard case .agent = submission else { return root.selectedThreadID }
        guard selectedThread == nil else { return root.selectedThreadID }

        let pendingDraft = composer.draft
        let pendingAttachments = composer.attachments
        let threadID = newChat()
        composer.draft = pendingDraft
        composer.attachments = pendingAttachments
        persistComposerDraft(pendingDraft, for: threadID)
        persistComposerAttachments(pendingAttachments, for: threadID)
        return threadID
    }

    @discardableResult
    public func prepareRetryLastUserTurn() -> Bool {
        guard let message = WorkspaceRetryPlanner.retryMessage(in: selectedThread) else {
            return false
        }
        setDraft(message.content)
        composer.attachments = message.attachments
        persistComposerAttachments(message.attachments, for: root.selectedThreadID)
        setLastError(nil)
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }
}
