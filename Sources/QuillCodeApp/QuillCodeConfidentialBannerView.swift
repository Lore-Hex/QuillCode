import SwiftUI

/// The persistent banner shown while a confidential chat is selected, so the private state is
/// unmistakable: the conversation is never saved, and every turn runs on the E2E-encrypted route.
/// Deliberately control-free — leaving confidential is just New Chat / selecting another thread —
/// which also keeps it out of interaction-target audits. Mirrors `.confidential-banner` in the
/// DOM renderer and E2E harness.
struct QuillCodeConfidentialBannerView: View {
    var body: some View {
        HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
            Image(systemName: "eye.slash.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(QuillCodePalette.purple)
            Text("Confidential chat")
                .font(.callout.weight(.semibold))
                .foregroundStyle(QuillCodePalette.text)
            Text("Not saved · E2E encrypted")
                .font(.callout)
                .foregroundStyle(QuillCodePalette.muted)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        // The mode's violet band — layered over the confidential panel so the strip reads as part of
        // the shifted chrome, not a gray leftover from the normal ramp.
        .background(QuillCodePalette.Confidential.bandFill)
        .background(QuillCodePalette.Confidential.panel2)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(QuillCodePalette.Confidential.lineStrong)
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Confidential chat: not saved, end-to-end encrypted")
        .accessibilityIdentifier("quillcode-confidential-banner")
    }
}
