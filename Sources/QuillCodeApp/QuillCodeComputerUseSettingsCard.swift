import SwiftUI

struct QuillCodeComputerUseSettingsCard: View {
    var settings: WorkspaceSettingsSurface
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader
            requirementRows
            nextActionRow
            restartHint
            refreshAction
        }
        .padding(14)
        .background(QuillCodePalette.panel.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(statusTint.opacity(0.28), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 8)
    }

    private var statusTint: Color {
        settings.computerUseStatus.available ? QuillCodePalette.green : QuillCodePalette.yellow
    }

    private var cardHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Computer Use")
                    .font(.headline)
                Text(settings.computerUseSetupSummary)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)
            Spacer()
            Text(settings.computerUseStatusLabel)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(statusTint.opacity(0.16))
                .foregroundStyle(statusTint)
                .clipShape(Capsule())
        }
    }

    private var requirementRows: some View {
        VStack(spacing: 8) {
            ForEach(settings.computerUseRequirements) { requirement in
                QuillCodePermissionRow(requirement: requirement, onCommand: onCommand)
            }
        }
    }

    private var nextActionRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: settings.computerUseStatus.available ? "checkmark.circle.fill" : "arrow.forward.circle.fill")
                .foregroundStyle(settings.computerUseStatus.available ? QuillCodePalette.green : QuillCodePalette.blue)
                .frame(width: 18)
            Text(settings.computerUseNextAction)
                .font(.caption)
                .foregroundStyle(settings.computerUseStatus.available ? QuillCodePalette.green : QuillCodePalette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(QuillCodePalette.background.opacity(0.48))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var restartHint: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(QuillCodePalette.blue)
                .frame(width: 18)
            Text("After changing macOS permissions, quit and reopen QuillCode if the status does not update.")
                .font(.caption2)
                .foregroundStyle(QuillCodePalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var refreshAction: some View {
        HStack {
            Button("Refresh status") {
                onCommand(settings.computerUseRefreshCommand)
            }
            .buttonStyle(QuillCodePressableButtonStyle())
            .quillCodeHitTarget(minWidth: 112, alignment: .leading)
            Spacer()
        }
        .font(.caption.weight(.semibold))
    }
}

private struct QuillCodePermissionRow: View {
    var requirement: ComputerUseRequirementSurface
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconTint.opacity(0.14))
                Image(systemName: requirement.isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(iconTint)
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(requirement.title)
                    .font(.callout.weight(.semibold))
                Text(requirement.detail)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)
            Spacer(minLength: 12)
            if requirement.isGranted {
                Text(requirement.statusLabel)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(QuillCodePalette.green)
            } else {
                Button("Open") {
                    onCommand(requirement.command)
                }
                .buttonStyle(.bordered)
                .disabled(!requirement.command.isEnabled)
                .controlSize(.small)
                .frame(minWidth: 72, minHeight: QuillCodeMetrics.minimumHitTarget)
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.16))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var iconTint: Color {
        requirement.isGranted ? QuillCodePalette.green : QuillCodePalette.yellow
    }
}
