import Foundation
import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
    func restorePersistedSelectedComposerDraftIfNeeded() {
        guard let selectedThreadID = root.selectedThreadID else { return }
        if composer.draft.isEmpty {
            composer.draft = persistedComposerDraft(for: selectedThreadID) ?? ""
        }
        if composer.attachments.isEmpty {
            composer.attachments = persistedComposerAttachments(for: selectedThreadID)
        }
    }

    func persistCurrentComposerDraft() {
        guard let selectedThreadID = root.selectedThreadID else { return }
        persistComposerDraft(composer.draft, for: selectedThreadID)
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
        root.threads.first { $0.id == threadID }?.composerDraft
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
        threadPersistence.save(root.threads[index])
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
