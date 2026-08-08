import SwiftUI
import QuillCodeApp

struct QuillCodeDesktopInstallationLocationView: View {
    @ObservedObject var controller: QuillCodeDesktopInstallationLocationController

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 14)

            Divider()
                .overlay(QuillCodeCharterTheme.line)

            VStack(spacing: 18) {
                Image(systemName: "arrow.down.app.fill")
                    .font(.system(size: 42, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(QuillCodeCharterTheme.sage)

                VStack(spacing: 7) {
                    Text("Move Quill Cowork to Applications")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text("Install the app in Applications for reliable updates and relaunches.")
                        .font(.callout)
                        .foregroundStyle(QuillCodeCharterTheme.body)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 28)

            Divider()
                .overlay(QuillCodeCharterTheme.line)

            HStack(spacing: 12) {
                Button("Not Now", action: controller.dismiss)
                    .buttonStyle(QuillCodeActionButtonStyle())
                    .quillCodeFormActionTarget()
                    .accessibilityIdentifier("quillcode-install-location-not-now")
                Spacer()
                Button(action: controller.openApplicationsFolder) {
                    Label("Open Applications", systemImage: "folder")
                }
                .buttonStyle(QuillCodeActionButtonStyle(.primary, minWidth: 170))
                .quillCodeFormActionTarget(minWidth: 170)
                .accessibilityIdentifier("quillcode-install-location-open-applications")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 470, height: 320)
        .background(QuillCodeCharterTheme.page)
        .foregroundStyle(QuillCodeCharterTheme.ivory)
        .tint(QuillCodeCharterTheme.sage)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "app.badge.checkmark")
                .font(.system(size: 28, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(QuillCodeCharterTheme.sage)
            Text("Finish Installing Quill Cowork")
                .font(.custom("Iowan Old Style", size: 20).weight(.semibold))
                .accessibilityIdentifier("quillcode-install-location-title")
            Spacer()
            Button(action: controller.dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(QuillCodeCharterTheme.muted)
                    .quillCodeIconButtonTarget(size: 36, radius: QuillCodeMetrics.iconControlRadius)
                    .background(QuillCodeCharterTheme.raised)
                    .overlay(
                        RoundedRectangle(
                            cornerRadius: QuillCodeMetrics.iconControlRadius,
                            style: .continuous
                        )
                        .stroke(QuillCodeCharterTheme.line, lineWidth: 1)
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: QuillCodeMetrics.iconControlRadius,
                            style: .continuous
                        )
                    )
            }
            .buttonStyle(QuillCodePressableButtonStyle())
            .help("Close")
            .accessibilityLabel("Close installation reminder")
            .accessibilityIdentifier("quillcode-install-location-close")
        }
    }
}
