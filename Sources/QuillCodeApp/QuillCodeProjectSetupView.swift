import SwiftUI

struct QuillCodeProjectSetupView: View {
    var onOpenProject: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: QuillCodeMetrics.settingsCardRadius, style: .continuous)
                    .fill(QuillCodePalette.panel2)
                    .overlay {
                        RoundedRectangle(cornerRadius: QuillCodeMetrics.settingsCardRadius, style: .continuous)
                            .stroke(QuillCodePalette.lineStrong, lineWidth: 1)
                    }
                    .frame(width: 60, height: 60)
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(QuillCodePalette.blue)
            }
            .accessibilityHidden(true)

            Text("Open a project")
                .font(.custom("Iowan Old Style", size: 22).weight(.semibold))
                .foregroundStyle(QuillCodePalette.text)

            Text("Choose the workspace folder \(QuillCodeProduct.displayName) can work in.")
                .font(.body)
                .foregroundStyle(QuillCodePalette.muted)

            Button(action: onOpenProject) {
                Label("Open Project...", systemImage: "folder")
            }
            .buttonStyle(QuillCodeActionButtonStyle(.primary, minWidth: 220))
            .quillCodeFormActionTarget(minWidth: 220)
            .accessibilityIdentifier("quillcode-empty-open-project")
            .padding(.top, 2)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
        .accessibilityIdentifier("quillcode-project-setup-empty-state")
    }
}
