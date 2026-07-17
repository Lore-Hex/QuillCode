import SwiftUI

/// The persistent banner shown while an incognito chat is selected, so the private state is
/// unmistakable: the conversation is never saved, and every turn runs on the E2E-encrypted route.
/// Deliberately control-free — leaving incognito is just New Chat / selecting another thread —
/// which also keeps it out of interaction-target audits. Mirrors `.incognito-banner` in the
/// DOM renderer and E2E harness.
struct QuillCodeIncognitoBannerView: View {
    var body: some View {
        HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
            Image(systemName: "eye.slash.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
            Text("Incognito chat")
                .font(.callout.weight(.semibold))
                .foregroundStyle(QuillCodePalette.text)
            Text("Not saved · E2E encrypted")
                .font(.callout)
                .foregroundStyle(QuillCodePalette.muted)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(QuillCodePalette.panel2)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(QuillCodePalette.line)
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Incognito chat: not saved, end-to-end encrypted")
        .accessibilityIdentifier("quillcode-incognito-banner")
    }
}
