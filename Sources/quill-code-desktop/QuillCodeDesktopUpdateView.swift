import SwiftUI
import QuillCodeApp

struct QuillCodeDesktopUpdateView: View {
    @ObservedObject var controller: QuillCodeDesktopUpdateController

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 14)

            Divider().opacity(0.55)

            content
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().opacity(0.55)
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .frame(width: 470, height: 340)
        .background(Color(nsColor: .windowBackgroundColor))
        .interactiveDismissDisabled(controller.state.isBusy)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 28, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Quill Cowork Update")
                    .font(.title3.weight(.semibold))
                    .accessibilityIdentifier("quillcode-update-title")
                if let configuration = controller.configuration {
                    Text("Current version \(configuration.currentVersion) (\(configuration.currentBuild))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: controller.dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .quillCodeIconButtonTarget(size: 36, radius: 9)
            }
            .buttonStyle(QuillCodePressableButtonStyle())
            .disabled(controller.state.isBusy)
            .help("Close")
            .accessibilityLabel("Close update")
            .accessibilityIdentifier("quillcode-update-close")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch controller.state {
        case .idle, .checking:
            statusContent(
                icon: "arrow.triangle.2.circlepath",
                title: "Checking for updates...",
                detail: "Contacting the GitHub release feed.",
                showsProgress: true
            )
        case .updateAvailable(let release):
            updateContent(release)
        case .downloading(let release):
            preparationStatusContent(release)
        case .installing(let release):
            statusContent(
                icon: "shippingbox",
                title: "Preparing \(release.displayVersion)",
                detail: "Quill Cowork will relaunch when the verified update is ready.",
                showsProgress: true
            )
        case .upToDate(let version, let build):
            statusContent(
                icon: "checkmark.circle.fill",
                title: "You're up to date",
                detail: "Quill Cowork \(version) (\(build)) is the latest version.",
                showsProgress: false
            )
        case .failed(let message, _):
            statusContent(
                icon: "exclamationmark.triangle.fill",
                title: "Update couldn't be completed",
                detail: message,
                showsProgress: false,
                scrollsDetail: true
            )
        }
    }

    private func preparationStatusContent(_ release: QuillCodeDesktopUpdateRelease) -> some View {
        let progress = controller.preparationProgress
        switch progress {
        case .downloading(let receivedBytes, let totalBytes):
            return statusContent(
                icon: "arrow.down.circle",
                title: "Downloading \(release.displayVersion)",
                detail: "\(fileSize(receivedBytes)) of \(fileSize(totalBytes))",
                showsProgress: true,
                progressValue: progress?.downloadFraction
            )
        case .verifying:
            return statusContent(
                icon: "checkmark.shield",
                title: "Verifying update",
                detail: "Checking the download size and SHA-256 digest.",
                showsProgress: true
            )
        case .extracting:
            return statusContent(
                icon: "shippingbox",
                title: "Unpacking update",
                detail: "Preparing the verified app bundle.",
                showsProgress: true
            )
        case .validatingApplication:
            return statusContent(
                icon: "checkmark.seal",
                title: "Validating app",
                detail: "Checking its identity, version, architecture, and code signature.",
                showsProgress: true
            )
        case nil:
            return statusContent(
                icon: "arrow.down.circle",
                title: "Downloading \(release.displayVersion)",
                detail: fileSize(release.asset.sizeBytes),
                showsProgress: true
            )
        }
    }

    private func updateContent(_ release: QuillCodeDesktopUpdateRelease) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "arrow.down.app.fill")
                    .font(.system(size: 34, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Version \(release.displayVersion) is ready")
                        .font(.headline)
                    Text("\(release.channel.rawValue.capitalized) channel")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: release.asset.sizeBytes, countStyle: .file))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("SHA-256 integrity verified before install", systemImage: "checkmark.shield")
                Label("Automatic rollback if the new build cannot launch", systemImage: "arrow.uturn.backward.circle")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Button("View release on GitHub", action: controller.openReleasePage)
                .buttonStyle(.link)
                .quillCodeLinkTarget(minWidth: nil, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusContent(
        icon: String,
        title: String,
        detail: String,
        showsProgress: Bool,
        progressValue: Double? = nil,
        scrollsDetail: Bool = false
    ) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 38, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Group {
                if scrollsDetail {
                    ScrollView {
                        Text(detail)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 4)
                    }
                    .frame(maxHeight: 84)
                } else {
                    Text(detail)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            if showsProgress {
                if let progressValue {
                    ProgressView(value: progressValue)
                        .frame(width: 220)
                        .accessibilityLabel(title)
                        .accessibilityValue(Text("\(Int(progressValue * 100)) percent"))
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(title)
                }
            }
        }
        .frame(maxWidth: 380)
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 8) {
            switch controller.state {
            case .updateAvailable:
                Button("Later", action: controller.dismiss)
                    .buttonStyle(QuillCodeActionButtonStyle())
                    .quillCodeFormActionTarget()
                Spacer()
                Button(action: controller.updateAndRelaunch) {
                    Label("Update and Relaunch", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(QuillCodeActionButtonStyle(.primary, minWidth: 168))
                .quillCodeFormActionTarget(minWidth: 168)
                .accessibilityIdentifier("quillcode-update-install")
            case .downloading:
                Spacer()
                Button("Cancel", action: controller.cancelCurrentOperation)
                    .buttonStyle(QuillCodeActionButtonStyle())
                    .quillCodeFormActionTarget()
            case .installing:
                Spacer()
                Text("Keep Quill Cowork open")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .failed(_, let release):
                if release != nil {
                    Button(action: controller.openDownloadInBrowser) {
                        Label("Browser Download", systemImage: "safari")
                    }
                    .buttonStyle(QuillCodeActionButtonStyle())
                    .quillCodeFormActionTarget()
                }
                Spacer()
                if release != nil {
                    Button(action: controller.updateAndRelaunch) {
                        Label("Try Again", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(QuillCodeActionButtonStyle(.primary, minWidth: 110))
                    .quillCodeFormActionTarget(minWidth: 110)
                    .accessibilityIdentifier("quillcode-update-retry")
                } else {
                    Button(action: controller.checkForUpdates) {
                        Label("Check Again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(QuillCodeActionButtonStyle(.primary, minWidth: 110))
                    .quillCodeFormActionTarget(minWidth: 110)
                    .accessibilityIdentifier("quillcode-update-recheck")
                }
            case .idle, .checking:
                Spacer()
            case .upToDate:
                Spacer()
                Button("Done", action: controller.dismiss)
                    .buttonStyle(QuillCodeActionButtonStyle(.primary))
                    .quillCodeFormActionTarget()
            }
        }
    }

    private func fileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(bytes, 0), countStyle: .file)
    }
}
