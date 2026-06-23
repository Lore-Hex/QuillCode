import SwiftUI
import QuillCodeCore

struct QuillCodeTopBarView: View {
    var topBar: TopBarSurface
    var commands: [WorkspaceCommandSurface]
    @Binding var isModelPickerPresented: Bool
    var onSetMode: (AgentMode) -> Void
    var onSetModel: (String) -> Void
    var onToggleModelFavorite: (String) -> Void
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        HStack(spacing: 12) {
            identityCluster
                .layoutPriority(3)

            Spacer(minLength: 10)

            HStack(spacing: 12) {
                QuillCodeModelPickerView(
                    topBar: topBar,
                    isPresented: $isModelPickerPresented,
                    onSetModel: onSetModel,
                    onToggleModelFavorite: onToggleModelFavorite
                )
                .layoutPriority(2)

                QuillCodeModePickerButton(
                    modeLabel: topBar.modeLabel,
                    onSetMode: onSetMode
                )

                statusIndicator
                commandMenu
            }
            .frame(minWidth: 0, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(QuillCodePalette.panel)
    }

    private var identityCluster: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(topBar.primaryTitle)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(minWidth: 0, alignment: .leading)
        .help(topBar.subtitle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(topBar.primaryTitle), \(topBar.subtitle)")
    }

    private var statusIndicator: some View {
        let status = topBar.agentStatusPresentation
        return HStack(spacing: 8) {
            if status.showsIndicator {
                Circle()
                    .fill(statusColor(for: status.tone))
                    .frame(width: 8, height: 8)
                    .help(status.label)
                    .accessibilityLabel(status.accessibilityLabel)
            }
            if let issue = topBar.runtimeIssuePresentation {
                QuillCodeTopBarPill(
                    text: issue.label,
                    systemImage: "exclamationmark.triangle",
                    tint: runtimeIssueColor(for: issue.tone),
                    maxWidth: 180,
                    layoutPriority: 2
                )
                .help(issue.label)
            }
        }
        .frame(minWidth: 0, alignment: .trailing)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func statusColor(for tone: TopBarStatusTone) -> Color {
        switch tone {
        case .failed:
            return QuillCodePalette.red
        case .running:
            return QuillCodePalette.yellow
        case .stopped:
            return QuillCodePalette.muted
        case .idle:
            return QuillCodePalette.green
        }
    }

    private func runtimeIssueColor(for tone: TopBarRuntimeIssueTone) -> Color {
        switch tone {
        case .error:
            return QuillCodePalette.red
        case .warning:
            return QuillCodePalette.yellow
        }
    }

    private var overflowCommands: [WorkspaceCommandSurface] {
        TopBarOverflowCommandCatalog.commands(
            from: commands,
            showsComputerUseSetup: topBar.showsComputerUseSetup
        )
    }

    private var commandMenu: some View {
        Menu {
            ForEach(overflowCommands) { command in
                Button {
                    onCommand(command)
                } label: {
                    if let shortcut = command.shortcut {
                        Text("\(command.title)  \(shortcut)")
                    } else {
                        Text(command.title)
                    }
                }
                .disabled(!command.isEnabled)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(QuillCodePalette.muted)
                .frame(width: QuillCodeMetrics.minimumHitTarget, height: QuillCodeMetrics.minimumHitTarget)
                .background(QuillCodePalette.selection.opacity(0.52))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .help("More")
        .accessibilityLabel("More workspace actions")
    }
}

private struct QuillCodeModePickerButton: View {
    var modeLabel: String
    var onSetMode: (AgentMode) -> Void

    private var selectedMode: AgentMode {
        AgentMode.allCases.first { $0.title == modeLabel } ?? .auto
    }

    private var orderedModes: [AgentMode] {
        [.auto, .review, .readOnly]
    }

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
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(modeColor(for: selectedMode))
                    .frame(width: 7, height: 7)
                Text(modeLabel)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(QuillCodePalette.muted)
            }
            .foregroundStyle(modeColor(for: selectedMode))
            .padding(.horizontal, 10)
            .frame(minHeight: QuillCodeMetrics.minimumHitTarget)
            .background(modeColor(for: selectedMode).opacity(0.12))
            .overlay {
                Capsule()
                    .stroke(modeColor(for: selectedMode).opacity(0.24), lineWidth: 1)
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .help("Choose approval mode")
        .accessibilityLabel("Approval mode, \(modeLabel)")
    }

    private func modeColor(for mode: AgentMode) -> Color {
        switch mode {
        case .auto:
            return QuillCodePalette.green
        case .review:
            return QuillCodePalette.yellow
        case .readOnly:
            return QuillCodePalette.blue
        }
    }
}

private struct QuillCodeTopBarPill: View {
    var text: String
    var systemImage: String
    var tint: Color = QuillCodePalette.blue
    var maxWidth: CGFloat?
    var layoutPriority: Double = 0

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.monospacedDigit().weight(.medium))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: maxWidth, minHeight: 32)
            .layoutPriority(layoutPriority)
            .background(tint.opacity(0.14))
            .foregroundStyle(tint)
            .overlay {
                Capsule()
                    .stroke(tint.opacity(0.22), lineWidth: 1)
            }
            .clipShape(Capsule())
    }
}
