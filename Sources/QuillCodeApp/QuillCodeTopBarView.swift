import SwiftUI
import QuillCodeCore

struct QuillCodeTopBarView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var topBar: TopBarSurface
    var commands: [WorkspaceCommandSurface]
    var leadingInset: CGFloat = 0
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 12) {
                if leadingInset > 0 {
                    Color.clear
                        .frame(width: leadingInset)
                        .accessibilityHidden(true)
                }

                identityGroup
                    .layoutPriority(3)

                Spacer(minLength: 8)

                topBarActions
                    .layoutPriority(2)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: QuillCodeMetrics.topBarHeight)

            if showsActivityHairline {
                Rectangle()
                    .fill(activityHairlineColor)
                    .frame(height: 1)
                    .accessibilityHidden(true)
            }
        }
        .background(QuillCodePalette.background)
        .help(topBarHelp)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(topBarAccessibilityLabel)
    }

    private var identityGroup: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(topBar.primaryTitle)
                .font(.headline.weight(.semibold))
                .foregroundStyle(QuillCodePalette.text)
                .lineLimit(1)
                .truncationMode(.tail)

            Text(topBar.subtitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var activeStopCommand: WorkspaceCommandSurface? {
        commands.first { $0.id == "stop-all" && $0.isEnabled }
    }

    private var topBarActions: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            if let activeStopCommand {
                stopButton(activeStopCommand)
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.94)))
            }
            commandMenu
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: activeStopCommand?.id)
    }

    private func stopButton(_ command: WorkspaceCommandSurface) -> some View {
        Button {
            onCommand(command)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "stop.fill")
                    .font(.caption.weight(.bold))
                    .accessibilityHidden(true)
                Text("Stop")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .quillCodeTextButtonTarget(minWidth: 64, radius: QuillCodeMetrics.minimumHitTarget / 2)
            .background(QuillCodePalette.red.opacity(0.90))
            .overlay {
                Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1)
            }
            .clipShape(Capsule())
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .help("Stop active work")
        .accessibilityLabel("Stop active work")
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
                .quillCodeIconButtonTarget()
                .background(QuillCodePalette.selection.opacity(0.22))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
            .quillCodeCapsuleButtonTarget()
            .background(QuillCodePalette.selection.opacity(0.62))
            .overlay {
                Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1)
            }
            .clipShape(Capsule())
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .help("Choose Auto safety mode")
        .accessibilityLabel("Auto safety mode, \(modeLabel)")
    }
}
