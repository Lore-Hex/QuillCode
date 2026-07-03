import Foundation
import QuillCodeApp
import QuillCodeCore

@MainActor
extension QuillCodeDesktopController {
    func copyTranscriptItem(id: String, text: String) {
        guard let feedback = copyCoordinator.copyTranscriptItem(id: id, text: text) else { return }
        copiedTranscriptItemID = feedback.copiedTranscriptItemID
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: feedback.clearAfterNanoseconds)
            await MainActor.run {
                if self?.copiedTranscriptItemID == id {
                    self?.copiedTranscriptItemID = nil
                }
            }
        }
    }

    func exportCurrentConversationMarkdown() {
        guard let markdown = TranscriptMarkdownExporter.exportableMarkdown(for: surface.transcript) else {
            return
        }
        exportConversationMarkdown(title: surface.topBar.primaryTitle, markdown: markdown)
    }

    func exportConversationMarkdown(title: String, markdown: String) {
        do {
            _ = try transcriptExportCoordinator.exportConversation(title: title, markdown: markdown)
        } catch {
            model.setAgentStatus(
                TopBarAgentStatusLabel.failed,
                lastError: "Could not export conversation: \(error.localizedDescription)"
            )
            refresh()
        }
    }
}
