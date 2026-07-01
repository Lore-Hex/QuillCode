import SwiftUI
import QuillCodeCore

struct QuillCodeBrowserPaneView: View {
    var browser: BrowserSurface
    @Binding var addressDraft: String
    var onOpen: () -> Void
    var onOpenSession: (() -> Void)?
    var onAddComment: (String) -> Void
    var onCommand: (String) -> Void

    @State private var commentDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            tabStrip
            navigationBar
            pageSummary
            commentInput
            comments
        }
        .padding(14)
        .frame(height: browser.snapshot == nil ? 260 : 300)
        .background(QuillCodePalette.panel)
    }

    private var commentInput: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            TextField("Add browser comment", text: $commentDraft)
                .textFieldStyle(.roundedBorder)
                .disabled(browser.currentURL == nil)
                .onSubmit(addComment)
                .quillCodeTextEntryTarget()
                .accessibilityIdentifier("quillcode-browser-comment-input")
            Button("Comment", action: addComment)
                .buttonStyle(QuillCodeActionButtonStyle(.secondary, minWidth: 92))
                .quillCodeFormActionTarget(minWidth: 92)
                .disabled(browser.currentURL == nil || commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("quillcode-browser-add-comment")
        }
    }

    @ViewBuilder
    private var comments: some View {
        if !browser.comments.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                    ForEach(browser.comments) { comment in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(comment.text)
                                .font(.caption)
                                .lineLimit(2)
                            Text(comment.url)
                                .font(.caption2.monospaced())
                                .foregroundStyle(QuillCodePalette.muted)
                                .lineLimit(1)
                        }
                        .padding(8)
                        .frame(width: 220, alignment: .leading)
                        .quillCodeSurface(
                            fill: QuillCodePalette.background.opacity(0.7),
                            radius: 18,
                            stroke: Color.white.opacity(0.08),
                            shadow: false
                        )
                    }
                }
            }
        }
    }

    private func addComment() {
        let comment = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !comment.isEmpty else { return }
        onAddComment(comment)
        commentDraft = ""
    }
}
