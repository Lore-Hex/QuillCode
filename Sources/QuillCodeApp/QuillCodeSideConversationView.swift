import SwiftUI

struct QuillCodeSideConversationView: View {
    var sideConversation: SideConversationSurface
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.callout.weight(.semibold))
                .foregroundStyle(QuillCodePalette.purple)
                .quillCodeDecorativeIconFrame(size: 32)
                .background(QuillCodePalette.purple.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Side conversation")
                    .font(.callout.weight(.semibold))
                Text("From \(sideConversation.parentTitle) · \(sideConversation.parentStatus)")
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                onCommand(sideConversation.returnCommand)
            } label: {
                Label(sideConversation.returnCommand.title, systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(QuillCodeActionButtonStyle(.secondary, minWidth: 148))
            .quillCodeTextButtonTarget(minWidth: 148)
            .accessibilityIdentifier("side-conversation-return")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(QuillCodePalette.purple.opacity(0.055))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(QuillCodePalette.purple.opacity(0.16))
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Side conversation from \(sideConversation.parentTitle). \(sideConversation.parentStatus)")
    }
}
