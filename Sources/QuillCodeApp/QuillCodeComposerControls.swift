import SwiftUI

struct QuillCodeFollowUpQueueView: View {
    var items: [FollowUpItemSurface]
    var onDelete: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: QuillCodeMetrics.denseControlClusterSpacing) {
            ForEach(items) { item in
                HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                    Text(item.text)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(QuillCodePalette.blue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        onDelete(item.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.bold))
                            .quillCodeIconButtonTarget(size: 22, radius: 6)
                    }
                    .buttonStyle(QuillCodePressableButtonStyle())
                    .foregroundStyle(QuillCodePalette.muted)
                    .help("Remove queued follow-up")
                    .accessibilityLabel("Remove queued follow-up")
                    .accessibilityIdentifier("quillcode-followup-delete")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(QuillCodePalette.blue.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(QuillCodePalette.blue.opacity(0.3), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("quillcode-followup-chip")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Queued follow-ups")
    }
}

struct QuillCodeComposerTextField: View {
    var placeholder: String
    @Binding var draft: String
    var isFocused: FocusState<Bool>.Binding
    var onDownArrow: () -> KeyPress.Result
    var onUpArrow: () -> KeyPress.Result
    var onTab: () -> KeyPress.Result
    var onReturn: () -> KeyPress.Result
    var onSend: () -> Void

    var body: some View {
        TextField(placeholder, text: $draft, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.body)
            .lineLimit(1...5)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .quillCodeTextEntryTarget()
            .focused(isFocused)
            .onKeyPress(.downArrow, action: onDownArrow)
            .onKeyPress(.upArrow, action: onUpArrow)
            .onKeyPress(.tab, action: onTab)
            .onKeyPress(.return, action: onReturn)
            .onSubmit(onSend)
            .accessibilityLabel("Message")
            .accessibilityIdentifier("quillcode-composer-input")
    }
}

struct QuillCodeComposerActionButton: View {
    var isSending: Bool
    var canSendDraft: Bool
    var onSend: () -> Void
    var onStop: () -> Void

    var body: some View {
        if isSending {
            Button(action: onStop) {
                Label("Stop", systemImage: "stop.fill")
                    .font(.headline)
                    .quillCodeTextButtonTarget(
                        minWidth: 90,
                        minHeight: 46,
                        radius: QuillCodeMetrics.composerControlRadius
                    )
            }
            .buttonStyle(QuillCodePressableButtonStyle())
            .background(QuillCodePalette.red)
            .foregroundStyle(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: QuillCodeMetrics.composerControlRadius, style: .continuous))
            .keyboardShortcut(.cancelAction)
            .help("Stop the current run")
            .accessibilityIdentifier("quillcode-stop-button")
        } else {
            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.headline.weight(.semibold))
                    .quillCodeIconButtonTarget(
                        size: 46,
                        radius: QuillCodeMetrics.composerControlRadius
                    )
            }
            .buttonStyle(QuillCodePressableButtonStyle())
            .background(canSendDraft ? QuillCodePalette.blue : QuillCodePalette.background.opacity(0.72))
            .foregroundStyle(canSendDraft ? Color.white : QuillCodePalette.muted)
            .clipShape(RoundedRectangle(cornerRadius: QuillCodeMetrics.composerControlRadius, style: .continuous))
            .disabled(!canSendDraft)
            .help("Send")
            .accessibilityLabel("Send message")
            .accessibilityIdentifier("quillcode-send-button")
        }
    }
}
