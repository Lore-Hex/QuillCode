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
                statusIcon

                VStack(spacing: 7) {
                    Text(statusTitle)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text(statusMessage)
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

            footer
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
            .disabled(controller.state.isBusy)
            .opacity(controller.state.isBusy ? 0.45 : 1)
            .help("Close")
            .accessibilityLabel("Close installation reminder")
            .accessibilityIdentifier("quillcode-install-location-close")
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch controller.state {
        case .ready:
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 42, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(QuillCodeCharterTheme.sage)
        case .moving:
            ProgressView()
                .controlSize(.large)
                .tint(QuillCodeCharterTheme.sage)
                .frame(width: 42, height: 42)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 38, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(QuillCodeCharterTheme.clay)
        }
    }

    private var statusTitle: String {
        switch controller.state {
        case .ready:
            "Move Quill Cowork to Applications"
        case .moving:
            "Finishing Installation"
        case .failed:
            "Quill Cowork Wasn't Moved"
        }
    }

    private var statusMessage: String {
        switch controller.state {
        case .ready:
            "Move and reopen the app for reliable updates and relaunches."
        case .moving:
            "Verifying the app before reopening it from Applications..."
        case .failed(let message):
            message
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 12) {
            switch controller.state {
            case .ready:
                Button("Not Now", action: controller.dismiss)
                    .buttonStyle(QuillCodeActionButtonStyle())
                    .quillCodeFormActionTarget()
                    .accessibilityIdentifier("quillcode-install-location-not-now")
                Spacer()
                moveButton(label: "Move & Relaunch", systemImage: "arrow.down.app")
            case .moving:
                Spacer()
                Text("Moving and verifying...")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(QuillCodeCharterTheme.body)
                    .accessibilityIdentifier("quillcode-install-location-moving")
                Spacer()
            case .failed:
                Button(action: controller.openApplicationsFolder) {
                    Label("Open Applications", systemImage: "folder")
                }
                .buttonStyle(QuillCodeActionButtonStyle())
                .quillCodeFormActionTarget(minWidth: 150)
                .accessibilityIdentifier("quillcode-install-location-open-applications")
                Spacer()
                moveButton(label: "Try Again", systemImage: "arrow.clockwise")
            }
        }
        .frame(minHeight: QuillCodeMetrics.minimumHitTarget)
    }

    private func moveButton(label: String, systemImage: String) -> some View {
        Button(action: controller.moveAndRelaunch) {
            Label(label, systemImage: systemImage)
        }
        .buttonStyle(QuillCodeActionButtonStyle(.primary, minWidth: 170))
        .quillCodeFormActionTarget(minWidth: 170)
        .accessibilityIdentifier("quillcode-install-location-move")
    }
}
