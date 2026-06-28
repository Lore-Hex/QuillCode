import SwiftUI

struct QuillCodeContextBannerView: View {
    var banner: ContextBannerSurface
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "text.bubble.badge.exclamationmark")
                .font(.title3)
                .foregroundStyle(QuillCodePalette.yellow)
                .quillCodeDecorativeIconFrame()
                .background(QuillCodePalette.yellow.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: QuillCodeMetrics.iconControlRadius, style: .continuous))

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
                actionButtons
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

    @ViewBuilder
    private var actionButtons: some View {
        ViewThatFits(in: .horizontal) {
            actionButtonRow
            VStack(alignment: .leading, spacing: 8) {
                actionButtonRow
            }
        }
    }

    private var actionButtonRow: some View {
        HStack(spacing: 8) {
            contextButton(for: banner.compactCommand, isPrimary: true, minWidth: 120)
            contextButton(for: banner.newThreadCommand, minWidth: 112)
            ForEach(banner.forkCommands, id: \.id) { command in
                contextButton(for: command, minWidth: 104)
            }
        }
    }

    @ViewBuilder
    private func contextButton(
        for command: WorkspaceCommandSurface,
        isPrimary: Bool = false,
        minWidth: CGFloat
    ) -> some View {
        if isPrimary {
            Button(command.title) {
                onCommand(command)
            }
                .buttonStyle(QuillCodeActionButtonStyle(.primary, minWidth: minWidth))
                .disabled(!command.isEnabled)
                .accessibilityLabel(command.title)
        } else {
            Button(command.title) {
                onCommand(command)
            }
                .buttonStyle(QuillCodeActionButtonStyle(.secondary, minWidth: minWidth))
                .disabled(!command.isEnabled)
                .accessibilityLabel(command.title)
        }
    }
}
