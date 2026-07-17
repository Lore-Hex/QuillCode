import SwiftUI
import QuillCodeCore

struct QuillCodeAutoReviewDenialsView: View {
    var surface: AutoReviewDenialsSurface
    var onClose: () -> Void
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            QuillCodeDialogHeader(
                title: "Auto-review Denials",
                subtitle: "Retry one exact action. Auto will review it again before anything runs.",
                closeTitle: "Done",
                onClose: onClose
            )

            if surface.items.isEmpty {
                QuillCodeDialogEmptyState(
                    systemImage: "checkmark.shield",
                    title: "No recent denials",
                    subtitle: "Denied Auto actions from this task will appear here."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(surface.items) { item in
                            denialRow(item)
                        }
                    }
                }
            }
        }
        .padding(22)
        .frame(width: 620, height: 560)
        .background(QuillCodePalette.panel)
        .accessibilityIdentifier("quillcode-auto-review-denials-dialog")
    }

    private func denialRow(_ item: AutoReviewDenialItemSurface) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundStyle(QuillCodePalette.yellow)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.toolName)
                        .font(.headline)
                    Text(item.actionSummary)
                        .font(.caption)
                        .foregroundStyle(QuillCodePalette.muted)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Text(stateLabel(item.retryState))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(stateColor(item.retryState))
            }

            Text(item.reason)
                .font(.callout)
                .foregroundStyle(QuillCodePalette.text)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                if let riskLabel = item.riskLabel {
                    metadataLabel("\(riskLabel) risk")
                }
                if let authorizationLabel = item.authorizationLabel {
                    metadataLabel(authorizationLabel)
                }
                Spacer()
                retryButton(item)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(QuillCodePalette.panel2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(QuillCodePalette.line, lineWidth: 1)
        )
    }

    private func metadataLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(QuillCodePalette.muted)
    }

    @ViewBuilder
    private func retryButton(_ item: AutoReviewDenialItemSurface) -> some View {
        let isRetrying = surface.retryingRequestID == item.requestID
        Button {
            onCommand(WorkspaceCommandSurface(
                id: item.retryCommandID,
                title: "Review and retry"
            ))
        } label: {
            HStack(spacing: 7) {
                if isRetrying {
                    ProgressView().controlSize(.small)
                }
                Text(isRetrying ? "Reviewing" : "Review and retry")
            }
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .quillCodeTextButtonTarget()
        .disabled(!item.canRetry || surface.retryingRequestID != nil)
        .accessibilityIdentifier("quillcode-auto-review-retry-\(item.requestID)")
    }

    private func stateLabel(_ state: AutoReviewDenialRetryState) -> String {
        switch state {
        case .available: "Retry available"
        case .consumed: "Retry used"
        case .unavailable: "Cannot replay safely"
        case .contextChanged: "Context changed"
        }
    }

    private func stateColor(_ state: AutoReviewDenialRetryState) -> Color {
        state == .available ? QuillCodePalette.blue : QuillCodePalette.muted
    }
}
