import SwiftUI

enum QuillCodeToolRawDetailsPreview {
    static let characterLimit = 16_000

    static func text(_ text: String) -> String {
        guard text.count > characterLimit else { return text }
        let omittedCount = text.count - characterLimit
        return String(text.prefix(characterLimit))
            + "\n\n[Preview truncated: \(omittedCount) characters omitted]"
    }
}

struct QuillCodeCodeBlock: View {
    var title: String
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
            ScrollView([.horizontal, .vertical]) {
                Text(QuillCodeToolRawDetailsPreview.text(text))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: QuillCodeMetrics.toolCardRawDetailsMaxHeight, alignment: .topLeading)
            .background(Color.black.opacity(0.35))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }
}
