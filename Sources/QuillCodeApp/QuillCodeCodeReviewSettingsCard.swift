import SwiftUI
import QuillCodeCore

struct QuillCodeCodeReviewSettingsCard: View {
    @Binding var draft: QuillCodeSettingsDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Picker("Review delivery", selection: $draft.reviewDelivery) {
                Text("Current task").tag(CodeReviewDelivery.current)
                Text("Detached").tag(CodeReviewDelivery.detached)
            }
            .pickerStyle(.segmented)
            .quillCodeSegmentedControlTarget()
            .accessibilityIdentifier("quillcode-code-review-delivery")

            VStack(alignment: .leading, spacing: 6) {
                Text("Model override")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.muted)
                TextField("Current model", text: $draft.reviewModelText)
                    .textFieldStyle(.roundedBorder)
                    .quillCodeTextEntryTarget()
                    .accessibilityLabel("Code review model override")
                    .accessibilityIdentifier("quillcode-code-review-model")
                if !draft.isReviewModelValid {
                    Text("Enter a model ID without spaces.")
                        .font(.caption)
                        .foregroundStyle(QuillCodePalette.red)
                }
            }
        }
        .quillCodeSettingsCard(tint: QuillCodePalette.blue)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: QuillCodeMetrics.controlClusterSpacing) {
            Text("Code review")
                .font(.headline)
            Spacer()
            Text(deliveryLabel)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(QuillCodePalette.blue.opacity(0.16))
                .foregroundStyle(QuillCodePalette.blue)
                .clipShape(Capsule())
        }
    }

    private var deliveryLabel: String {
        switch draft.reviewDelivery {
        case .current:
            return "Current task"
        case .detached:
            return "Detached"
        }
    }
}
