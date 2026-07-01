import SwiftUI
import QuillCodeCore

struct QuillCodeModePickerButton: View {
    var modeLabel: String
    var onSetMode: (AgentMode) -> Void

    var body: some View {
        Menu {
            ForEach(orderedModes, id: \.rawValue) { mode in
                Button {
                    onSetMode(mode)
                } label: {
                    HStack {
                        Text(mode.title)
                        if mode == selectedMode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .quillCodePlatformMenuItemTarget(reason: Self.menuItemTargetReason)
            }
        } label: {
            modePickerLabel
        }
        .quillCodeCapsuleButtonTarget()
        .buttonStyle(QuillCodePressableButtonStyle())
        .help("Choose Auto safety mode")
        .accessibilityLabel("Auto safety mode, \(modeLabel)")
        .accessibilityIdentifier("quillcode-mode-picker-button")
    }

    private var selectedMode: AgentMode {
        AgentMode.allCases.first { $0.title == modeLabel } ?? .auto
    }

    private var orderedModes: [AgentMode] {
        AgentMode.cycleOrder
    }

    private var selectedModeColor: Color {
        switch selectedMode {
        case .auto:
            return QuillCodePalette.green
        case .plan:
            return QuillCodePalette.blue
        case .review:
            return QuillCodePalette.yellow
        case .readOnly:
            return QuillCodePalette.muted
        }
    }

    private var modePickerLabel: some View {
        HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
            Circle()
                .fill(selectedModeColor)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(modeLabel)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(QuillCodePalette.muted)
        }
        .foregroundStyle(QuillCodePalette.text)
        .padding(.horizontal, 10)
        .quillCodeCapsuleButtonTarget()
        .background(QuillCodePalette.selection.opacity(0.62))
        .overlay {
            Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Auto safety mode, \(modeLabel)")
        .accessibilityIdentifier("quillcode-mode-picker-button")
    }

    private static let menuItemTargetReason =
        "AppKit owns mode picker menu row geometry; the mode trigger carries the custom hit-target contract."
}
