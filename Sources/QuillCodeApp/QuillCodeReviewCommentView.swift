import SwiftUI

struct QuillCodeReviewCommentView: View {
    var comment: WorkspaceReviewCommentSurface
    var showsLocation = true

    var body: some View {
        if comment.source == .codeReview {
            finding
        } else {
            userNote
        }
    }

    private var finding: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let priority = comment.priority {
                    Text(priority.label)
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundStyle(priorityColor(priority))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(priorityColor(priority).opacity(0.13))
                        .clipShape(Capsule())
                }
                Text(comment.title ?? "Code review finding")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.text)
                Spacer(minLength: 8)
                if showsLocation, let label = comment.lineRangeLabel {
                    Text(label)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(QuillCodePalette.muted)
                }
            }
            Text(comment.text)
                .font(.caption)
                .foregroundStyle(QuillCodePalette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(findingTint.opacity(0.07))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(findingTint)
                .frame(width: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("quillcode-review-finding")
    }

    private var userNote: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "text.bubble")
                .foregroundStyle(QuillCodePalette.blue)
            if showsLocation, let label = comment.lineRangeLabel {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.muted)
            }
            Text(comment.text)
                .font(.caption)
                .foregroundStyle(QuillCodePalette.text)
        }
    }

    private var findingTint: Color {
        comment.priority.map(priorityColor) ?? QuillCodePalette.blue
    }

    private func priorityColor(_ priority: WorkspaceCodeReviewPriority) -> Color {
        switch priority {
        case .p0:
            QuillCodePalette.red
        case .p1:
            QuillCodePalette.yellow
        case .p2:
            QuillCodePalette.blue
        case .p3:
            QuillCodePalette.muted
        }
    }
}
