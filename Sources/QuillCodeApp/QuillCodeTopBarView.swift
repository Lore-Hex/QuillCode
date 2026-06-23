import SwiftUI
import QuillCodeCore

struct QuillCodeTopBarView: View {
    var topBar: TopBarSurface
    var commands: [WorkspaceCommandSurface]
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 12) {
                contextLabel
                    .layoutPriority(1)

                threadTitle
                    .layoutPriority(3)

                commandMenu
                    .layoutPriority(2)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: QuillCodeMetrics.topBarHeight)

            if showsActivityHairline {
                Rectangle()
                    .fill(activityHairlineColor)
                    .frame(height: 2)
                    .accessibilityHidden(true)
            }
        }
        .background(QuillCodePalette.background)
        .help(topBarHelp)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(topBarAccessibilityLabel)
    }

    private var contextLabel: some View {
        Text(topBar.subtitle)
            .font(.caption)
            .foregroundStyle(QuillCodePalette.muted)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: 240, alignment: .leading)
    }

    private var threadTitle: some View {
        Text(topBar.primaryTitle)
            .font(.headline.weight(.semibold))
            .foregroundStyle(QuillCodePalette.text)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var agentStatus: TopBarStatusPresentation {
        topBar.agentStatusPresentation
    }

    private var runtimeIssue: TopBarRuntimeIssuePresentation? {
        topBar.runtimeIssuePresentation
    }

    private var showsActivityHairline: Bool {
        agentStatus.showsIndicator || runtimeIssue != nil
    }

    private var activityHairlineColor: Color {
        if let runtimeIssue {
            return runtimeIssueColor(for: runtimeIssue.tone)
        }
        return statusColor(for: agentStatus.tone)
    }

    private var topBarHelp: String {
        var parts = [topBar.subtitle, agentStatus.accessibilityLabel]
        if let runtimeIssue {
            parts.append("Issue: \(runtimeIssue.label)")
        }
        return parts.joined(separator: ". ")
    }

    private var topBarAccessibilityLabel: String {
        var label = "\(topBar.primaryTitle), \(topBar.subtitle), \(agentStatus.accessibilityLabel)"
        if let runtimeIssue {
            label += ", issue: \(runtimeIssue.label)"
        }
        return label
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
                .background(QuillCodePalette.selection.opacity(0.22))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .help("More")
        .accessibilityLabel("More workspace actions")
    }
}

struct QuillCodeModePickerButton: View {
    var modeLabel: String
    var onSetMode: (AgentMode) -> Void

    private var selectedMode: AgentMode {
        AgentMode.allCases.first { $0.title == modeLabel } ?? .auto
    }

    private var orderedModes: [AgentMode] {
        [.auto, .review, .readOnly]
    }

    private var selectedModeColor: Color {
        switch selectedMode {
        case .auto:
            return QuillCodePalette.green
        case .review:
            return QuillCodePalette.yellow
        case .readOnly:
            return QuillCodePalette.muted
        }
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
            .frame(minHeight: QuillCodeMetrics.minimumHitTarget)
            .background(QuillCodePalette.selection.opacity(0.62))
            .overlay {
                Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1)
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .help("Choose Auto safety mode")
        .accessibilityLabel("Auto safety mode, \(modeLabel)")
    }
}
