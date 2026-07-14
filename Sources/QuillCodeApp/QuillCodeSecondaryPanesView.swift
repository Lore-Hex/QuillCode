import SwiftUI

struct QuillCodePaneCountPill: View {
    var label: String
    var count: Int

    var body: some View {
        Text("\(count) \(label)")
            .font(.caption2.monospacedDigit().weight(.semibold))
            .foregroundStyle(QuillCodePalette.blue)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(QuillCodePalette.blue.opacity(0.12))
            .clipShape(Capsule())
    }
}

struct QuillCodePaneEmptyStateView: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.callout.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(QuillCodePalette.background.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct QuillCodePaneCloseButton: View {
    var paneName: String
    var accessibilityIdentifier: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .quillCodeIconButtonTarget()
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .help("Close \(paneName)")
        .accessibilityLabel("Close \(paneName)")
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
