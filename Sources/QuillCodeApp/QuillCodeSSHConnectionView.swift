import SwiftUI
import QuillCodeCore
import QuillCodeTools

struct QuillCodeSSHConnectionView: View {
    @ObservedObject var coordinator: QuillCodeSSHConnectionDialogCoordinator
    var onCancel: () -> Void
    var onRetry: () -> Void
    var onConnect: () -> Void

    @FocusState private var focusedField: Field?

    private enum Field {
        case search
        case manualAddress
        case remotePath
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            QuillCodeDialogHeader(
                title: "Connect over SSH",
                subtitle: "Open a project on another computer using your existing SSH configuration.",
                closeTitle: "Cancel",
                onClose: onCancel
            )

            modePicker
            hostSource
            projectFields
            statusMessage
            footer
        }
        .padding(20)
        .frame(width: 560, height: 610)
        .background(QuillCodePalette.background)
        .foregroundStyle(QuillCodePalette.text)
        .onAppear(perform: focusInitialField)
        .onChange(of: coordinator.draft.mode) { _, _ in focusInitialField() }
        .onChange(of: coordinator.draft.selectedHostID) { _, _ in
            if coordinator.draft.mode == .configured {
                focusedField = .remotePath
            }
        }
    }

    private var modePicker: some View {
        Picker("Connection source", selection: $coordinator.draft.mode) {
            ForEach(QuillCodeSSHConnectionMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .quillCodeSegmentedControlTarget()
        .accessibilityIdentifier("quillcode-ssh-mode-picker")
    }

    @ViewBuilder
    private var hostSource: some View {
        switch coordinator.draft.mode {
        case .configured:
            configuredHosts
        case .manual:
            QuillCodeLabeledTextField(
                title: "SSH address",
                placeholder: "user@host",
                text: $coordinator.draft.manualAddress,
                footer: "Use user@host, a Host alias, or an ssh:// URL.",
                accessibilityIdentifier: "quillcode-ssh-manual-address"
            )
            .focused($focusedField, equals: .manualAddress)
        }
    }

    private var configuredHosts: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                TextField("Search SSH hosts", text: $coordinator.draft.query)
                    .textFieldStyle(.roundedBorder)
                    .quillCodeTextEntryTarget()
                    .focused($focusedField, equals: .search)
                    .accessibilityIdentifier("quillcode-ssh-host-search")
                Button(action: onRetry) {
                    Image(systemName: "arrow.clockwise")
                        .quillCodeIconButtonTarget()
                }
                .buttonStyle(QuillCodePressableButtonStyle())
                .disabled(coordinator.draft.hostLoad.isLoading)
                .help("Refresh SSH hosts")
                .accessibilityLabel("Refresh SSH hosts")
                .accessibilityIdentifier("quillcode-ssh-refresh")
            }
            configuredHostContent
            Text(coordinator.draft.hostLoad.configPath)
                .font(.caption2.monospaced())
                .foregroundStyle(QuillCodePalette.muted)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(coordinator.draft.hostLoad.configPath)
        }
    }

    @ViewBuilder
    private var configuredHostContent: some View {
        if coordinator.draft.hostLoad.isLoading {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Reading SSH configuration…")
                    .foregroundStyle(QuillCodePalette.muted)
            }
            .frame(maxWidth: .infinity, minHeight: 210)
        } else if coordinator.draft.filteredHosts.isEmpty {
            QuillCodeDialogEmptyState(
                systemImage: "network",
                title: coordinator.draft.hostLoad.hosts.isEmpty ? "No SSH hosts found" : "No matching hosts",
                subtitle: coordinator.draft.hostLoad.hosts.isEmpty
                    ? "Add a concrete Host alias to ~/.ssh/config or use Manual."
                    : "Try another alias or resolved address."
            )
            .frame(minHeight: 210, maxHeight: 210)
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(coordinator.draft.filteredHosts) { host in
                        hostRow(host)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 210)
        }
    }

    private func hostRow(_ host: SSHHostConfiguration) -> some View {
        let isSelected = coordinator.draft.selectedHostID == host.id
        return Button {
            coordinator.selectHost(host)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "desktopcomputer")
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? QuillCodePalette.blue : QuillCodePalette.muted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(host.alias)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(QuillCodePalette.text)
                    Text(host.resolvedAddress)
                        .font(.caption.monospaced())
                        .foregroundStyle(QuillCodePalette.muted)
                        .lineLimit(1)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(QuillCodePalette.blue)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .background(isSelected ? QuillCodePalette.selection : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .quillCodeFullRowButtonTarget(minHeight: 50, radius: 8)
        .accessibilityIdentifier("quillcode-ssh-host-\(host.id)")
    }

    private var projectFields: some View {
        HStack(alignment: .top, spacing: QuillCodeMetrics.controlClusterSpacing) {
            QuillCodeLabeledTextField(
                title: "Remote project folder",
                placeholder: "~/project",
                text: $coordinator.draft.remotePath,
                footer: "Absolute or home-relative path.",
                accessibilityIdentifier: "quillcode-ssh-remote-path",
                onSubmit: connectIfPossible
            )
            .focused($focusedField, equals: .remotePath)
            QuillCodeLabeledTextField(
                title: "Project name",
                placeholder: "Optional",
                text: $coordinator.draft.projectName,
                footer: "Defaults to the remote folder.",
                accessibilityIdentifier: "quillcode-ssh-project-name",
                onSubmit: connectIfPossible
            )
        }
    }

    @ViewBuilder
    private var statusMessage: some View {
        if let error = coordinator.draft.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(QuillCodePalette.red)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("quillcode-ssh-error")
        } else if let warning = coordinator.draft.hostLoad.warnings.first {
            Label(warning, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(QuillCodePalette.yellow)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            Text("QuillCode checks the connection before adding the project.")
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
            Spacer()
            Button("Cancel", action: onCancel)
                .buttonStyle(QuillCodeActionButtonStyle())
                .quillCodeFormActionTarget()
            Button(action: connectIfPossible) {
                HStack(spacing: 7) {
                    if coordinator.draft.isConnecting {
                        ProgressView().controlSize(.small)
                    }
                    Text(coordinator.draft.isConnecting ? "Connecting" : "Connect")
                }
            }
            .buttonStyle(QuillCodeActionButtonStyle(.primary, minWidth: 112))
            .quillCodeFormActionTarget(minWidth: 112)
            .keyboardShortcut(.defaultAction)
            .disabled(!coordinator.draft.canConnect)
            .accessibilityIdentifier("quillcode-ssh-connect")
        }
    }

    private func focusInitialField() {
        DispatchQueue.main.async {
            focusedField = coordinator.draft.mode == .configured ? .search : .manualAddress
        }
    }

    private func connectIfPossible() {
        guard coordinator.draft.canConnect else { return }
        onConnect()
    }
}
