import Foundation
import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
    /// Stashes the outgoing thread's draft and restores the incoming thread's
    /// draft when lifecycle changes reassign the selected thread.
    func applyThreadDraftSelection(to newID: UUID?, removing removed: UUID? = nil) {
        let outgoing = root.selectedThreadID
        if outgoing != newID {
            restoreComposerDraft(from: outgoing, to: newID)
        }
        if let removed {
            threadDrafts = ComposerDraftStore.cleared(removed, drafts: threadDrafts)
        }
    }

    public func selectThread(_ id: UUID, recordsNavigation: Bool = true) {
        guard let thread = root.threads.first(where: { $0.id == id }) else { return }
        let previousLocation = currentNavigationLocation
        // The user is leaving the current thread: persist its morning-triage return watermark to its
        // current tail so background growth on it surfaces as "unseen" on return (cross-session).
        // Only on an actual thread switch, mirroring the transcript tracker's leave transition.
        if let outgoing = root.selectedThreadID, outgoing != id {
            persistOutgoingReturnWatermark()
        }
        restoreComposerDraft(from: root.selectedThreadID, to: id)
        selectThreadRecord(id, projectID: thread.projectID)
        if recordsNavigation {
            recordNavigationTransition(from: previousLocation)
        }
    }

    @discardableResult
    func insertCreatedThread(
        _ thread: ChatThread,
        selectedProjectID: UUID?,
        saveThread: Bool
    ) -> UUID {
        let previousLocation = currentNavigationLocation
        // Leaving the current thread for a newly created one (New Chat / fork / compact): persist its
        // return watermark, mirroring the harness's newChat() → markTranscriptSeen.
        if let outgoing = root.selectedThreadID, outgoing != thread.id {
            persistOutgoingReturnWatermark()
        }
        clearSidebarSelection()
        restoreComposerDraft(from: root.selectedThreadID, to: thread.id)
        root.threads.insert(thread, at: 0)
        selectThreadRecord(thread.id, projectID: selectedProjectID)
        if saveThread {
            threadPersistence.save(thread)
        }
        recordNavigationTransition(from: previousLocation)
        return thread.id
    }

    private func restoreComposerDraft(from outgoing: UUID?, to incoming: UUID?) {
        if let incoming {
            let result = ComposerDraftStore.select(
                outgoing: outgoing,
                incoming: incoming,
                liveDraft: composer.draft,
                drafts: threadDrafts
            )
            threadDrafts = result.drafts
            composer.draft = result.restoredDraft
        } else if let outgoing {
            stashOutgoingThreadDraft(outgoing)
        }
    }

    private func stashOutgoingThreadDraft(_ outgoing: UUID) {
        if composer.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            threadDrafts[outgoing] = nil
        } else {
            threadDrafts[outgoing] = composer.draft
        }
        composer.draft = ""
    }

    private func selectThreadRecord(_ id: UUID, projectID: UUID?) {
        root.selectedThreadID = id
        root.selectedProjectID = knownProjectID(projectID)
        syncTerminalSessionToSelectedProject()
        touchProject(root.selectedProjectID)
        saveProjects()
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
    }
}
