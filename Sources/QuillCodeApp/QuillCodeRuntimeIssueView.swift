import SwiftUI

struct QuillCodeRuntimeIssueView: View {
    var issue: RuntimeIssueSurface
    var showsDiagnostics = false
    var onAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(issue.title)
                    .font(.callout.weight(.semibold))
                Text(issue.message)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
                if let actionLabel = issue.actionLabel {
                    if let onAction {
                        Button(actionLabel, action: onAction)
                            .buttonStyle(.borderless)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tint)
                            .quillCodeHitTarget(minWidth: 72, alignment: .leading)
                    } else {
                        Text(actionLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tint)
                    }
                }
                if showsDiagnostics && !issue.diagnostics.isEmpty {
                    Divider()
                        .padding(.vertical, 4)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Diagnostics")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(QuillCodePalette.muted)
                        ForEach(issue.diagnostics) { diagnostic in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(diagnostic.label)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(QuillCodePalette.muted)
                                    .frame(width: 96, alignment: .leading)
                                Text(diagnostic.value)
                                    .font(.caption2.monospaced())
                                    .textSelection(.enabled)
                                    .lineLimit(3)
                            }
                        }
                    }
                    .accessibilityElement(children: .contain)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var tint: Color {
        issue.severity == .error ? QuillCodePalette.red : QuillCodePalette.yellow
    }
}
