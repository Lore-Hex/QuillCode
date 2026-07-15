import SwiftUI
import QuillCodeCore

struct QuillCodePersonalitySettingsCard: View {
    @Binding var draft: QuillCodeSettingsDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(QuillCodePalette.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Default personality")
                        .font(.callout.weight(.semibold))
                    Text(draft.defaultPersonality.summary)
                        .font(.caption)
                        .foregroundStyle(QuillCodePalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Picker("Default personality", selection: $draft.defaultPersonality) {
                ForEach(QuillCodePersonality.allCases, id: \.self) { personality in
                    Text(personality.displayName).tag(personality)
                }
            }
            .pickerStyle(.segmented)
            .quillCodeSegmentedControlTarget()
            .accessibilityIdentifier("quillcode-settings-personality")

            Text("Applies to new chats. Use /personality to change only the current chat.")
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
        }
        .quillCodeSettingsCard(tint: QuillCodePalette.blue)
    }
}
