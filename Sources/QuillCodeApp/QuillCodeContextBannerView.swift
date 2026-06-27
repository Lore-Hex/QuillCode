import SwiftUI

struct QuillCodeContextBannerView: View {
    var banner: ContextBannerSurface
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "text.bubble.badge.exclamationmark")
                .font(.title3)
                .foregroundStyle(QuillCodePalette.yellow)
                .frame(width: 34, height: 34)
                .background(QuillCodePalette.yellow.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(banner.title)
                        .font(.headline)
                    Text("\(banner.usedPercent)%")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(QuillCodePalette.yellow)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(QuillCodePalette.yellow.opacity(0.14))
                        .clipShape(Capsule())
                }
                Text(banner.subtitle)
                    .font(.callout)
                    .foregroundStyle(QuillCodePalette.muted)
                HStack(spacing: 8) {
                    Button(banner.compactCommand.title) {
                        onCommand(banner.compactCommand)
                    }
                    .buttonStyle(.borderedProminent)
                    .quillCodeHitTarget(minWidth: 104)
                    .disabled(!banner.compactCommand.isEnabled)
                    Button(banner.newThreadCommand.title) {
                        onCommand(banner.newThreadCommand)
                    }
                    .buttonStyle(.bordered)
                    .quillCodeHitTarget(minWidth: 112)
                    Button(banner.forkCommand.title) {
                        onCommand(banner.forkCommand)
                    }
                    .buttonStyle(.bordered)
                    .quillCodeHitTarget(minWidth: 112)
                    .disabled(!banner.forkCommand.isEnabled)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: 760, alignment: .leading)
        .background(QuillCodePalette.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(QuillCodePalette.yellow.opacity(0.28), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
