import SwiftUI

struct QuillCodeLabeledTextField: View {
    var title: String
    var placeholder: String
    @Binding var text: String
    var footer: String?
    var onSubmit: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(minHeight: QuillCodeMetrics.minimumHitTarget)
                .onSubmit {
                    onSubmit?()
                }
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
            }
        }
    }
}

struct QuillCodeDialogHeader: View {
    var title: String
    var subtitle: String
    var closeTitle: String
    var onClose: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(QuillCodePalette.muted)
            }
            Spacer()
            Button(closeTitle, action: onClose)
                .keyboardShortcut(.cancelAction)
        }
    }
}

struct QuillCodeDialogSectionTitle: View {
    var title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(QuillCodePalette.muted)
            .textCase(.uppercase)
    }
}

struct QuillCodeDialogEmptyState: View {
    var systemImage: String
    var title: String
    var subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(QuillCodePalette.muted)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(QuillCodePalette.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}
