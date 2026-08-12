import Foundation
import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
    func restorePersistedSelectedComposerDraftIfNeeded() {
        guard let selectedThreadID = root.selectedThreadID else {
            if composer.draft.isEmpty {
                composer.draft = threadPersistence.pendingComposerDraft() ?? ""
            }
            return
        }
        threadPersistence.deletePendingComposerDraft()
        let persistedDraft = persistedComposerDraft(for: selectedThreadID)
        if let index = root.threads.firstIndex(where: { $0.id == selectedThreadID }) {
            root.threads[index].composerDraft = Self.normalizedComposerDraft(persistedDraft)
        }
        if composer.draft.isEmpty {
            composer.draft = persistedDraft ?? ""
        }
        if composer.attachments.isEmpty {
            composer.attachments = persistedComposerAttachments(for: selectedThreadID)
        }
    }

    func persistCurrentComposerDraft() {
        guard let selectedThreadID = root.selectedThreadID else {
            threadPersistence.savePendingComposerDraft(Self.normalizedComposerDraft(composer.draft))
            return
        }
        persistComposerDraft(composer.draft, for: selectedThreadID)
    }

    /// Keeps model projections aligned with the live desktop binding without touching disk. The
    /// desktop follows this with a debounced checkpoint, while navigation can still synchronously
    /// persist before changing the owner.
    public func updateLiveComposerDraft(_ draft: String, ownerThreadID: UUID?) {
        guard ownerThreadID == root.selectedThreadID else { return }
        composer.draft = draft
    }

    /// Applies a debounced desktop checkpoint to the owner that was selected when typing occurred.
    /// Capturing that identity prevents a delayed write from bleeding text into a newly selected chat.
    public func checkpointComposerDraft(_ draft: String, ownerThreadID: UUID?) {
        guard ownerThreadID == root.selectedThreadID else { return }
        composer.draft = draft
        persistCurrentComposerDraft()
    }

    func clearComposerDraft(for threadID: UUID?) {
        guard let threadID else { return }
        if root.selectedThreadID == threadID {
            composer.draft = ""
        }
        threadDrafts = ComposerDraftStore.cleared(threadID, drafts: threadDrafts)
        persistComposerDraft(nil, for: threadID)
    }

    func persistedComposerDraft(for threadID: UUID) -> String? {
        guard let thread = root.threads.first(where: { $0.id == threadID }) else { return nil }
        return threadPersistence.composerDraft(for: thread)
    }

    func persistedComposerAttachments(for threadID: UUID) -> [ChatAttachment] {
        root.threads.first { $0.id == threadID }?.composerAttachments ?? []
    }

    func persistComposerDraft(_ draft: String?, for threadID: UUID) {
        let normalized = Self.normalizedComposerDraft(draft)
        guard let index = root.threads.firstIndex(where: { $0.id == threadID }),
              root.threads[index].composerDraft != normalized
        else {
            return
        }
        root.threads[index].composerDraft = normalized
        threadPersistence.saveComposerDraft(in: root.threads[index])
    }

    static func normalizedComposerDraft(_ draft: String?) -> String? {
        guard let draft,
              !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return draft
    }
}
