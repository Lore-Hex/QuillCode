import Foundation
import QuillCodeCore
import QuillCodePersistence

@MainActor
extension QuillCodeWorkspaceModel {
    /// Imports user-selected images into QuillCode-owned storage. File reading happens off the
    /// main actor so attaching a large image does not stall typing or transcript scrolling.
    public func addComposerImages(from sourceURLs: [URL]) async {
        guard !sourceURLs.isEmpty else { return }
        if selectedThread == nil {
            _ = newChat()
        }
        guard let threadID = root.selectedThreadID, let imageAttachmentStore else {
            setLastError("Image attachments are unavailable in this runtime.")
            return
        }

        let remaining = ChatAttachment.maximumCountPerTurn - composer.attachments.count
        guard remaining > 0 else {
            setLastError(
                ImageAttachmentStoreError.attachmentLimitReached(
                    maximumCount: ChatAttachment.maximumCountPerTurn
                ).localizedDescription
            )
            return
        }

        let selectedURLs = Array(sourceURLs.prefix(remaining))
        let importResult = await Task.detached(priority: .userInitiated) {
            var attachments: [ChatAttachment] = []
            var firstError: String?
            for sourceURL in selectedURLs {
                do {
                    attachments.append(
                        try imageAttachmentStore.importImage(from: sourceURL, threadID: threadID)
                    )
                } catch {
                    firstError = firstError ?? error.localizedDescription
                }
            }
            return (attachments, firstError)
        }.value

        guard root.threads.contains(where: { $0.id == threadID }) else {
            for attachment in importResult.0 {
                try? imageAttachmentStore.remove(attachment)
            }
            return
        }
        let existing = persistedComposerAttachments(for: threadID)
        let available = max(0, ChatAttachment.maximumCountPerTurn - existing.count)
        let accepted = Array(importResult.0.prefix(available))
        for attachment in importResult.0.dropFirst(available) {
            try? imageAttachmentStore.remove(attachment)
        }
        let updated = existing + accepted
        persistComposerAttachments(updated, for: threadID)
        if root.selectedThreadID == threadID {
            composer.attachments = updated
        }
        if sourceURLs.count > remaining || accepted.count < importResult.0.count {
            setLastError(
                ImageAttachmentStoreError.attachmentLimitReached(
                    maximumCount: ChatAttachment.maximumCountPerTurn
                ).localizedDescription
            )
        } else {
            setLastError(importResult.1)
        }
    }

    public func removeComposerImage(_ id: UUID) {
        guard let index = composer.attachments.firstIndex(where: { $0.id == id }) else { return }
        let attachment = composer.attachments.remove(at: index)
        persistComposerAttachments(composer.attachments, for: root.selectedThreadID)
        removeManagedImagesIfUnreferenced([attachment])
        setLastError(nil)
    }

    public func reportImageAttachmentError(_ error: any Error) {
        setLastError(error.localizedDescription)
    }

    func persistComposerAttachments(_ attachments: [ChatAttachment], for threadID: UUID?) {
        guard let threadID,
              let index = root.threads.firstIndex(where: { $0.id == threadID })
        else { return }
        let bounded = Array(attachments.prefix(ChatAttachment.maximumCountPerTurn))
        guard root.threads[index].composerAttachments != bounded else { return }
        root.threads[index].composerAttachments = bounded
        threadPersistence.save(root.threads[index])
    }

    func clearComposerAttachments(for threadID: UUID?) {
        if root.selectedThreadID == threadID {
            composer.attachments = []
        }
        persistComposerAttachments([], for: threadID)
    }

    func removeManagedImagesIfUnreferenced(_ candidates: [ChatAttachment]) {
        guard let imageAttachmentStore, !candidates.isEmpty else { return }
        let referencedIDs = Set(root.threads.flatMap(Self.allImageAttachments).map(\.id))
        for attachment in candidates where !referencedIDs.contains(attachment.id) {
            try? imageAttachmentStore.remove(attachment)
        }
    }

    private static func allImageAttachments(in thread: ChatThread) -> [ChatAttachment] {
        thread.composerAttachments
            + thread.followUpQueue.flatMap(\.attachments)
            + thread.messages.flatMap(\.attachments)
    }
}
