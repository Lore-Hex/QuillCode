import SwiftUI
import QuillCodeCore

extension QuillCodeBrowserPaneView {
    func snapshotDetails(_ details: [String]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: 6)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(details, id: \.self) { detail in
                Text(detail)
                    .font(.caption2.monospaced())
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(QuillCodePalette.panel.opacity(0.9))
                    .clipShape(Capsule())
            }
        }
    }

    func browserBadge(_ label: String, tint: Color) -> some View {
        Text(label)
            .font(.caption2.monospacedDigit().weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14))
            .overlay(Capsule().stroke(tint.opacity(0.22), lineWidth: 1))
            .clipShape(Capsule())
    }

    func browserInspectionTint(_ depth: BrowserInspectionDepth) -> Color {
        switch depth {
        case .metadataOnly:
            return QuillCodePalette.yellow
        case .fileMetadata:
            return QuillCodePalette.blue
        case .staticHTMLSnapshot, .networkHTMLSnapshot:
            return QuillCodePalette.green
        case .liveDOMSnapshot:
            return QuillCodePalette.purple
        }
    }
}
