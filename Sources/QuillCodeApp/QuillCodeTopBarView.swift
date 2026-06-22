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

            HStack(spacing: 8) {
                QuillCodeModelPickerView(
                    topBar: topBar,
                    isPresented: $isModelPickerPresented,
                    onSetMode: onSetMode,
                    onSetModel: onSetModel,
                    onToggleModelFavorite: onToggleModelFavorite
                )
                .layoutPriority(2)

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
        HStack(spacing: 8) {
            if showsStatusDot {
                Circle()
                    .fill(statusTint)
                    .frame(width: 8, height: 8)
                    .help(topBar.agentStatus)
                    .accessibilityLabel("Agent status: \(topBar.agentStatus)")
            }
            if let runtimeIssueLabel = topBar.runtimeIssueLabel {
                QuillCodeTopBarPill(
                    text: runtimeIssueLabel,
                    systemImage: "exclamationmark.triangle",
                    tint: topBar.runtimeIssueSeverity == .error ? QuillCodePalette.red : QuillCodePalette.yellow,
                    maxWidth: 180,
                    layoutPriority: 2
                )
                .help(runtimeIssueLabel)
            }
        }
        .frame(minWidth: 0, alignment: .trailing)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var showsStatusDot: Bool {
        let lowercasedStatus = topBar.agentStatus.lowercased()
        return lowercasedStatus.contains("fail")
            || lowercasedStatus.contains("error")
            || lowercasedStatus.contains("run")
            || lowercasedStatus.contains("work")
    }

    private var statusTint: Color {
        let lowercasedStatus = topBar.agentStatus.lowercased()
        if lowercasedStatus.contains("fail") || lowercasedStatus.contains("error") {
            return QuillCodePalette.red
        }
        if lowercasedStatus.contains("run") || lowercasedStatus.contains("work") {
            return QuillCodePalette.yellow
        }
        return QuillCodePalette.green
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
